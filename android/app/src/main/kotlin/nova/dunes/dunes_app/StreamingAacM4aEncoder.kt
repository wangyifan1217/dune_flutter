package nova.dunes.dunes_app

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.util.concurrent.TimeUnit

/** PCM 16-bit → AAC/m4a. A successful finish includes output EOS and a finalized muxer. */
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
    private var outputEnded = false
    private var samplesWritten = 0L
    private var finishedSuccessfully = false

    fun start() {
        try {
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels)
            format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec = encoder
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            Log.i("DunesRecorder", "AAC encoder=${encoder.name} sampleRate=$sampleRate channels=$channels")
        } catch (e: Exception) {
            releaseInternal(deleteOutput = true)
            throw e
        }
    }

    @Synchronized
    fun writePcm(data: ByteArray, offset: Int, length: Int) {
        if (inputClosed || length <= 0) return
        var index = offset
        val end = offset + length
        var deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
        while (index < end) {
            check(System.nanoTime() < deadline) { "AAC encoder input timed out" }
            drainEncoder(deadline)
            val encoder = checkNotNull(codec) { "AAC encoder unavailable" }
            val inIndex = encoder.dequeueInputBuffer(timeoutUs)
            if (inIndex < 0) continue
            val inBuf = checkNotNull(encoder.getInputBuffer(inIndex)) { "AAC input buffer unavailable" }
            inBuf.clear()
            val chunk = minOf(inBuf.remaining(), end - index)
            val aligned = chunk - (chunk % frameBytes)
            check(aligned > 0) { "AAC input buffer cannot hold a PCM frame" }
            inBuf.put(data, index, aligned)
            encoder.queueInputBuffer(inIndex, 0, aligned, presentationUs, 0)
            presentationUs += aligned * 1_000_000L / (sampleRate * frameBytes)
            index += aligned
            deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
        }
        drainEncoder(deadline)
    }

    @Synchronized
    fun finish(): Boolean {
        if (inputClosed) return finishedSuccessfully && outputLooksValid()
        inputClosed = true
        var complete = false
        try {
            val encoder = checkNotNull(codec) { "AAC encoder unavailable" }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
            var inputEnded = false
            while (!outputEnded && System.nanoTime() < deadline) {
                if (!inputEnded) {
                    val inIndex = encoder.dequeueInputBuffer(timeoutUs)
                    if (inIndex >= 0) {
                        encoder.queueInputBuffer(inIndex, 0, 0, presentationUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputEnded = true
                    }
                }
                // TRY_AGAIN_LATER is not EOS. Keep draining until EOS or the total deadline.
                drainEncoder(deadline)
            }
            complete = inputEnded && outputEnded && muxerStarted && samplesWritten > 0
            if (!complete) Log.w("DunesRecorder", "AAC finish incomplete eos=$outputEnded samples=$samplesWritten")
        } catch (e: Exception) {
            Log.w("DunesRecorder", "AAC finish failed", e)
        } finally {
            val finalized = releaseInternal(deleteOutput = false)
            finishedSuccessfully = complete && finalized && outputLooksValid()
        }
        return finishedSuccessfully
    }

    @Synchronized
    fun abort() {
        inputClosed = true
        finishedSuccessfully = false
        releaseInternal(deleteOutput = true)
    }

    private fun drainEncoder(deadline: Long) {
        val encoder = codec ?: return
        val info = MediaCodec.BufferInfo()
        while (!outputEnded && System.nanoTime() < deadline) {
            val outIndex = encoder.dequeueOutputBuffer(info, timeoutUs)
            when {
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    check(!muxerStarted) { "AAC output format changed after muxer start" }
                    val mux = checkNotNull(muxer)
                    muxerTrack = mux.addTrack(encoder.outputFormat)
                    mux.start()
                    muxerStarted = true
                }
                outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> return
                outIndex >= 0 -> {
                    try {
                        // Codec initialization belongs in addTrack(outputFormat), not audio samples.
                        val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        if (!isConfig && info.size > 0) {
                            check(muxerStarted) { "AAC sample arrived before output format" }
                            val outBuf = checkNotNull(encoder.getOutputBuffer(outIndex))
                            outBuf.position(info.offset)
                            outBuf.limit(info.offset + info.size)
                            checkNotNull(muxer).writeSampleData(muxerTrack, outBuf, info)
                            samplesWritten++
                        }
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputEnded = true
                    } finally {
                        encoder.releaseOutputBuffer(outIndex, false)
                    }
                }
                outIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> continue
                else -> return
            }
        }
    }

    private fun outputLooksValid(): Boolean = File(outputPath).let { it.exists() && it.length() > 0 }

    /** Always release both resources, including when one vendor implementation throws. */
    private fun releaseInternal(deleteOutput: Boolean): Boolean {
        val encoder = codec
        codec = null
        try { encoder?.stop() } catch (e: Exception) { Log.w("DunesRecorder", "AAC codec stop failed", e) }
        try { encoder?.release() } catch (e: Exception) { Log.w("DunesRecorder", "AAC codec release failed", e) }
        val mux = muxer
        muxer = null
        var finalized = false
        try {
            if (muxerStarted && mux != null) {
                mux.stop()
                finalized = true
            }
        } catch (e: Exception) {
            Log.w("DunesRecorder", "AAC muxer stop failed", e)
        } finally {
            try { mux?.release() } catch (e: Exception) { Log.w("DunesRecorder", "AAC muxer release failed", e) }
            muxerStarted = false
        }
        if (deleteOutput) {
            try { File(outputPath).delete() } catch (_: Exception) { }
        }
        return finalized
    }
}
