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
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val voiceChannel = "dunes/audio_recorder"
    private val voiceStreamChannel = "dunes/audio_recorder_stream"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var tpnsBridge: TpnsPushBridge? = null
    private var voiceStreamSink: EventChannel.EventSink? = null

    // glm-asr-2512 仅接受 wav/mp3，这里录成 16k/16bit/单声道 PCM 并封装为标准 WAV。
    private val sampleRate = 16000
    private val channelCount = 1
    private val bitsPerSample = 16

    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    @Volatile private var isRecording = false
    private var pcmFile: File? = null
    private var wavPath: String? = null
    private var startedAtMs: Long = 0L
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
                    "stop" -> stopRecord(result, deleteFile = false)
                    "cancel" -> stopRecord(result, deleteFile = true)
                    "status" -> result.success(mapOf("isRecording" to isRecording))
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
    }

    private fun startRecord(result: MethodChannel.Result) {
        try {
            stopInternal(deleteFile = true)
            val dir = File(cacheDir, "voice")
            if (!dir.exists()) dir.mkdirs()
            val stamp = System.currentTimeMillis()
            val pcm = File(dir, "voice-$stamp.pcm")
            val wav = File(dir, "voice-$stamp.wav")
            pcmFile = pcm
            wavPath = wav.absolutePath

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
            startedAtMs = System.currentTimeMillis()
            ensureWakeLock()

            recordThread = Thread { writePcmLoop(pcm, bufferSize) }.also { it.start() }
            result.success(true)
        } catch (e: Exception) {
            stopInternal(deleteFile = true)
            result.error("AUDIO_START_FAILED", e.message, null)
        }
    }

    private fun writePcmLoop(pcm: File, bufferSize: Int) {
        val buf = ByteArray(bufferSize)
        try {
            FileOutputStream(pcm).use { out ->
                while (isRecording) {
                    val read = audioRecord?.read(buf, 0, buf.size) ?: -1
                    if (read > 0) {
                        out.write(buf, 0, read)
                        emitAudioChunk(buf, read)
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
            val path = wavPath
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

    private fun stopInternal(deleteFile: Boolean): Long {
        val start = startedAtMs
        isRecording = false
        try {
            recordThread?.join(1000)
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

        val pcm = pcmFile
        val wav = wavPath
        startedAtMs = 0L
        releaseWakeLock()

        if (deleteFile) {
            deleteQuietly(pcm)
            deleteQuietly(wav?.let { File(it) })
            pcmFile = null
            wavPath = null
            return 0L
        }

        // 由裸 PCM 一次性组装标准 WAV（头 + 数据）。
        if (pcm != null && pcm.exists() && wav != null) {
            try {
                writeWavFromPcm(pcm, File(wav))
            } catch (_: Exception) {
                deleteQuietly(File(wav))
                wavPath = null
            } finally {
                deleteQuietly(pcm)
                pcmFile = null
            }
        }
        if (start <= 0L) return 0L
        return (System.currentTimeMillis() - start).coerceAtLeast(0L)
    }

    private fun writeWavFromPcm(pcm: File, wav: File) {
        val dataLen = pcm.length()
        FileOutputStream(wav).use { out ->
            out.write(buildWavHeader(dataLen))
            FileInputStream(pcm).use { input ->
                val buf = ByteArray(8192)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    out.write(buf, 0, n)
                }
            }
        }
    }

    /** 标准 44 字节 PCM WAV 头。 */
    private fun buildWavHeader(dataLen: Long): ByteArray {
        val byteRate = sampleRate * channelCount * bitsPerSample / 8
        val blockAlign = channelCount * bitsPerSample / 8
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt((36 + dataLen).toInt())
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16) // PCM fmt chunk size
        header.putShort(1) // PCM format
        header.putShort(channelCount.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort(blockAlign.toShort())
        header.putShort(bitsPerSample.toShort())
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(dataLen.toInt())
        return header.array()
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
