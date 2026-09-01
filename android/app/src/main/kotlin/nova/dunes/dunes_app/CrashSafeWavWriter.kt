package nova.dunes.dunes_app

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 边录边追加 WAV。文件随时可播，进程被杀后按实际长度修复头即可，
 * 不依赖 AAC muxer 的 finish()。
 */
class CrashSafeWavWriter(
    private val path: String,
    private val sampleRate: Int = 16_000,
    private val channels: Int = 1,
    private val bitsPerSample: Int = 16,
) {
    private val file = RandomAccessFile(path, "rw")
    private var dataBytes = 0
    private var writesSinceHeader = 0

    init {
        file.setLength(0)
        file.write(headerBytes(0))
    }

    @Synchronized
    fun write(data: ByteArray, offset: Int, length: Int) {
        if (length <= 0) return
        file.seek(44L + dataBytes)
        file.write(data, offset, length)
        dataBytes += length
        writesSinceHeader++
        if (writesSinceHeader >= 40) {
            rewriteHeader()
        }
    }

    @Synchronized
    fun flushHeader() {
        rewriteHeader()
    }

    @Synchronized
    fun close() {
        try {
            rewriteHeader()
        } finally {
            try {
                file.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun rewriteHeader() {
        val pos = file.filePointer
        file.seek(0)
        file.write(headerBytes(dataBytes))
        file.seek(pos)
        writesSinceHeader = 0
    }

    private fun headerBytes(dataLength: Int): ByteArray {
        return wavHeader(dataLength, sampleRate, channels, bitsPerSample)
    }

    companion object {
        fun repairHeader(path: String): Boolean {
            val file = File(path)
            if (!file.exists() || file.length() <= 44L) return false
            val dataLength = (file.length() - 44L).toInt().coerceAtLeast(0)
            return try {
                RandomAccessFile(path, "rw").use { raf ->
                    raf.seek(0)
                    raf.write(wavHeader(dataLength, 16_000, 1, 16))
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        fun durationMs(path: String): Int {
            val file = File(path)
            if (!file.exists() || file.length() <= 44L) return 0
            val dataBytes = file.length() - 44L
            return (dataBytes / 32L).toInt().coerceAtLeast(0)
        }

        private fun wavHeader(
            dataLength: Int,
            sampleRate: Int,
            channels: Int,
            bitsPerSample: Int,
        ): ByteArray {
            val byteRate = sampleRate * channels * bitsPerSample / 8
            val blockAlign = channels * bitsPerSample / 8
            val buf = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            buf.put("RIFF".toByteArray(Charsets.US_ASCII))
            buf.putInt(36 + dataLength)
            buf.put("WAVE".toByteArray(Charsets.US_ASCII))
            buf.put("fmt ".toByteArray(Charsets.US_ASCII))
            buf.putInt(16)
            buf.putShort(1)
            buf.putShort(channels.toShort())
            buf.putInt(sampleRate)
            buf.putInt(byteRate)
            buf.putShort(blockAlign.toShort())
            buf.putShort(bitsPerSample.toShort())
            buf.put("data".toByteArray(Charsets.US_ASCII))
            buf.putInt(dataLength)
            return buf.array()
        }
    }
}
