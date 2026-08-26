package nova.dunes.dunes_app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** PCM capture and reply playback for the τ phone. */
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
    private var priorSpeakerphone = false
    @Volatile private var capturing = false
    @Volatile private var playing = false
    private var playThread: Thread? = null
    private var audioTrack: AudioTrack? = null
    private var playResult: MethodChannel.Result? = null
    private var scoStarted = false
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
    private val routeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!capturing) return
            applyOutputRoute()
        }
    }
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
            if (capturing) applyOutputRoute()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
            if (capturing) applyOutputRoute()
        }
    }

    init {
        registerNotificationHangupReceiver()
        registerRouteReceiver()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
        }
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "play" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("VOICE_CALL_PLAY_FAILED", "missing wav bytes", null)
                    } else {
                        play(bytes, result)
                    }
                }
                "stopPlayback" -> {
                    stopPlayback()
                    result.success(null)
                }
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
            priorSpeakerphone = audioManager.isSpeakerphoneOn
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            applyOutputRoute()
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

    private fun play(wavBytes: ByteArray, result: MethodChannel.Result) {
        stopPlayback()
        playResult = result
        playing = true
        playThread = Thread {
            try {
                val wav = parseWav(wavBytes)
                val channelMask = if (wav.channels == 2) {
                    AudioFormat.CHANNEL_OUT_STEREO
                } else {
                    AudioFormat.CHANNEL_OUT_MONO
                }
                val encoding = if (wav.bitsPerSample == 8) {
                    AudioFormat.ENCODING_PCM_8BIT
                } else {
                    AudioFormat.ENCODING_PCM_16BIT
                }
                val minBuf = AudioTrack.getMinBufferSize(wav.sampleRate, channelMask, encoding)
                if (minBuf <= 0) throw IllegalStateException("AudioTrack buffer init failed")
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setSampleRate(wav.sampleRate)
                            .setChannelMask(channelMask)
                            .setEncoding(encoding)
                            .build(),
                    )
                    .setBufferSizeInBytes(maxOf(minBuf, minBuf * 2))
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
                audioTrack = track
                track.play()
                var offset = 0
                val chunk = minBuf
                while (playing && offset < wav.pcm.size) {
                    val end = minOf(offset + chunk, wav.pcm.size)
                    val written = track.write(wav.pcm, offset, end - offset)
                    if (written < 0) break
                    offset += written
                }
                if (playing && track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    // Let the last buffer drain before completing.
                    Thread.sleep(80)
                }
                completePlay()
            } catch (e: Exception) {
                completePlay(e.message)
            }
        }.also {
            it.name = "tau-voice-play"
            it.start()
        }
    }

    private fun stopPlayback() {
        playing = false
        val pending = playResult
        playResult = null
        try {
            audioTrack?.pause()
        } catch (_: Exception) {
        }
        try {
            audioTrack?.stop()
        } catch (_: Exception) {
        }
        try {
            audioTrack?.release()
        } catch (_: Exception) {
        }
        audioTrack = null
        try {
            playThread?.join(300)
        } catch (_: InterruptedException) {
        }
        playThread = null
        if (pending != null) {
            mainHandler.post { pending.success(null) }
        }
    }

    private fun completePlay(error: String? = null) {
        val pending = playResult ?: return
        playResult = null
        playing = false
        mainHandler.post {
            if (error != null) {
                pending.error("VOICE_CALL_PLAY_FAILED", error, null)
            } else {
                pending.success(null)
            }
        }
    }

    private fun applyOutputRoute() {
        val wired = hasWiredHeadset()
        val bluetooth = hasBluetoothHeadset()
        if (wired) {
            stopSco()
            audioManager.isSpeakerphoneOn = false
            return
        }
        if (bluetooth) {
            audioManager.isSpeakerphoneOn = false
            startSco()
            return
        }
        stopSco()
        audioManager.isSpeakerphoneOn = true
    }

    private fun hasWiredHeadset(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
                device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    device.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    device.type == AudioDeviceInfo.TYPE_USB_DEVICE
            }
        }
        @Suppress("DEPRECATION")
        return audioManager.isWiredHeadsetOn
    }

    private fun hasBluetoothHeadset(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
                device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
            }
        }
        @Suppress("DEPRECATION")
        return audioManager.isBluetoothScoOn || audioManager.isBluetoothA2dpOn
    }

    private fun startSco() {
        if (scoStarted) return
        try {
            audioManager.startBluetoothSco()
            audioManager.isBluetoothScoOn = true
            scoStarted = true
        } catch (_: Exception) {
            scoStarted = false
        }
    }

    private fun stopSco() {
        if (!scoStarted) return
        try {
            audioManager.isBluetoothScoOn = false
            audioManager.stopBluetoothSco()
        } catch (_: Exception) {
        }
        scoStarted = false
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
        stopPlayback()
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
        stopSco()
        abandonAudioFocus()
        audioManager.isSpeakerphoneOn = priorSpeakerphone
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

    private fun registerRouteReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_HEADSET_PLUG)
            addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(routeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(routeReceiver, filter)
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

        private data class WavPcm(
            val sampleRate: Int,
            val channels: Int,
            val bitsPerSample: Int,
            val pcm: ByteArray,
        )

        private fun parseWav(bytes: ByteArray): WavPcm {
            if (bytes.size < 44 ||
                bytes[0] != 'R'.code.toByte() ||
                bytes[1] != 'I'.code.toByte() ||
                bytes[2] != 'F'.code.toByte() ||
                bytes[3] != 'F'.code.toByte()
            ) {
                throw IllegalArgumentException("not a wav file")
            }
            val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val channels = header.getShort(22).toInt().coerceAtLeast(1)
            val sampleRate = header.getInt(24).coerceAtLeast(8_000)
            val bitsPerSample = header.getShort(34).toInt().let { if (it == 8 || it == 16) it else 16 }
            var offset = 12
            var dataOffset = 44
            var dataSize = bytes.size - 44
            while (offset + 8 <= bytes.size) {
                val chunkId = String(bytes, offset, 4, Charsets.US_ASCII)
                val chunkSize = header.getInt(offset + 4)
                if (chunkId == "data") {
                    dataOffset = offset + 8
                    dataSize = chunkSize
                    break
                }
                offset += 8 + chunkSize
            }
            val end = (dataOffset + dataSize).coerceAtMost(bytes.size)
            return WavPcm(
                sampleRate = sampleRate,
                channels = channels,
                bitsPerSample = bitsPerSample,
                pcm = bytes.copyOfRange(dataOffset, end),
            )
        }
    }
}
