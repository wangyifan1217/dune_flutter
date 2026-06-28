package nova.dunes.dunes_app

import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.tencent.android.tpush.XGPushConfig
import me.leolin.shortcutbadger.ShortcutBadger

object BadgeHelper {
    private const val TAG = "DunesBadge"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val BADGE_KEY = "flutter.dunes_push_badge_count"

    fun readCount(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val count = readStoredCount(prefs)
        Log.i(TAG, "readCount=$count")
        return count
    }

    private fun readStoredCount(prefs: SharedPreferences): Int {
        if (!prefs.contains(BADGE_KEY)) return 0
        return try {
            prefs.getInt(BADGE_KEY, 0)
        } catch (e: ClassCastException) {
            // Flutter shared_preferences may store integers as Long on Android.
            prefs.getLong(BADGE_KEY, 0L).toInt()
        }.coerceAtLeast(0)
    }

    fun applyCount(context: Context, count: Int) {
        val appContext = context.applicationContext
        val next = count.coerceAtLeast(0)
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val previous = readStoredCount(prefs)
        if (previous == next) {
            Log.i(TAG, "applyCount skip unchanged=$next")
            applyLauncherBadge(appContext, next)
            return
        }
        prefs.edit().putInt(BADGE_KEY, next).apply()
        Log.i(TAG, "applyCount requested=$count normalized=$next previous=$previous")
        try {
            XGPushConfig.setBadgeNum(appContext, next)
            Log.i(TAG, "TPNS setBadgeNum=$next")
        } catch (e: Exception) {
            Log.w(TAG, "TPNS setBadgeNum failed: ${e.message}")
        }
        applyLauncherBadge(appContext, next)
    }

    private fun applyLauncherBadge(context: Context, count: Int) {
        // MIUI/HyperOS 桌面角标取决于通知栏条数；角标归零时必须清掉所有通知，
        // 否则系统会按残留通知条数继续显示角标。
        if (count <= 0) {
            clearAllNotifications(context)
        }
        if (MiuiBadgeHelper.isMiuiDevice()) {
            MiuiBadgeHelper.applyCount(context, count)
            return
        }
        try {
            if (count <= 0) {
                ShortcutBadger.removeCount(context)
            } else {
                ShortcutBadger.applyCount(context, count)
            }
            Log.i(TAG, "ShortcutBadger applied count=$count")
        } catch (e: Exception) {
            Log.w(TAG, "ShortcutBadger failed: ${e.message}")
        }
    }

    private fun clearAllNotifications(context: Context) {
        try {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm?.cancelAll()
            Log.i(TAG, "cleared all notifications for badge=0")
        } catch (e: Exception) {
            Log.w(TAG, "clearAllNotifications failed: ${e.message}")
        }
    }

    fun increment(context: Context) {
        val before = readCount(context)
        Log.i(TAG, "increment before=$before after=${before + 1}")
        applyCount(context, before + 1)
    }
}
