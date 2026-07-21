package nova.dunes.dunes_app

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File

/**
 * 合并多个 AAC/m4a 片段。失败时返回 false，由调用方回退到保留最大片段。
 */
object M4aSegmentMerger {
    fun merge(paths: List<String>, outputPath: String): Boolean {
        val existing = paths.mapNotNull { path ->
            val file = File(path)
            if (file.exists() && file.length() > 0) path else null
        }
        if (existing.isEmpty()) return false
        if (existing.size == 1) {
            val src = existing[0]
            if (src == outputPath) return true
            return try {
                File(outputPath).delete()
                File(src).copyTo(File(outputPath), overwrite = true)
                true
            } catch (_: Exception) {
                false
            }
        }

        var muxer: MediaMuxer? = null
        val extractors = mutableListOf<MediaExtractor>()
        return try {
            File(outputPath).parentFile?.mkdirs()
            File(outputPath).delete()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var outTrack = -1
            var presentationUs = 0L

            for (path in existing) {
                val extractor = MediaExtractor()
                extractor.setDataSource(path)
                extractors.add(extractor)

                var audioTrack = -1
                var format: MediaFormat? = null
                for (i in 0 until extractor.trackCount) {
                    val f = extractor.getTrackFormat(i)
                    val mime = f.getString(MediaFormat.KEY_MIME).orEmpty()
                    if (mime.startsWith("audio/")) {
                        audioTrack = i
                        format = f
                        break
                    }
                }
                if (audioTrack < 0 || format == null) continue
                extractor.selectTrack(audioTrack)
                if (outTrack < 0) {
                    outTrack = muxer.addTrack(format)
                    muxer.start()
                }

                val buffer = java.nio.ByteBuffer.allocate(256 * 1024)
                val info = MediaCodec.BufferInfo()
                var segmentDurationUs = 0L
                while (true) {
                    val sampleSize = extractor.readSampleData(buffer, 0)
                    if (sampleSize < 0) break
                    info.offset = 0
                    info.size = sampleSize
                    info.presentationTimeUs = presentationUs + extractor.sampleTime.coerceAtLeast(0L)
                    info.flags = extractor.sampleFlags
                    muxer.writeSampleData(outTrack, buffer, info)
                    segmentDurationUs = maxOf(segmentDurationUs, extractor.sampleTime.coerceAtLeast(0L))
                    extractor.advance()
                }
                // 片段之间留一点间隔，避免时间戳重叠。
                presentationUs += segmentDurationUs + 20_000L
            }

            if (outTrack < 0) {
                false
            } else {
                File(outputPath).exists() && File(outputPath).length() > 0
            }
        } catch (_: Exception) {
            false
        } finally {
            for (extractor in extractors) {
                try {
                    extractor.release()
                } catch (_: Exception) {
                }
            }
            try {
                muxer?.stop()
            } catch (_: Exception) {
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
        }
    }

    fun largestExistingPath(paths: List<String>): String? {
        var best: String? = null
        var bestSize = -1L
        for (path in paths) {
            val file = File(path)
            if (!file.exists()) continue
            val size = file.length()
            if (size > bestSize) {
                bestSize = size
                best = path
            }
        }
        return best
    }
}
