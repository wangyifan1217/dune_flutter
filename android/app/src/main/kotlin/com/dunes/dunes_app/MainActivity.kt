package com.dunes.dunes_app

import android.media.MediaRecorder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val voiceChannel = "dunes/audio_recorder"
    private var recorder: MediaRecorder? = null
    private var outputPath: String? = null
    private var startedAtMs: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startRecord(result)
                    "stop" -> stopRecord(result, deleteFile = false)
                    "cancel" -> stopRecord(result, deleteFile = true)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startRecord(result: MethodChannel.Result) {
        try {
            stopInternal(deleteFile = true)
            val dir = File(cacheDir, "voice")
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, "voice-${System.currentTimeMillis()}.m4a")
            outputPath = file.absolutePath
            val r = MediaRecorder()
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioEncodingBitRate(96_000)
            r.setAudioSamplingRate(44_100)
            r.setOutputFile(file.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            startedAtMs = System.currentTimeMillis()
            result.success(true)
        } catch (e: Exception) {
            stopInternal(deleteFile = true)
            result.error("AUDIO_START_FAILED", e.message, null)
        }
    }

    private fun stopRecord(result: MethodChannel.Result, deleteFile: Boolean) {
        try {
            val path = outputPath
            val duration = stopInternal(deleteFile)
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
        val r = recorder
        recorder = null
        startedAtMs = 0L
        if (r != null) {
            try {
                r.stop()
            } catch (_: RuntimeException) {
                deleteVoiceFile(outputPath)
                outputPath = null
            } finally {
                r.reset()
                r.release()
            }
        }
        val path = outputPath
        if (deleteFile) {
            deleteVoiceFile(path)
            outputPath = null
        }
        if (start <= 0L) return 0L
        return (System.currentTimeMillis() - start).coerceAtLeast(0L)
    }

    private fun deleteVoiceFile(path: String?) {
        if (path.isNullOrBlank()) return
        try {
            File(path).delete()
        } catch (_: Exception) {}
    }
}
