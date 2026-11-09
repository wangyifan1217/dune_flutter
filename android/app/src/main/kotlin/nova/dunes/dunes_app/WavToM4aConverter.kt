package nova.dunes.dunes_app

import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** WAV upload compression shares the same bounded AAC drain/finish as live recording. */
object WavToM4aConverter {
    fun convert(inputPath: String, outputPath: String): Boolean {
        if (inputPath == outputPath) return false
        val input = File(inputPath)
        if (!input.exists() || input.length() <= 44) return false
        var encoder: StreamingAacM4aEncoder? = null
        var success = false
        try {
            FileInputStream(input).use { stream ->
                val header = ByteArray(44)
                if (stream.read(header) != 44) return false
                val buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
                buffer.position(22)
                val channels = buffer.short.toInt().coerceAtLeast(1)
                val sampleRate = buffer.int.coerceAtLeast(8000)
                buffer.position(34)
                if (buffer.short.toInt() != 16) return false
                val active = StreamingAacM4aEncoder(outputPath, sampleRate, channels)
                encoder = active
                active.start()
                val frameBytes = channels * 2
                val pcm = ByteArray(4096 - 4096 % frameBytes)
                while (true) {
                    val read = stream.read(pcm)
                    if (read <= 0) break
                    val usable = read - read % frameBytes
                    if (usable > 0) active.writePcm(pcm, 0, usable)
                }
                success = active.finish()
                return success
            }
        } catch (e: Exception) {
            Log.w("DunesRecorder", "WAV compression failed; keep source WAV", e)
            return false
        } finally {
            if (!success) encoder?.abort()
        }
    }
}
