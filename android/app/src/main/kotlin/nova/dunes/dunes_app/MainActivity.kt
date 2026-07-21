package nova.dunes.dunes_app

import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val voiceChannel = "dunes/audio_recorder"
    private val voiceStreamChannel = "dunes/audio_recorder_stream"
    private val voiceEventsChannel = "dunes/audio_recorder_events"
    private val meetingAudioChannel = "dunes/meeting_audio"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var tpnsBridge: TpnsPushBridge? = null
    private var voiceStreamSink: EventChannel.EventSink? = null
    private var recorderEventSink: EventChannel.EventSink? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    // 16k/mono PCM 供实时转写；同时边录边编码为 AAC/m4a 供上传。
    private val sampleRate = 16000
    private val channelCount = 1
    private val bitsPerSample = 16
    private val frameBytes = channelCount * bitsPerSample / 8

    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private var streamingEncoder: StreamingAacM4aEncoder? = null
    private val segmentPaths = mutableListOf<String>()
    private var recordBufferSize: Int = 0
    @Volatile private var isRecording = false
    @Volatile private var isPaused = false
    @Volatile private var micConflictDetected = false
    private var outputPath: String? = null
    private var startedAtMs: Long = 0L
    private var accumulatedDurationMs: Long = 0L
    private var wakeLock: PowerManager.WakeLock? = null
    private var consecutiveReadErrors = 0
    /** 开录/续录后短时间内的空读不视为抢麦（设备刚就绪时常有短暂静音）。 */
    private var ignoreSilentConflictUntilMs: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tpnsBridge = TpnsPushBridge(applicationContext).also {
            it.attach(flutterEngine)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startRecord(result)
                    "pause" -> pauseRecord(result)
                    "resume" -> resumeRecord(result)
                    "stop" -> stopRecord(result, deleteFile = false)
                    "cancel" -> stopRecord(result, deleteFile = true)
                    "status" -> result.success(
                        mapOf(
                            "isRecording" to isRecording,
                            "isPaused" to isPaused,
                        )
                    )
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voiceStreamChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    voiceStreamSink = events
                }

                override fun onCancel(arguments: Any?) {
                    voiceStreamSink = null
                }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voiceEventsChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    recorderEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    recorderEventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, meetingAudioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "convertWavToM4a" -> {
                        val inputPath = call.argument<String>("inputPath")?.trim().orEmpty()
                        val outputPath = call.argument<String>("outputPath")?.trim().orEmpty()
                        if (inputPath.isEmpty() || outputPath.isEmpty()
                        ) {
                            result.error("INVALID_ARGS", "inputPath/outputPath required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val ok = WavToM4aConverter.convert(inputPath, outputPath)
                            mainHandler.post {
                                if (ok) result.success(outputPath)
                                else result.error("CONVERT_FAILED", "wav to m4a failed", null)
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun voiceRecordingDir(): File {
        // 用 filesDir，避免 cache 被系统清理导致中断后录音丢失。
        val dir = File(filesDir, "voice_recordings")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun newVoiceRecordingPath(prefix: String = "voice"): String {
        val stamp = System.currentTimeMillis()
        return File(voiceRecordingDir(), "$prefix-$stamp.m4a").absolutePath
    }

    private fun startRecord(result: MethodChannel.Result) {
        try {
            stopInternal(deleteFile = true)
            MeetingRecordingService.start(this)
            segmentPaths.clear()
            micConflictDetected = false
            consecutiveReadErrors = 0

            val m4aPath = newVoiceRecordingPath("voice")
            outputPath = m4aPath
            startNewSegmentEncoder(m4aPath)
            openAudioRecordAndStart()

            isRecording = true
            isPaused = false
            accumulatedDurationMs = 0L
            startedAtMs = System.currentTimeMillis()
            ignoreSilentConflictUntilMs = System.currentTimeMillis() + 3_000L
            ensureWakeLock()

            recordThread = Thread { writePcmLoop() }.also { it.start() }
            requestAudioFocusForRecording()
            result.success(true)
        } catch (e: Exception) {
            stopInternal(deleteFile = true)
            result.error("AUDIO_START_FAILED", e.message, null)
        }
    }

    private fun startNewSegmentEncoder(path: String) {
        val encoder = StreamingAacM4aEncoder(
            outputPath = path,
            sampleRate = sampleRate,
            channels = channelCount,
        )
        encoder.start()
        streamingEncoder = encoder
        outputPath = path
    }

    private fun openAudioRecordAndStart() {
        releaseAudioRecordQuietly()
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufferSize = if (minBuf > 0) minBuf * 2 else sampleRate * 2
        recordBufferSize = bufferSize

        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            // 回退默认麦克风源，兼容部分机型。
            val fallback = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            if (fallback.state != AudioRecord.STATE_INITIALIZED) {
                fallback.release()
                throw IllegalStateException("AudioRecord init failed")
            }
            fallback.startRecording()
            audioRecord = fallback
            return
        }
        record.startRecording()
        audioRecord = record
    }

    private fun pauseRecord(result: MethodChannel.Result) {
        if (!isRecording || isPaused) {
            result.success(false)
            return
        }
        try {
            if (pauseRecordInternal(finalizeSegment = true)) {
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.error("AUDIO_PAUSE_FAILED", e.message, null)
        }
    }

    /**
     * @param finalizeSegment 为 true 时立刻落盘当前片段（来电/其他语音软件抢麦时必须）。
     */
    private fun pauseRecordInternal(finalizeSegment: Boolean): Boolean {
        if (!isRecording || isPaused) return false
        accumulatedDurationMs += currentSegmentDurationMs()
        isPaused = true
        startedAtMs = 0L
        stopAudioRecordCapture()
        if (finalizeSegment) {
            finalizeCurrentSegmentIfNeeded()
        }
        consecutiveReadErrors = 0
        return true
    }

    private fun stopAudioRecordCapture() {
        val record = audioRecord
        if (record != null &&
            record.recordingState == AudioRecord.RECORDSTATE_RECORDING
        ) {
            try {
                record.stop()
            } catch (_: IllegalStateException) {
            }
        }
    }

    private fun finalizeCurrentSegmentIfNeeded() {
        val encoder = streamingEncoder
        val path = outputPath
        streamingEncoder = null
        if (encoder == null || path.isNullOrBlank()) {
            outputPath = null
            return
        }
        val ok = try {
            encoder.finish()
        } catch (_: Exception) {
            false
        }
        if (ok) {
            segmentPaths.add(path)
        } else {
            deleteQuietly(File(path))
        }
        outputPath = null
    }

    private fun resumeRecord(result: MethodChannel.Result) {
        if (!isRecording || !isPaused) {
            result.success(false)
            return
        }
        try {
            requestAudioFocusForRecording()
            // 其他语音软件抢麦后，旧 AudioRecord 往往已失效，必须重建。
            openAudioRecordAndStart()
            if (streamingEncoder == null) {
                startNewSegmentEncoder(newVoiceRecordingPath("voice"))
            }
            micConflictDetected = false
            consecutiveReadErrors = 0
            isPaused = false
            startedAtMs = System.currentTimeMillis()
            ignoreSilentConflictUntilMs = System.currentTimeMillis() + 3_000L
            // 录音线程可能已因冲突退出，必要时重启。
            if (recordThread?.isAlive != true) {
                recordThread = Thread { writePcmLoop() }.also { it.start() }
            }
            result.success(true)
        } catch (e: Exception) {
            isPaused = true
            result.error("AUDIO_RESUME_FAILED", e.message, null)
        }
    }

    private fun writePcmLoop() {
        val bufferSize = if (recordBufferSize > 0) recordBufferSize else sampleRate * 2
        val buf = ByteArray(bufferSize)
        try {
            while (isRecording) {
                if (isPaused) {
                    Thread.sleep(50)
                    continue
                }
                val record = audioRecord
                if (record == null) {
                    handleMicConflict("audioRecordGone")
                    break
                }
                val read = try {
                    record.read(buf, 0, buf.size)
                } catch (_: Exception) {
                    AudioRecord.ERROR_INVALID_OPERATION
                }
                when {
                    read > 0 -> {
                        consecutiveReadErrors = 0
                        val usable = read - (read % frameBytes)
                        if (usable > 0) {
                            streamingEncoder?.writePcm(buf, 0, usable)
                            emitAudioChunk(buf, usable)
                        }
                    }
                    read == -6 /* ERROR_DEAD_OBJECT */ ||
                        read == AudioRecord.ERROR_INVALID_OPERATION ||
                        read == AudioRecord.ERROR_BAD_VALUE ||
                        read == AudioRecord.ERROR -> {
                        consecutiveReadErrors++
                        if (consecutiveReadErrors >= 3) {
                            handleMicConflict("audioRecordError")
                            break
                        }
                        Thread.sleep(30)
                    }
                    read == 0 -> {
                        consecutiveReadErrors++
                        // 约 3s 连续空读，且不在开录宽限期内，才判定为静默抢麦。
                        if (consecutiveReadErrors >= 150 &&
                            System.currentTimeMillis() >= ignoreSilentConflictUntilMs
                        ) {
                            handleMicConflict("audioRecordSilent")
                            break
                        }
                        Thread.sleep(20)
                    }
                    else -> {
                        consecutiveReadErrors++
                        if (consecutiveReadErrors >= 5) {
                            handleMicConflict("audioRecordError")
                            break
                        }
                        Thread.sleep(30)
                    }
                }
            }
        } catch (_: Exception) {
            // 录音线程异常时忽略，已落盘片段可在 stop 时合并。
            if (isRecording && !isPaused) {
                handleMicConflict("audioRecordException")
            }
        }
    }

    private fun handleMicConflict(reason: String) {
        if (!isRecording || isPaused || micConflictDetected) return
        micConflictDetected = true
        mainHandler.post {
            if (!isRecording || isPaused) return@post
            if (pauseRecordInternal(finalizeSegment = true)) {
                emitRecorderEvent("paused", reason)
            }
        }
    }

    private fun emitAudioChunk(buffer: ByteArray, size: Int) {
        val sink = voiceStreamSink ?: return
        val copy = buffer.copyOf(size)
        mainHandler.post {
            sink.success(copy)
        }
    }

    private fun stopRecord(result: MethodChannel.Result, deleteFile: Boolean) {
        try {
            val duration = stopInternal(deleteFile)
            val path = outputPath
            if (deleteFile || path.isNullOrBlank()) {
                result.success(null)
                return
            }
            result.success(
                mapOf(
                    "path" to path,
                    "durationMs" to duration
                )
            )
        } catch (e: Exception) {
            stopInternal(deleteFile = true)
            result.error("AUDIO_STOP_FAILED", e.message, null)
        }
    }

    private fun currentSegmentDurationMs(): Long {
        if (!isRecording || isPaused || startedAtMs <= 0L) return 0L
        return (System.currentTimeMillis() - startedAtMs).coerceAtLeast(0L)
    }

    private fun stopInternal(deleteFile: Boolean): Long {
        if (isRecording && !isPaused) {
            accumulatedDurationMs += currentSegmentDurationMs()
        }
        val duration = accumulatedDurationMs
        isRecording = false
        isPaused = false
        micConflictDetected = false
        try {
            recordThread?.join(3000)
        } catch (_: InterruptedException) {
        }
        recordThread = null

        releaseAudioRecordQuietly()
        startedAtMs = 0L
        accumulatedDurationMs = 0L
        consecutiveReadErrors = 0
        releaseWakeLock()
        abandonAudioFocusForRecording()
        MeetingRecordingService.stop(this)

        if (deleteFile) {
            streamingEncoder?.abort()
            streamingEncoder = null
            deleteQuietly(outputPath?.let { File(it) })
            outputPath = null
            for (path in segmentPaths) {
                deleteQuietly(File(path))
            }
            segmentPaths.clear()
            return 0L
        }

        finalizeCurrentSegmentIfNeeded()
        val paths = segmentPaths.toList()
        segmentPaths.clear()
        if (paths.isEmpty()) {
            outputPath = null
            return duration
        }

        if (paths.size == 1) {
            outputPath = paths[0]
            return duration
        }

        val merged = newVoiceRecordingPath("voice-merged")
        if (M4aSegmentMerger.merge(paths, merged)) {
            outputPath = merged
            for (path in paths) {
                if (path != merged) deleteQuietly(File(path))
            }
        } else {
            // 合并失败时保留体积最大的片段，避免整段录音丢失。
            val keep = M4aSegmentMerger.largestExistingPath(paths)
            outputPath = keep
            for (path in paths) {
                if (path != keep) deleteQuietly(File(path))
            }
        }
        return duration
    }

    private fun releaseAudioRecordQuietly() {
        val record = audioRecord
        audioRecord = null
        if (record == null) return
        try {
            if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                record.stop()
            }
        } catch (_: IllegalStateException) {
        } finally {
            try {
                record.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun deleteQuietly(file: File?) {
        if (file == null) return
        try {
            if (file.exists()) file.delete()
        } catch (_: Exception) {
        }
    }

    private fun ensureWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dunes:meeting-recorder").apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        } finally {
            wakeLock = null
        }
    }

    private fun emitRecorderEvent(kind: String, reason: String? = null) {
        val sink = recorderEventSink ?: return
        val payload = mutableMapOf<String, Any>("kind" to kind)
        if (!reason.isNullOrBlank()) {
            payload["reason"] = reason
        }
        mainHandler.post { sink.success(payload) }
    }

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        mainHandler.post {
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    if (isRecording && !isPaused && pauseRecordInternal(finalizeSegment = true)) {
                        emitRecorderEvent("paused", "audioFocusLoss")
                    }
                }
                AudioManager.AUDIOFOCUS_GAIN -> {
                    if (isRecording && isPaused) {
                        emitRecorderEvent("interruptionEnded")
                    }
                }
            }
        }
    }

    private fun requestAudioFocusForRecording() {
        val am = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(audioFocusChangeListener, mainHandler)
                .setAcceptsDelayedFocusGain(true)
                .build()
            audioFocusRequest = request
            am.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
    }

    private fun abandonAudioFocusForRecording() {
        val am = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(audioFocusChangeListener)
        }
    }
}
