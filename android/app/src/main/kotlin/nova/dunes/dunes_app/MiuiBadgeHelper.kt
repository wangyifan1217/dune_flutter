package nova.dunes.dunes_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

object MiuiBadgeHelper {
    private const val TAG = "DunesBadge"
    private const val INTENT_ACTION = "android.intent.action.APPLICATION_MESSAGE_UPDATE"
    private const val EXTRA_COMPONENT =
        "android.intent.extra.update_application_component_name"
    private const val EXTRA_MESSAGE =
        "android.intent.extra.update_application_message_text"

    fun isMiuiDevice(): Boolean {
        return Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true) ||
            Build.MANUFACTURER.equals("Redmi", ignoreCase = true) ||
            Build.MANUFACTURER.equals("POCO", ignoreCase = true)
    }

    fun applyCount(context: Context, count: Int) {
        if (!isMiuiDevice()) return
        val appContext = context.applicationContext
        val launchIntent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
            ?: return
        val component = ComponentName(
            launchIntent.component?.packageName ?: appContext.packageName,
            launchIntent.component?.className ?: return,
        )
        val text = if (count > 0) count.toString() else ""
        try {
            val intent = Intent(INTENT_ACTION).apply {
                putExtra(EXTRA_COMPONENT, "${component.packageName}/${component.className}")
                putExtra(EXTRA_MESSAGE, text)
            }
            appContext.sendBroadcast(intent)
            Log.i(TAG, "MIUI badge broadcast sent count=$count")
        } catch (e: Exception) {
            Log.w(TAG, "MIUI badge broadcast failed: ${e.message}")
        }
    }
}
