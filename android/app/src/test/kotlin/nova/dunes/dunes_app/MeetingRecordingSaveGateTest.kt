package nova.dunes.dunes_app

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class MeetingRecordingSaveGateTest {
    @Test fun normalFinalizationReturnsExistingM4a() {
        val gate = MeetingRecordingSaveGate("original.wav")
        assertTrue(gate.complete("recorded.m4a"))
        assertEquals("recorded.m4a", gate.awaitPath(3500))
    }

    @Test fun encoderFailureReturnsOriginal() {
        val gate = MeetingRecordingSaveGate("original.wav")
        gate.complete(null)
        assertEquals("original.wav", gate.awaitPath(3500))
    }

    @Test fun hungFinalizationReturnsOriginalAndRejectsLateResult() {
        val gate = MeetingRecordingSaveGate("original.wav")
        assertEquals("original.wav", gate.awaitPath(10))
        assertFalse(gate.complete("late.m4a"))
        assertEquals("original.wav", gate.awaitPath(0))
    }

    @Test fun normalCompletionWakesWaiterWithoutWaitingForDeadline() {
        val gate = MeetingRecordingSaveGate("original.wav")
        val returned = CountDownLatch(1)
        var path: String? = null
        val waiter = Thread {
            path = gate.awaitPath(10000)
            returned.countDown()
        }
        waiter.start()
        gate.complete("recorded.m4a")
        assertTrue(returned.await(2, TimeUnit.SECONDS))
        waiter.join()
        assertEquals("recorded.m4a", path)
    }
}
