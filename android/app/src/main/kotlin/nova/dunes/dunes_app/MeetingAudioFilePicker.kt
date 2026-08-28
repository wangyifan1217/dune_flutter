package nova.dunes.dunes_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * 会议录音选择：按块拷到 filesDir，避免 file_selector 把整文件读进 ByteArray 导致 OOM。
 */
class MeetingAudioFilePicker(private val activity: FlutterActivity) {
    companion object {
        const val REQUEST_CODE = 0x4D4155
        private const val BUFFER_SIZE = 64 * 1024
    }

    private var pending: MethodChannel.Result? = null

    fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "already picking", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "audio/*",
                    "audio/mpeg",
                    "audio/mp4",
                    "audio/x-m4a",
                    "audio/m4a",
                    "audio/wav",
                    "audio/x-wav",
                    "audio/aac",
                    "audio/amr",
                    "audio/3gpp",
                    "application/octet-stream",
                ),
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: Exception) {
            pending = null
            result.error("PICK_FAILED", e.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return true
        }
        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) {
        }
        Thread {
            try {
                val path = copyUriToFile(uri)
                activity.runOnUiThread { result.success(path) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("COPY_FAILED", e.message ?: "copy failed", null)
                }
            }
        }.start()
        return true
    }

    private fun copyUriToFile(uri: Uri): String {
        val name = queryDisplayName(uri)
        val mime = activity.contentResolver.getType(uri)
        if (!isLikelyAudio(name, mime)) {
            throw IllegalArgumentException("请选择 wav / mp3 / m4a 录音文件")
        }
        val dir = File(activity.filesDir, "meeting_picks")
        if (!dir.exists()) dir.mkdirs()
        val dest = File(dir, uniqueFileName(name, mime))
        activity.contentResolver.openInputStream(uri).use { input ->
            if (input == null) throw IllegalStateException("无法读取所选文件")
            FileOutputStream(dest).use { output ->
                val buf = ByteArray(BUFFER_SIZE)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    output.write(buf, 0, n)
                }
                output.flush()
            }
        }
        if (!dest.exists() || dest.length() <= 0L) {
            dest.delete()
            throw IllegalStateException("录音文件保存失败")
        }
        return dest.absolutePath
    }

    private fun queryDisplayName(uri: Uri): String? {
        activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx < 0) return null
            return cursor.getString(idx)
        }
        return uri.lastPathSegment
    }

    private fun uniqueFileName(rawName: String?, mime: String?): String {
        val stamp = System.currentTimeMillis()
        val cleaned = sanitizeName(rawName)
        val withExt = ensureExtension(cleaned, mime)
        return "pick_${stamp}_$withExt"
    }

    private fun sanitizeName(raw: String?): String {
        val base = (raw ?: "")
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
            .trim()
        if (base.isEmpty() || base == "." || base == "..") return "recording"
        return base.take(80)
    }

    private fun ensureExtension(name: String, mime: String?): String {
        if (name.contains('.')) return name
        val ext = when (mime?.lowercase()) {
            "audio/mpeg" -> "mp3"
            "audio/mp4", "audio/m4a", "audio/x-m4a" -> "m4a"
            "audio/wav", "audio/x-wav", "audio/wave" -> "wav"
            "audio/aac" -> "aac"
            "audio/amr", "audio/3gpp" -> "amr"
            else -> "m4a"
        }
        return "$name.$ext"
    }

    private fun isLikelyAudio(name: String?, mime: String?): Boolean {
        val m = mime?.lowercase().orEmpty()
        if (m.startsWith("audio/")) return true
        val n = name?.lowercase().orEmpty()
        return n.endsWith(".mp3") ||
            n.endsWith(".m4a") ||
            n.endsWith(".wav") ||
            n.endsWith(".aac") ||
            n.endsWith(".amr") ||
            n.endsWith(".ogg") ||
            n.endsWith(".flac") ||
            n.endsWith(".3gp") ||
            n.endsWith(".caf")
    }
}
