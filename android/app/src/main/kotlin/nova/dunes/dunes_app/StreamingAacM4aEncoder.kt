package nova.dunes.dunes_app

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * 边录边编码：PCM 16-bit 实时写入 AAC/m4a，避免停止录音后再整段转码。
 */
class StreamingAacM4aEncoder(
    private val outputPath: String,
    private val sampleRate: Int,
    private val channels: Int,
    private val bitRate: Int = 32_000,
) {
    private val timeoutUs = 10_000L
    private val frameBytes = channels * 2
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var muxerTrack = -1
    private var muxerStarted = false
    private var presentationUs = 0L
    private var inputClosed = false

    fun start() {
        val format = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            sampleRate,
            channels,
        )
        format.setInteger(
            MediaFormat.KEY_AAC_PROFILE,
            MediaCodecInfo.CodecProfileLevel.AACObjectLC,
        )
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()
        codec = encoder
        muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    }

    fun writePcm(data: ByteArray, offset: Int, length: Int) {
        if (inputClosed || length <= 0) return
        var index = offset
        val end = offset + length
        while (index < end) {
            drainEncoder(endOfStream = false)
            val encoder = codec ?: return
            val inIndex = encoder.dequeueInputBuffer(timeoutUs)
            if (inIndex < 0) continue

            val inBuf = encoder.getInputBuffer(inIndex) ?: continue
            inBuf.clear()
            val chunk = minOf(inBuf.remaining(), end - index)
            val aligned = chunk - (chunk % frameBytes)
            if (aligned <= 0) {
                encoder.queueInputBuffer(inIndex, 0, 0, presentationUs, 0)
                break
            }
            inBuf.put(data, index, aligned)
            val durationUs = aligned * 1_000_000L / (sampleRate * frameBytes)
            encoder.queueInputBuffer(inIndex, 0, aligned, presentationUs, 0)
            presentationUs += durationUs
            index += aligned
        }
        drainEncoder(endOfStream = false)
    }

    fun finish(): Boolean {
        if (inputClosed) return outputLooksValid()
        inputClosed = true
        return try {
            val encoder = codec ?: return false
            var attempts = 0
            while (attempts < 8) {
                val inIndex = encoder.dequeueInputBuffer(timeoutUs)
                if (inIndex >= 0) {
                    encoder.queueInputBuffer(
                        inIndex,
                        0,
                        0,
                        presentationUs,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                    )
                    break
                }
                drainEncoder(endOfStream = true)
                attempts++
            }
            drainEncoder(endOfStream = true)
            releaseInternal(deleteOutput = false)
            outputLooksValid()
        } catch (_: Exception) {
            releaseInternal(deleteOutput = false)
            outputLooksValid()
        }
    }

    fun abort() {
        inputClosed = true
        releaseInternal(deleteOutput = true)
    }

    private fun drainEncoder(endOfStream: Boolean) {
        val encoder = codec ?: return
        val info = MediaCodec.BufferInfo()
        while (true) {
            val outIndex = encoder.dequeueOutputBuffer(info, timeoutUs)
            when {
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (muxerStarted) return
                    val mux = muxer ?: return
                    muxerTrack = mux.addTrack(encoder.outputFormat)
                    mux.start()
                    muxerStarted = true
                }
                outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> return
                outIndex >= 0 -> {
                    val outBuf = encoder.getOutputBuffer(outIndex)
                    if (outBuf != null && info.size > 0 && muxerStarted) {
                        outBuf.position(info.offset)
                        outBuf.limit(info.offset + info.size)
                        muxer?.writeSampleData(muxerTrack, outBuf, info)
                    }
                    encoder.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        return
                    }
                }
                else -> return
            }
            if (!endOfStream && outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) return
        }
    }

    private fun outputLooksValid(): Boolean {
        val file = File(outputPath)
        return file.exists() && file.length() > 0
    }

    private fun releaseInternal(deleteOutput: Boolean) {
        try {
            codec?.stop()
        } catch (_: Exception) {
        }
        codec?.release()
        codec = null
        try {
            if (muxerStarted) muxer?.stop()
        } catch (_: Exception) {
        }
        muxer?.release()
        muxer = null
        muxerStarted = false
        if (deleteOutput) {
            try {
                File(outputPath).delete()
            } catch (_: Exception) {
            }
        }
    }
}
