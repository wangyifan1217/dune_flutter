package nova.dunes.dunes_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/** Keeps the τ call microphone capture eligible to run while the device is locked. */
class TauVoiceCallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANGUP) {
            sendBroadcast(
                Intent(ACTION_NOTIFICATION_HANGUP)
                    .setPackage(packageName),
            )
            stopSelf()
            return START_NOT_STICKY
        }

        startAsForeground()
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "τ 通话",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        setShowBadge(false)
                        description = "τ 电话通话中的常驻提示"
                    },
                )
            }
        }

        val hangupIntent = Intent(this, TauVoiceCallForegroundService::class.java)
            .setAction(ACTION_HANGUP)
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val hangupPendingIntent = PendingIntent.getService(this, 0, hangupIntent, pendingFlags)

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("τ 通话中")
            .setContentText("正在使用麦克风")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "挂断",
                hangupPendingIntent,
            )
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_HANGUP = "nova.dunes.dunes_app.action.TAU_VOICE_CALL_HANGUP"
        const val ACTION_NOTIFICATION_HANGUP =
            "nova.dunes.dunes_app.action.TAU_VOICE_CALL_NOTIFICATION_HANGUP"
        private const val CHANNEL_ID = "dunes_tau_voice_call"
        private const val NOTIFICATION_ID = 4712

        fun start(context: Context) {
            val intent = Intent(context, TauVoiceCallForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TauVoiceCallForegroundService::class.java))
        }
    }
}
