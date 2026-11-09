package nova.dunes.dunes_app

/** Meeting-only tee: original PCM must survive an optional encoder failure. */
internal class MeetingPcmSink(
    private val writeOriginal: (ByteArray, Int, Int) -> Unit,
    private val writeEncoded: (ByteArray, Int, Int) -> Unit,
    private val onEncodingFailure: (Exception) -> Unit,
) {
    private var encodingEnabled = true

    fun disableEncoding() { encodingEnabled = false }

    fun write(data: ByteArray, offset: Int, length: Int) {
        // Disk failures propagate to pause recording. Codec failures only disable compression.
        writeOriginal(data, offset, length)
        if (!encodingEnabled) return
        try {
            writeEncoded(data, offset, length)
        } catch (e: Exception) {
            encodingEnabled = false
            onEncodingFailure(e)
        }
    }
}
