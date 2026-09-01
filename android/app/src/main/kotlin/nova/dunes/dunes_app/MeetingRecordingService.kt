package nova.dunes.dunes_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 麦克风类型的前台服务。
 *
 * Android 10/11/14 要求：只有存在「microphone」类型的前台服务时，App 切后台或锁屏后
 * 才被允许继续采集麦克风；否则系统会静音麦克风。录音期间启动本服务并展示常驻通知。
 */
class MeetingRecordingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        try {
            taskRemovedListener?.invoke()
        } catch (_: Exception) {
        }
        super.onTaskRemoved(rootIntent)
        stopSelf()
    }

    private fun startAsForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "会议录音",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    setShowBadge(false)
                    description = "会议录音进行时的常驻提示"
                }
                mgr.createNotificationChannel(channel)
            }
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("沙丘 · 会议录音进行中")
            .setContentText("正在后台录音，结束后生成纪要")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val CHANNEL_ID = "dunes_meeting_recording"
        private const val NOTIFICATION_ID = 4711

        @Volatile
        var taskRemovedListener: (() -> Unit)? = null

        fun start(context: Context) {
            val intent = Intent(context, MeetingRecordingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MeetingRecordingService::class.java))
        }

        fun update(context: Context, title: String, text: String) {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
            mgr.notify(NOTIFICATION_ID, notification)
        }
    }
}
