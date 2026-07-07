package nova.dunes.dunes_app

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
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
    private val meetingAudioChannel = "dunes/meeting_audio"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var tpnsBridge: TpnsPushBridge? = null
    private var voiceStreamSink: EventChannel.EventSink? = null

    // 16k/mono PCM 供实时转写；同时边录边编码为 AAC/m4a 供上传。
    private val sampleRate = 16000
    private val channelCount = 1
    private val bitsPerSample = 16
    private val frameBytes = channelCount * bitsPerSample / 8

    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private var streamingEncoder: StreamingAacM4aEncoder? = null
    @Volatile private var isRecording = false
    @Volatile private var isPaused = false
    private var outputPath: String? = null
    private var startedAtMs: Long = 0L
    private var accumulatedDurationMs: Long = 0L
    private var wakeLock: PowerManager.WakeLock? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, meetingAudioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "convertWavToM4a" -> {
                        val inputPath = call.argument<String>("inputPath")?.trim().orEmpty()
                        val outputPath = call.argument<String>("outputPath")?.trim().orEmpty()
                        if (inputPath.isEmpty() || outputPath.isEmpty()) {
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

    private fun startRecord(result: MethodChannel.Result) {
        try {
            stopInternal(deleteFile = true)
            MeetingRecordingService.start(this)
            val dir = File(cacheDir, "voice")
            if (!dir.exists()) dir.mkdirs()
            val stamp = System.currentTimeMillis()
            val m4a = File(dir, "voice-$stamp.m4a")
            outputPath = m4a.absolutePath

            val encoder = StreamingAacM4aEncoder(
                outputPath = m4a.absolutePath,
                sampleRate = sampleRate,
                channels = channelCount,
            )
            encoder.start()
            streamingEncoder = encoder

            val minBuf = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val bufferSize = if (minBuf > 0) minBuf * 2 else sampleRate * 2

            val record = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                throw IllegalStateException("AudioRecord init failed")
            }

            record.startRecording()
            audioRecord = record
            isRecording = true
            isPaused = false
            accumulatedDurationMs = 0L
            startedAtMs = System.currentTimeMillis()
            ensureWakeLock()

            recordThread = Thread { writePcmLoop(bufferSize) }.also { it.start() }
            result.success(true)
        } catch (e: Exception) {
            stopInternal(deleteFile = true)
            result.error("AUDIO_START_FAILED", e.message, null)
        }
    }

    private fun pauseRecord(result: MethodChannel.Result) {
        if (!isRecording || isPaused) {
            result.success(false)
            return
        }
        try {
            accumulatedDurationMs += currentSegmentDurationMs()
            isPaused = true
            val record = audioRecord
            if (record != null &&
                record.recordingState == AudioRecord.RECORDSTATE_RECORDING
            ) {
                record.stop()
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("AUDIO_PAUSE_FAILED", e.message, null)
        }
    }

    private fun resumeRecord(result: MethodChannel.Result) {
        if (!isRecording || !isPaused) {
            result.success(false)
            return
        }
        try {
            val record = audioRecord
            if (record == null) {
                throw IllegalStateException("AudioRecord unavailable")
            }
            record.startRecording()
            isPaused = false
            startedAtMs = System.currentTimeMillis()
            result.success(true)
        } catch (e: Exception) {
            result.error("AUDIO_RESUME_FAILED", e.message, null)
        }
    }

    private fun writePcmLoop(bufferSize: Int) {
        val buf = ByteArray(bufferSize)
        try {
            while (isRecording) {
                if (isPaused) {
                    Thread.sleep(50)
                    continue
                }
                val read = audioRecord?.read(buf, 0, buf.size) ?: -1
                if (read > 0) {
                    val usable = read - (read % frameBytes)
                    if (usable > 0) {
                        streamingEncoder?.writePcm(buf, 0, usable)
                        emitAudioChunk(buf, usable)
                    }
                }
            }
        } catch (_: Exception) {
            // 录音线程异常时忽略，stop 时按已写入的数据处理。
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
        try {
            recordThread?.join(3000)
        } catch (_: InterruptedException) {
        }
        recordThread = null

        val record = audioRecord
        audioRecord = null
        if (record != null) {
            try {
                if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    record.stop()
                }
            } catch (_: IllegalStateException) {
            } finally {
                record.release()
            }
        }

        val path = outputPath
        startedAtMs = 0L
        accumulatedDurationMs = 0L
        releaseWakeLock()
        MeetingRecordingService.stop(this)

        val encoder = streamingEncoder
        streamingEncoder = null
        if (deleteFile) {
            encoder?.abort()
            deleteQuietly(path?.let { File(it) })
            outputPath = null
            return 0L
        }

        val ok = encoder?.finish() ?: false
        if (!ok) {
            deleteQuietly(path?.let { File(it) })
            outputPath = null
        }
        return duration
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
}
