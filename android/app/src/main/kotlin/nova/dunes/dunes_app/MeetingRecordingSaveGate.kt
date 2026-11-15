package nova.dunes.dunes_app

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Select once: normal encoded result or the already durable PCM after a deadline. */
internal class MeetingRecordingSaveGate(private val fallbackPath: String) {
    private val ready = CountDownLatch(1)
    private var closed = false
    private var encodedPath: String? = null

    @Synchronized
    fun complete(path: String?): Boolean {
        if (closed) return false
        encodedPath = path
        ready.countDown()
        return true
    }

    fun awaitPath(timeoutMs: Long): String {
        try {
            ready.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        synchronized(this) {
            closed = true
            return encodedPath ?: fallbackPath
        }
    }
}
