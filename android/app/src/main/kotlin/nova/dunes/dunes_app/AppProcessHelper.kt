package nova.dunes.dunes_app

import android.app.ActivityManager
import android.content.Context

object AppProcessHelper {
    fun isMainProcessRunning(context: Context): Boolean {
        val appContext = context.applicationContext
        val expected = appContext.packageName
        val manager = appContext.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        return manager.runningAppProcesses.orEmpty().any { process ->
            process.processName == expected
        }
    }
}
