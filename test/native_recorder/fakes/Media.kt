package android.media

import java.io.File
import java.nio.ByteBuffer
import java.util.ArrayDeque

/** Deterministic codec outputs; these doubles do not emulate vendor hardware. */
object FakeAudio {
    var eosDelay = 4
    var neverEos = false
    var failWrite = false
    var failConfigure = false
    var failMuxerStop = false
    var failCodecRelease = false
    var stallInput = false
    var codec: MediaCodec? = null
    var muxer: MediaMuxer? = null
    fun reset() {
        eosDelay = 4; neverEos = false; failWrite = false; failConfigure = false
        failMuxerStop = false; failCodecRelease = false; stallInput = false
        codec = null; muxer = null
    }
}
class MediaFormat {
    fun setInteger(key: String, value: Int) {}
    companion object {
        const val MIMETYPE_AUDIO_AAC = "audio/mp4a-latm"
        const val KEY_AAC_PROFILE = "aac-profile"
        const val KEY_BIT_RATE = "bitrate"
        const val KEY_MAX_INPUT_SIZE = "max-input-size"
        fun createAudioFormat(mime: String, sampleRate: Int, channels: Int) = MediaFormat()
    }
}
class MediaCodecInfo { object CodecProfileLevel { const val AACObjectLC = 2 } }
class MediaCodec {
    class BufferInfo { var offset = 0; var size = 0; var presentationTimeUs = 0L; var flags = 0 }
    private data class Output(val bytes: ByteArray, val flags: Int, val pts: Long)
    private val queued = ArrayDeque<Output>()
    private var current: Output? = null
    private var needsFormat = false
    private var configured = false
    private var inputEnded = false
    private var pollsAfterEnd = 0
    private var eosSent = false
    var released = false
    var releasedOutputs = 0
    val name = "test-aac"
    val outputFormat = MediaFormat()
    fun configure(format: MediaFormat, surface: Any?, crypto: Any?, flags: Int) {
        if (FakeAudio.failConfigure) error("injected configure failure")
    }
    fun start() {}
    fun stop() {}
    fun release() { released = true; if (FakeAudio.failCodecRelease) error("injected release failure") }
    fun dequeueInputBuffer(timeoutUs: Long): Int {
        if (FakeAudio.stallInput) { Thread.sleep(1); return -1 }
        return 0
    }
    fun getInputBuffer(index: Int): ByteBuffer = ByteBuffer.allocate(4096)
    fun queueInputBuffer(index: Int, offset: Int, size: Int, pts: Long, flags: Int) {
        if (flags and BUFFER_FLAG_END_OF_STREAM != 0) { inputEnded = true; return }
        if (!configured) {
            configured = true; needsFormat = true
            queued.add(Output(byteArrayOf(1, 2), BUFFER_FLAG_CODEC_CONFIG, 0))
        }
        if (size > 0) queued.add(Output(byteArrayOf(3, 4, 5), 0, pts))
    }
    fun dequeueOutputBuffer(info: BufferInfo, timeoutUs: Long): Int {
        if (needsFormat) { needsFormat = false; return INFO_OUTPUT_FORMAT_CHANGED }
        if (!queued.isEmpty()) return emit(queued.remove(), info)
        if (inputEnded && !eosSent && !FakeAudio.neverEos && pollsAfterEnd++ >= FakeAudio.eosDelay) {
            eosSent = true
            // Delayed final audio is deliberately returned together with EOS.
            return emit(Output(byteArrayOf(6, 7), BUFFER_FLAG_END_OF_STREAM, 999), info)
        }
        Thread.sleep(1)
        return INFO_TRY_AGAIN_LATER
    }
    private fun emit(output: Output, info: BufferInfo): Int {
        current = output; info.offset = 0; info.size = output.bytes.size
        info.flags = output.flags; info.presentationTimeUs = output.pts
        return 0
    }
    fun getOutputBuffer(index: Int): ByteBuffer? = current?.let { ByteBuffer.wrap(it.bytes) }
    fun releaseOutputBuffer(index: Int, render: Boolean) { releasedOutputs++; current = null }
    companion object {
        const val CONFIGURE_FLAG_ENCODE = 1
        const val BUFFER_FLAG_CODEC_CONFIG = 2
        const val BUFFER_FLAG_END_OF_STREAM = 4
        const val INFO_TRY_AGAIN_LATER = -1
        const val INFO_OUTPUT_FORMAT_CHANGED = -2
        const val INFO_OUTPUT_BUFFERS_CHANGED = -3
        fun createEncoderByType(mime: String): MediaCodec = MediaCodec().also { FakeAudio.codec = it }
    }
}
class MediaMuxer(path: String, format: Int) {
    object OutputFormat { const val MUXER_OUTPUT_MPEG_4 = 0 }
    private val file = File(path).also { it.writeBytes(byteArrayOf(0)) }
    var samples = 0
    var configurationSamples = 0
    var released = false
    var stopped = false
    init { FakeAudio.muxer = this }
    fun addTrack(format: MediaFormat) = 0
    fun start() {}
    fun writeSampleData(track: Int, bytes: ByteBuffer, info: MediaCodec.BufferInfo) {
        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
            configurationSamples++; error("codec configuration must not be written as an audio sample")
        }
        if (FakeAudio.failWrite) error("injected sample write failure")
        samples++; file.appendBytes(ByteArray(info.size))
    }
    fun stop() { stopped = true; if (FakeAudio.failMuxerStop) error("injected muxer stop failure") }
    fun release() { released = true }
}
