package nova.dunes.dunes_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.tencent.android.tpush.XGIOperateCallback
import com.tencent.android.tpush.XGPushConfig
import com.tencent.android.tpush.XGPushManager
import com.tencent.tpns.baseapi.XGApiConfig
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TpnsPushBridge(
    private val context: Context,
) {
    fun attach(engine: FlutterEngine) {
        val channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> initPush(call, result)
                "getToken" -> result.success(XGPushConfig.getToken(context))
                "bindAccount" -> bindAccount(call, result)
                "unbindAccount" -> unbindAccount(call, result)
                "setBadge" -> setBadge(call, result)
                "openNotificationSettings" -> openNotificationSettings(result)
                "isMiuiDevice" -> result.success(MiuiBadgeHelper.isMiuiDevice())
                else -> result.notImplemented()
            }
        }
    }

    private fun initPush(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val accessId = (args["accessId"] as? String)?.toLongOrNull()
        val accessKey = args["accessKey"] as? String

        try {
            if (accessId != null && !accessKey.isNullOrBlank()) {
                XGPushConfig.setAccessId(context, accessId)
                XGPushConfig.setAccessKey(context, accessKey)
            }

            (args["clusterDomain"] as? String)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { XGApiConfig.setServerSuffix(context, it) }

            (args["miPushAppId"] as? String)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { XGPushConfig.setMiPushAppId(context, it) }

            (args["miPushAppKey"] as? String)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?.let { XGPushConfig.setMiPushAppKey(context, it) }

            ensureTpnsNotificationChannel()
            XGPushConfig.enableOtherPush(context, true)
            XGPushManager.registerPush(context)
            Log.i(TAG, "TPNS registerPush invoked")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "TPNS init failed", e)
            result.error("INIT_FAILED", e.message, null)
        }
    }

    private fun bindAccount(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val account = args["account"]?.toString()?.trim().orEmpty()
        if (account.isEmpty()) {
            result.error("INVALID", "account is empty", null)
            return
        }
        XGPushManager.bindAccount(
            context,
            account,
            XGPushManager.AccountType.CUSTOM.value,
            noopCallback(result),
        )
    }

    private fun unbindAccount(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val account = args["account"]?.toString()?.trim().orEmpty()
        if (account.isEmpty()) {
            result.success(true)
            return
        }
        XGPushManager.delAccount(
            context,
            account,
            XGPushManager.AccountType.CUSTOM.value,
            noopCallback(result),
        )
    }

    private fun setBadge(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val count = (args["count"] as? Number)?.toInt() ?: 0
        Log.i(TAG, "setBadge from Flutter count=$count")
        BadgeHelper.applyCount(context, count)
        result.success(true)
    }

    private fun openNotificationSettings(result: MethodChannel.Result) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", context.packageName, null)
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.w(TAG, "openNotificationSettings failed", e)
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    private fun ensureTpnsNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        // 关闭通知渠道角标，避免 MIUI 在通知展示时再自动 +1（与精确角标叠加成 2）。
        manager.deleteNotificationChannel("dunes_tpns_messages")
        val existing = manager.getNotificationChannel(TPNS_CHANNEL_ID)
        if (existing != null && !existing.canShowBadge()) return
        if (existing != null) {
            manager.deleteNotificationChannel(TPNS_CHANNEL_ID)
        }
        val channel = NotificationChannel(
            TPNS_CHANNEL_ID,
            TPNS_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "即时通讯与系统通知"
            enableVibration(true)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
        Log.i(TAG, "notification channel created showBadge=false id=$TPNS_CHANNEL_ID")
    }

    private fun noopCallback(result: MethodChannel.Result): XGIOperateCallback {
        return object : XGIOperateCallback {
            override fun onSuccess(data: Any?, flag: Int) {
                result.success(true)
            }

            override fun onFail(data: Any?, errCode: Int, msg: String?) {
                Log.w(TAG, "TPNS op failed: code=$errCode msg=$msg")
                result.success(false)
            }
        }
    }

    companion object {
        private const val TAG = "DunesTpns"
        private const val TPNS_CHANNEL_ID = "dunes_tpns_messages"
        private const val TPNS_CHANNEL_NAME = "沙丘推送"
        const val CHANNEL_NAME = "dunes/tpns_push"

        @Volatile
        var methodChannel: MethodChannel? = null

        fun notifyToken(token: String) {
            if (token.isBlank()) return
            methodChannel?.invokeMethod("onToken", token)
        }

        fun notifyNotificationShown() {
            methodChannel?.invokeMethod("onNotificationShown", null)
        }
    }
}
