package nova.dunes.dunes_app

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 将 16-bit PCM WAV 转为 AAC/m4a，用于会议录音上传前压缩。
 */
object WavToM4aConverter {
    private const val TIMEOUT_US = 10_000L
    /** 16k 单声道语音：32kbps 体积约为 WAV 的 1/16，ASR 可接受。 */
    private const val BIT_RATE = 32_000

    fun convert(inputPath: String, outputPath: String): Boolean {
        val input = File(inputPath)
        if (!input.exists() || input.length() <= 44) return false

        FileInputStream(input).use { stream ->
            val header = ByteArray(44)
            if (stream.read(header) != 44) return false
            val buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
            buffer.position(22)
            val channels = buffer.short.toInt().coerceAtLeast(1)
            val sampleRate = buffer.int.coerceAtLeast(8000)
            buffer.position(34)
            val bitsPerSample = buffer.short.toInt().coerceAtLeast(16)
            if (bitsPerSample != 16) return false

            val format = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                sampleRate,
                channels,
            )
            format.setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
            format.setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()

            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var muxerTrack = -1
            var muxerStarted = false
            val info = MediaCodec.BufferInfo()
            var presentationUs = 0L
            val bytesPerSample = bitsPerSample / 8
            val frameBytes = channels * bytesPerSample
            val pcmBuf = ByteArray(4096)
            var inputDone = false
            var outputDone = false

            try {
                while (!outputDone) {
                    if (!inputDone) {
                        val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                        if (inIndex >= 0) {
                            val inBuf = codec.getInputBuffer(inIndex) ?: continue
                            inBuf.clear()
                            val read = stream.read(pcmBuf)
                            if (read <= 0) {
                                codec.queueInputBuffer(
                                    inIndex,
                                    0,
                                    0,
                                    presentationUs,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputDone = true
                            } else {
                                val usable = read - (read % frameBytes)
                                if (usable <= 0) {
                                    codec.queueInputBuffer(inIndex, 0, 0, presentationUs, 0)
                                } else {
                                    inBuf.put(pcmBuf, 0, usable)
                                    val durationUs =
                                        usable * 1_000_000L / (sampleRate * frameBytes)
                                    codec.queueInputBuffer(
                                        inIndex,
                                        0,
                                        usable,
                                        presentationUs,
                                        0,
                                    )
                                    presentationUs += durationUs
                                }
                            }
                        }
                    }

                    val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                    when {
                        outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (muxerStarted) return false
                            muxerTrack = muxer.addTrack(codec.outputFormat)
                            muxer.start()
                            muxerStarted = true
                        }
                        outIndex >= 0 -> {
                            val outBuf = codec.getOutputBuffer(outIndex)
                            if (outBuf != null && info.size > 0 && muxerStarted) {
                                outBuf.position(info.offset)
                                outBuf.limit(info.offset + info.size)
                                muxer.writeSampleData(muxerTrack, outBuf, info)
                            }
                            codec.releaseOutputBuffer(outIndex, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                outputDone = true
                            }
                        }
                    }
                }
                return muxerStarted && File(outputPath).exists() && File(outputPath).length() > 0
            } finally {
                try {
                    codec.stop()
                } catch (_: Exception) {
                }
                codec.release()
                try {
                    if (muxerStarted) muxer.stop()
                } catch (_: Exception) {
                }
                muxer.release()
            }
        }
    }
}
