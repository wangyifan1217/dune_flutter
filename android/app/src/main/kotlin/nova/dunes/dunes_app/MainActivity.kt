package nova.dunes.dunes_app

import android.content.Intent
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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val voiceChannel = "dunes/audio_recorder"
    private val voiceStreamChannel = "dunes/audio_recorder_stream"
    private val voiceEventsChannel = "dunes/audio_recorder_events"
    private val meetingAudioChannel = "dunes/meeting_audio"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var tpnsBridge: TpnsPushBridge? = null
    private var tauVoiceCallAudio: TauVoiceCallAudio? = null
    private var meetingAudioPicker: MeetingAudioFilePicker? = null
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
    @Volatile private var pausedBySystemInterruption = false
    @Volatile private var micConflictDetected = false
    private var outputPath: String? = null
    private var startedAtMs: Long = 0L
    private var accumulatedDurationMs: Long = 0L
    private var wakeLock: PowerManager.WakeLock? = null
    private var consecutiveReadErrors = 0
    /** 开录/续录后短时间内的空读不视为抢麦（设备刚就绪时常有短暂静音）。 */
    private var ignoreSilentConflictUntilMs: Long = 0L
    /** 小米等机型会掐断 VOICE_RECOGNITION，空读后重开麦克风的次数。 */
    private var audioSourceRecoveries = 0
    private var sessionTracking = false
    private var sessionTitle = ""
    private var crashWav: CrashSafeWavWriter? = null
    private val rotateRunnable = Runnable { rotateLiveSegmentIfNeeded() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MeetingRecordingService.taskRemovedListener = {
            flushLiveSessionForDeath()
        }
        tpnsBridge = TpnsPushBridge(applicationContext).also {
            it.attach(flutterEngine)
        }
        tauVoiceCallAudio = TauVoiceCallAudio(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startRecord(call, result)
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
                    "abandonedSession" -> result.success(abandonedSessionPayload())
                    "recoverAbandonedSession" -> recoverAbandonedSession(result)
                    "discardAbandonedSession" -> {
                        discardAbandonedSession()
                        result.success(true)
                    }
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
        meetingAudioPicker = MeetingAudioFilePicker(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, meetingAudioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAudioFile" -> meetingAudioPicker?.pick(result)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (meetingAudioPicker?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
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

    private fun liveSessionFile(): File = File(voiceRecordingDir(), "live_session.json")

    private fun livePcmFile(): File = File(voiceRecordingDir(), "live_pcm.wav")

    private fun persistLiveSession() {
        if (!sessionTracking) return
        val segs = segmentPaths.filter { File(it).let { f -> f.exists() && f.length() > 0 } }.toMutableList()
        val current = outputPath
        if (!current.isNullOrBlank()) {
            val file = File(current)
            if (file.exists() && file.length() > 0 && !segs.contains(current)) {
                segs.add(current)
            }
        }
        val pcmPath = livePcmFile().absolutePath
        val pcmExists = livePcmFile().exists() && livePcmFile().length() > 44
        try {
            crashWav?.flushHeader()
            val json = JSONObject()
            json.put("title", sessionTitle)
            json.put("startedAtMs", startedAtMs)
            json.put(
                "durationMs",
                if (pcmExists) CrashSafeWavWriter.durationMs(pcmPath).toLong()
                else accumulatedDurationMs + currentSegmentDurationMs()
            )
            json.put("segments", JSONArray(segs))
            json.put("pcmPath", pcmPath)
            liveSessionFile().writeText(json.toString())
        } catch (_: Exception) {
        }
    }

    private fun clearLiveSessionFile() {
        deleteQuietly(liveSessionFile())
    }

    private fun startSegmentRotateTimer() {
        mainHandler.removeCallbacks(rotateRunnable)
        if (!sessionTracking) return
        mainHandler.postDelayed(rotateRunnable, 60_000L)
    }

    private fun rotateLiveSegmentIfNeeded() {
        if (!isRecording || isPaused || !sessionTracking) return
        accumulatedDurationMs += currentSegmentDurationMs()
        startedAtMs = System.currentTimeMillis()
        finalizeCurrentSegmentIfNeeded()
        startNewSegmentEncoder(newVoiceRecordingPath("voice"))
        persistLiveSession()
        startSegmentRotateTimer()
        refreshRecordingNotification()
    }

    private fun flushLiveSessionForDeath() {
        if (!isRecording || !sessionTracking) return
        if (!isPaused) {
            pauseRecordInternal(finalizeSegment = true)
            pausedBySystemInterruption = true
        } else {
            finalizeCurrentSegmentIfNeeded()
        }
        persistLiveSession()
        crashWav?.flushHeader()
    }

    private fun readAbandonedSession(): JSONObject? {
        if (isRecording && sessionTracking) return null
        val file = liveSessionFile()
        if (file.exists()) {
            try {
                return JSONObject(file.readText())
            } catch (_: Exception) {
            }
        }
        val pcm = livePcmFile()
        if (pcm.exists() && pcm.length() > 44 + 1024) {
            return JSONObject().apply {
                put("title", "")
                put("durationMs", CrashSafeWavWriter.durationMs(pcm.absolutePath))
                put("segments", JSONArray())
                put("pcmPath", pcm.absolutePath)
            }
        }
        return null
    }

    private fun existingAbandonedSegments(json: JSONObject): List<String> {
        val raw = json.optJSONArray("segments") ?: JSONArray()
        val segs = mutableListOf<String>()
        for (i in 0 until raw.length()) {
            val path = raw.optString(i)
            val file = File(path)
            if (file.exists() && file.length() > 1024) segs.add(path)
        }
        return segs
    }

    private fun abandonedPcmPath(json: JSONObject): String? {
        val path = json.optString("pcmPath")
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.exists() || file.length() <= 44 + 1024) return null
        return path
    }

    private fun abandonedSessionPayload(): Map<String, Any>? {
        val json = readAbandonedSession() ?: return null
        val pcm = abandonedPcmPath(json)
        val segs = existingAbandonedSegments(json)
        if (pcm == null && segs.isEmpty()) return null
        val durationMs = if (pcm != null) {
            CrashSafeWavWriter.durationMs(pcm).toLong()
        } else {
            json.optLong("durationMs", 0L)
        }
        return mapOf(
            "title" to json.optString("title"),
            "durationMs" to durationMs,
            "segmentCount" to maxOf(segs.size, if (pcm != null) 1 else 0),
        )
    }

    private fun recoverAbandonedSession(result: MethodChannel.Result) {
        val json = readAbandonedSession()
        if (json == null) {
            result.success(null)
            return
        }
        val pcm = abandonedPcmPath(json)
        val segs = existingAbandonedSegments(json)
        if (pcm == null && segs.isEmpty()) {
            discardAbandonedSession()
            result.success(null)
            return
        }
        Thread {
            if (pcm != null) {
                CrashSafeWavWriter.repairHeader(pcm)
                val leftover = json.optJSONArray("segments") ?: JSONArray()
                for (i in 0 until leftover.length()) {
                    deleteQuietly(File(leftover.optString(i)))
                }
                val durationMs = CrashSafeWavWriter.durationMs(pcm)
                mainHandler.post {
                    clearLiveSessionFile()
                    result.success(
                        mapOf(
                            "path" to pcm,
                            "durationMs" to durationMs,
                        )
                    )
                }
                return@Thread
            }
            val durationMs = json.optLong("durationMs", 0L)
            val path = when {
                segs.size == 1 -> segs[0]
                else -> {
                    val merged = newVoiceRecordingPath("voice-recovered")
                    if (M4aSegmentMerger.merge(segs, merged)) {
                        for (item in segs) {
                            if (item != merged) deleteQuietly(File(item))
                        }
                        merged
                    } else {
                        M4aSegmentMerger.largestExistingPath(segs)
                    }
                }
            }
            mainHandler.post {
                clearLiveSessionFile()
                if (path.isNullOrBlank()) {
                    result.success(null)
                } else {
                    result.success(
                        mapOf(
                            "path" to path,
                            "durationMs" to durationMs,
                        )
                    )
                }
            }
        }.start()
    }

    private fun discardAbandonedSession() {
        val json = readAbandonedSession()
        if (json != null) {
            val raw = json.optJSONArray("segments") ?: JSONArray()
            for (i in 0 until raw.length()) {
                deleteQuietly(File(raw.optString(i)))
            }
            deleteQuietly(File(json.optString("pcmPath")))
        }
        closeCrashWav(deleteFile = true)
        clearLiveSessionFile()
    }

    private fun closeCrashWav(deleteFile: Boolean) {
        try {
            crashWav?.close()
        } catch (_: Exception) {
        }
        crashWav = null
        if (deleteFile) {
            deleteQuietly(livePcmFile())
        }
    }

    private fun startRecord(call: MethodCall, result: MethodChannel.Result) {
        try {
            stopInternal(deleteFile = true)
            sessionTitle = call.argument<String>("title")?.trim().orEmpty()
            sessionTracking = call.argument<Boolean>("persistSession") == true
            MeetingRecordingService.start(this)
            segmentPaths.clear()
            micConflictDetected = false
            consecutiveReadErrors = 0
            audioSourceRecoveries = 0

            val m4aPath = newVoiceRecordingPath("voice")
            outputPath = m4aPath
            startNewSegmentEncoder(m4aPath)
            openAudioRecordAndStart()

            isRecording = true
            isPaused = false
            pausedBySystemInterruption = false
            accumulatedDurationMs = 0L
            startedAtMs = System.currentTimeMillis()
            ignoreSilentConflictUntilMs = System.currentTimeMillis() + 3_000L
            ensureWakeLock()

            recordThread = Thread { writePcmLoop() }.also { it.start() }
            requestAudioFocusForRecording()
            if (sessionTracking) {
                closeCrashWav(deleteFile = true)
                crashWav = CrashSafeWavWriter(livePcmFile().absolutePath)
            }
            persistLiveSession()
            startSegmentRotateTimer()
            refreshRecordingNotification()
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
        val record = createAudioRecord(bufferSize)
        record.startRecording()
        audioRecord = record
    }

    /**
     * 长会议用 MIC，不要用 VOICE_RECOGNITION。
     * 小米 14 / HyperOS 会把识别源当成短语音会话，大约 3 分钟后静音并触发我们的「抢麦暂停」。
     */
    private fun createAudioRecord(bufferSize: Int): AudioRecord {
        val sources = mutableListOf(
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.DEFAULT,
            MediaRecorder.AudioSource.CAMCORDER,
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
        )
        if (Build.VERSION.SDK_INT >= 24) {
            sources.add(1, MediaRecorder.AudioSource.UNPROCESSED)
        }
        for (source in sources) {
            val record = try {
                AudioRecord(
                    source,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize
                )
            } catch (_: Exception) {
                continue
            }
            if (record.state == AudioRecord.STATE_INITIALIZED) {
                return record
            }
            record.release()
        }
        throw IllegalStateException("AudioRecord init failed")
    }

    private fun pauseRecord(result: MethodChannel.Result) {
        if (!isRecording) {
            result.success(false)
            return
        }
        if (isPaused) {
            result.success(true)
            return
        }
        try {
            pausedBySystemInterruption = false
            if (pauseRecordInternal(finalizeSegment = true)) {
                MeetingRecordingService.update(
                    this,
                    title = "沙丘 · 会议录音已暂停",
                    text = "点击继续后才会再采集，已录部分已保存"
                )
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
        crashWav?.flushHeader()
        persistLiveSession()
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
            persistLiveSession()
        } else {
            deleteQuietly(File(path))
        }
        outputPath = null
    }

    private fun resumeRecord(result: MethodChannel.Result) {
        if (!isRecording) {
            result.success(false)
            return
        }
        if (!isPaused) {
            result.success(true)
            return
        }
        try {
            resumeRecordInternal()
            pausedBySystemInterruption = false
            MeetingRecordingService.update(
                this,
                title = "沙丘 · 会议录音进行中",
                text = "正在后台录音，结束后生成纪要"
            )
            result.success(true)
        } catch (e: Exception) {
            isPaused = true
            result.error("AUDIO_RESUME_FAILED", e.message, null)
        }
    }

    private fun resumeRecordInternal() {
        requestAudioFocusForRecording()
        openAudioRecordAndStart()
        if (streamingEncoder == null) {
            startNewSegmentEncoder(newVoiceRecordingPath("voice"))
        }
        micConflictDetected = false
        consecutiveReadErrors = 0
        audioSourceRecoveries = 0
        isPaused = false
        startedAtMs = System.currentTimeMillis()
        ignoreSilentConflictUntilMs = System.currentTimeMillis() + 3_000L
        if (recordThread?.isAlive != true) {
            recordThread = Thread { writePcmLoop() }.also { it.start() }
        }
    }

    private fun tryNativeResumeAfterSystemInterruption() {
        if (!isRecording || !isPaused || !pausedBySystemInterruption) return
        try {
            resumeRecordInternal()
            pausedBySystemInterruption = false
            MeetingRecordingService.update(
                this,
                title = "沙丘 · 会议录音进行中",
                text = "正在后台录音，结束后生成纪要"
            )
            emitRecorderEvent("resumed", "system")
        } catch (_: Exception) {
            emitRecorderEvent("interruptionEnded")
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
                            crashWav?.write(buf, 0, usable)
                            emitAudioChunk(buf, usable)
                        }
                    }
                    read == -6 /* ERROR_DEAD_OBJECT */ ||
                        read == AudioRecord.ERROR_INVALID_OPERATION ||
                        read == AudioRecord.ERROR_BAD_VALUE ||
                        read == AudioRecord.ERROR -> {
                        consecutiveReadErrors++
                        if (consecutiveReadErrors >= 3) {
                            if (tryRecoverAudioRecord()) {
                                consecutiveReadErrors = 0
                                continue
                            }
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
                            if (tryRecoverAudioRecord()) {
                                consecutiveReadErrors = 0
                                continue
                            }
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

    private fun tryRecoverAudioRecord(): Boolean {
        if (!isRecording || isPaused || !sessionTracking || audioSourceRecoveries >= 2) {
            return false
        }
        return try {
            openAudioRecordAndStart()
            audioSourceRecoveries++
            ignoreSilentConflictUntilMs = System.currentTimeMillis() + 3_000L
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun handleMicConflict(reason: String) {
        if (!isRecording || isPaused || micConflictDetected) return
        micConflictDetected = true
        mainHandler.post {
            if (!isRecording || isPaused) return@post
            if (pauseRecordInternal(finalizeSegment = true)) {
                pausedBySystemInterruption = true
                emitRecorderEvent("paused", reason)
                MeetingRecordingService.update(
                    this,
                    title = "沙丘 · 会议录音已暂停",
                    text = "麦克风被占用，结束后将自动继续，已录部分已保存"
                )
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
        Thread({
            try {
                val duration = stopInternal(deleteFile)
                val path = outputPath
                mainHandler.post {
                    if (deleteFile || path.isNullOrBlank()) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "path" to path,
                                "durationMs" to duration
                            )
                        )
                    }
                }
            } catch (e: Exception) {
                try {
                    stopInternal(deleteFile = true)
                } catch (_: Exception) {
                }
                mainHandler.post {
                    result.error("AUDIO_STOP_FAILED", e.message, null)
                }
            }
        }, "dunes-audio-stop").start()
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
        val cancelTrackedSession = deleteFile && isRecording && sessionTracking
        val stopTrackedSession = isRecording && sessionTracking
        isRecording = false
        isPaused = false
        pausedBySystemInterruption = false
        micConflictDetected = false
        mainHandler.removeCallbacks(rotateRunnable)
        // 先停采集，避免录音线程卡在 read() 上，join 把主线程拖死。
        stopAudioRecordCapture()
        try {
            recordThread?.join(3000)
        } catch (_: InterruptedException) {
        }
        recordThread = null

        releaseAudioRecordQuietly()
        startedAtMs = 0L
        accumulatedDurationMs = 0L
        consecutiveReadErrors = 0
        audioSourceRecoveries = 0
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
            if (stopTrackedSession) {
                closeCrashWav(deleteFile = true)
            }
            if (cancelTrackedSession) {
                discardAbandonedSession()
            }
            if (stopTrackedSession) {
                sessionTracking = false
                sessionTitle = ""
            }
            return 0L
        }

        crashWav?.flushHeader()
        closeCrashWav(deleteFile = false)
        finalizeCurrentSegmentIfNeeded()
        if (stopTrackedSession) {
            clearLiveSessionFile()
            sessionTracking = false
            sessionTitle = ""
        }
        val paths = segmentPaths.toList()
        segmentPaths.clear()
        val pcm = livePcmFile()
        val pcmOk = pcm.exists() && pcm.length() > 44
        if (paths.isEmpty()) {
            if (pcmOk) {
                outputPath = pcm.absolutePath
                return CrashSafeWavWriter.durationMs(pcm.absolutePath).toLong()
            }
            outputPath = null
            return duration
        }

        if (paths.size == 1) {
            outputPath = paths[0]
            if (pcmOk) deleteQuietly(pcm)
            return duration
        }

        val merged = newVoiceRecordingPath("voice-merged")
        if (M4aSegmentMerger.merge(paths, merged)) {
            outputPath = merged
            for (path in paths) {
                if (path != merged) deleteQuietly(File(path))
            }
            if (pcmOk) deleteQuietly(pcm)
        } else {
            val keep = M4aSegmentMerger.largestExistingPath(paths)
            outputPath = keep ?: if (pcmOk) pcm.absolutePath else null
            for (path in paths) {
                if (path != keep) deleteQuietly(File(path))
            }
            if (keep != null && pcmOk) deleteQuietly(pcm)
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
            acquire()
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

    private fun refreshRecordingNotification() {
        if (!isRecording || isPaused || !sessionTracking) return
        val totalMs = accumulatedDurationMs + currentSegmentDurationMs()
        val minutes = (totalMs / 60000L).toInt()
        val seconds = ((totalMs / 1000L) % 60L).toInt()
        MeetingRecordingService.update(
            this,
            title = "沙丘 · 会议录音进行中",
            text = String.format("已录 %d:%02d，结束后生成纪要", minutes, seconds)
        )
    }

    private fun emitRecorderEvent(kind: String, reason: String? = null) {
        val sink = recorderEventSink ?: return
        val payload = mutableMapOf<String, Any>("kind" to kind)
        if (!reason.isNullOrBlank()) {
            payload["reason"] = reason
        }
        mainHandler.post { sink.success(payload) }
    }

    override fun onResume() {
        super.onResume()
        tryNativeResumeAfterSystemInterruption()
    }

    override fun onDestroy() {
        MeetingRecordingService.taskRemovedListener = null
        flushLiveSessionForDeath()
        super.onDestroy()
    }

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        mainHandler.post {
            when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                    if (isRecording && !isPaused && pauseRecordInternal(finalizeSegment = true)) {
                        pausedBySystemInterruption = true
                        emitRecorderEvent("paused", "audioFocusLoss")
                        MeetingRecordingService.update(
                            this,
                            title = "沙丘 · 会议录音已暂停",
                            text = "来电结束后将自动继续，已录部分已保存"
                        )
                    }
                }
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    // 通知/导航压低音量，会议录音继续采。
                }
                AudioManager.AUDIOFOCUS_GAIN -> {
                    tryNativeResumeAfterSystemInterruption()
                }
            }
        }
    }

    private fun requestAudioFocusForRecording() {
        // 长会议只采集、不播声音。抢 VOICE_COMMUNICATION 焦点会被小米当成网络通话，约 3 分钟掐断。
        if (sessionTracking) return
        val am = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
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
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
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
