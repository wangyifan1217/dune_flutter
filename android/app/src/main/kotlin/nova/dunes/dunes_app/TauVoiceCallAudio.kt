package nova.dunes.dunes_app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** PCM-only capture route for the τ phone; independent from the file recorder. */
class TauVoiceCallAudio(
    context: Context,
    messenger: BinaryMessenger,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var streamSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var priorAudioMode = AudioManager.MODE_NORMAL
    @Volatile private var capturing = false
    private val notificationHangupReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != TauVoiceCallForegroundService.ACTION_NOTIFICATION_HANGUP) return
            stop()
            mainHandler.post {
                eventSink?.success(
                    mapOf(
                        "kind" to "hangup",
                        "source" to "notification",
                    ),
                )
            }
        }
    }

    init {
        registerNotificationHangupReceiver()
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "stop", "cancel" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, PCM_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                streamSink = events
            }

            override fun onCancel(arguments: Any?) {
                streamSink = null
            }
        })
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun start(result: MethodChannel.Result) {
        if (capturing) {
            result.success(null)
            return
        }
        if (ContextCompat.checkSelfPermission(appContext, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("VOICE_CALL_PERMISSION_DENIED", "microphone denied", null)
            return
        }
        try {
            TauVoiceCallForegroundService.start(appContext)
            priorAudioMode = audioManager.mode
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            requestAudioFocus()
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val bufferSize = maxOf(minBuffer * 2, SAMPLE_RATE / 5 * BYTES_PER_FRAME)
            val record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                throw IllegalStateException("VOICE_COMMUNICATION AudioRecord init failed")
            }
            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(record.audioSessionId)?.also { it.enabled = true }
            }
            audioRecord = record
            record.startRecording()
            capturing = true
            captureThread = Thread { captureLoop(bufferSize) }.also {
                it.name = "tau-voice-pcm"
                it.start()
            }
            result.success(null)
        } catch (e: Exception) {
            stop()
            result.error("VOICE_CALL_START_FAILED", e.message, null)
        }
    }

    private fun captureLoop(bufferSize: Int) {
        val buffer = ByteArray(bufferSize)
        while (capturing) {
            val read = try {
                audioRecord?.read(buffer, 0, buffer.size) ?: AudioRecord.ERROR_INVALID_OPERATION
            } catch (_: Exception) {
                AudioRecord.ERROR_INVALID_OPERATION
            }
            if (read > 0) {
                val pcm = buffer.copyOf(read - (read % BYTES_PER_FRAME))
                if (pcm.isNotEmpty()) {
                    mainHandler.post { streamSink?.success(pcm) }
                }
            } else if (read < 0) {
                break
            }
        }
    }

    private fun stop() {
        capturing = false
        try {
            captureThread?.join(500)
        } catch (_: InterruptedException) {
        }
        captureThread = null
        echoCanceler?.release()
        echoCanceler = null
        audioRecord?.let { record ->
            try {
                if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) record.stop()
            } catch (_: IllegalStateException) {
            }
            record.release()
        }
        audioRecord = null
        abandonAudioFocus()
        audioManager.mode = priorAudioMode
        TauVoiceCallForegroundService.stop(appContext)
    }

    private fun registerNotificationHangupReceiver() {
        val filter = IntentFilter(TauVoiceCallForegroundService.ACTION_NOTIFICATION_HANGUP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(
                notificationHangupReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(notificationHangupReceiver, filter)
        }
    }

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .build()
            audioFocusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
            )
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "dunes/voice_call"
        private const val PCM_CHANNEL = "dunes/voice_call_pcm"
        private const val EVENT_CHANNEL = "dunes/voice_call_events"
        private const val SAMPLE_RATE = 16_000
        private const val BYTES_PER_FRAME = 2
    }
}
