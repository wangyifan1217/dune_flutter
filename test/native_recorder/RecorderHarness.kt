package nova.dunes.dunes_app

import android.media.FakeAudio
import java.nio.file.Files
import java.io.File

fun main() {
    val root = Files.createTempDirectory("meeting-recorder-tests").toFile()
    var count = 0
    fun scenario(name: String, run: () -> Unit) {
        FakeAudio.reset()
        run()
        count++
        println("PASS $name")
    }
    fun encoder(name: String) = StreamingAacM4aEncoder(File(root, "$name.m4a").path, 16000, 1)
    try {
        scenario("meeting continues writing every PCM chunk when the first AAC write fails") {
            var originalBytes = 0
            var attempts = 0
            var failures = 0
            val sink = MeetingPcmSink(
                writeOriginal = { _, _, length -> originalBytes += length },
                writeEncoded = { _, _, _ -> attempts++; error("injected first-frame failure") },
                onEncodingFailure = { failures++ },
            )
            repeat(3) { sink.write(ByteArray(32000), 0, 32000) }
            check(originalBytes == 96000 && attempts == 1 && failures == 1)
        }
        scenario("meeting PCM disk failure propagates and is not classified as a codec failure") {
            var encoded = false
            var codecError = false
            val sink = MeetingPcmSink(
                writeOriginal = { _, _, _ -> throw java.io.IOException("disk full") },
                writeEncoded = { _, _, _ -> encoded = true },
                onEncodingFailure = { codecError = true },
            )
            check(runCatching { sink.write(ByteArray(100), 0, 100) }.exceptionOrNull() is java.io.IOException)
            check(!encoded && !codecError)
        }
        scenario("normal meeting writes original PCM before each encoded chunk") {
            val order = mutableListOf<String>()
            val sink = MeetingPcmSink(
                writeOriginal = { _, _, _ -> order.add("pcm") },
                writeEncoded = { _, _, _ -> order.add("aac") },
                onEncodingFailure = { error("unexpected failure") },
            )
            repeat(2) { sink.write(ByteArray(100), 0, 100) }
            check(order == listOf("pcm", "aac", "pcm", "aac"))
        }
        scenario("AAC startup failure leaves meeting PCM recording enabled") {
            var originalBytes = 0
            val sink = MeetingPcmSink(
                writeOriginal = { _, _, length -> originalBytes += length },
                writeEncoded = { _, _, _ -> error("disabled codec must not run") },
                onEncodingFailure = { error("unexpected callback") },
            )
            sink.disableEncoding()
            sink.write(ByteArray(100), 0, 100)
            check(originalBytes == 100)
        }
        scenario("short recording filters configuration and waits for delayed output EOS") {
            val encoder = encoder("short")
            encoder.start(); encoder.writePcm(ByteArray(8000), 0, 8000)
            check(encoder.finish())
            check(FakeAudio.muxer!!.configurationSamples == 0)
            check(FakeAudio.muxer!!.samples == 3) // two PCM chunks plus delayed final audio
            check(FakeAudio.muxer!!.stopped && FakeAudio.muxer!!.released)
            check(encoder.finish())
        }
        scenario("missing output EOS cannot be reported as a successful file") {
            FakeAudio.neverEos = true
            val encoder = encoder("no-eos")
            encoder.start(); encoder.writePcm(ByteArray(100), 0, 100)
            check(!encoder.finish())
            check(FakeAudio.codec!!.released && FakeAudio.muxer!!.released)
        }
        scenario("muxer finalization failure is not success") {
            FakeAudio.failMuxerStop = true
            val encoder = encoder("muxer-failure")
            encoder.start(); encoder.writePcm(ByteArray(100), 0, 100)
            check(!encoder.finish())
            check(FakeAudio.muxer!!.released)
        }
        scenario("sample write exception releases the output buffer") {
            FakeAudio.failWrite = true
            val encoder = encoder("write-failure")
            encoder.start()
            check(runCatching { encoder.writePcm(ByteArray(100), 0, 100) }.isFailure)
            check(FakeAudio.codec!!.releasedOutputs == 2)
            encoder.abort()
            check(!File(root, "write-failure.m4a").exists())
        }
        scenario("codec release failure does not skip muxer finalization") {
            FakeAudio.failCodecRelease = true
            val encoder = encoder("release-failure")
            encoder.start(); encoder.writePcm(ByteArray(100), 0, 100)
            check(encoder.finish())
            check(FakeAudio.muxer!!.stopped && FakeAudio.muxer!!.released)
        }
        scenario("startup failure releases partially initialized codec") {
            FakeAudio.failConfigure = true
            check(runCatching { encoder("start-failure").start() }.isFailure)
            check(FakeAudio.codec!!.released)
        }
        scenario("stalled input times out instead of blocking capture indefinitely") {
            FakeAudio.stallInput = true
            val encoder = encoder("input-stall")
            encoder.start()
            val before = System.nanoTime()
            check(runCatching { encoder.writePcm(ByteArray(100), 0, 100) }.isFailure)
            check(System.nanoTime() - before < 4_000_000_000L)
            encoder.abort()
        }
        val wav = File(root, "original.wav")
        CrashSafeWavWriter(wav.path).apply { write(ByteArray(8000) { 1 }, 0, 8000); close() }
        val original = wav.readBytes()
        scenario("WAV conversion failure preserves original and removes invalid compressed output") {
            FakeAudio.failWrite = true
            val target = File(root, "failed-conversion.m4a")
            check(!WavToM4aConverter.convert(wav.path, target.path))
            check(wav.readBytes().contentEquals(original))
            check(!target.exists())
        }
        scenario("WAV compression uses the same delayed EOS handling") {
            check(WavToM4aConverter.convert(wav.path, File(root, "converted.m4a").path))
            check(FakeAudio.muxer!!.configurationSamples == 0)
            check(wav.readBytes().contentEquals(original))
        }
        println("$count native codec scenarios passed")
    } finally {
        root.deleteRecursively()
    }
}
