package nova.dunes.dunes_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.tencent.android.tpush.XGIOperateCallback
import com.tencent.android.tpush.XGPushConfig
import com.tencent.android.tpush.XGPushManager
import com.tencent.android.tpush.XGBasicPushNotificationBuilder
import com.tencent.android.tpush.XGPushClickedResult
import com.tencent.android.tpush.XGPushShowedResult
import com.tencent.tpns.baseapi.XGApiConfig
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class TpnsPushBridge(
    private val context: Context,
) {
    fun attach(engine: FlutterEngine) {
        appContext = context.applicationContext
        dartHandlerReady = false
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
                "clearConversationNotifications" ->
                    clearConversationNotificationsFromCall(call, result)
                "openNotificationSettings" -> openNotificationSettings(result)
                "isMiuiDevice" -> result.success(MiuiBadgeHelper.isMiuiDevice())
                "consumePendingNotificationClick" -> {
                    dartHandlerReady = true
                    drainPendingClick()
                    result.success(true)
                }
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
            configureTpnsNotificationBuilder()
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

    private fun clearConversationNotificationsFromCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val conversationId = (args["conversationId"] as? Number)?.toLong()
            ?: args["conversationId"]?.toString()?.toLongOrNull()
            ?: 0L
        if (conversationId <= 0L) {
            result.success(0)
            return
        }
        result.success(clearConversationNotifications(context, conversationId))
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

    /**
     * TPNS 默认通知会带 FLAG_AUTO_CANCEL，点击后通知栏条目会立即消失。
     * 清除该 flag 后，点击只负责打开 APP，通知仍可在通知栏中手动划掉；
     * 顶部 heads-up 横幅仍由 Android 系统按自己的生命周期收起。
     */
    private fun configureTpnsNotificationBuilder() {
        try {
            val builder = XGPushManager.getDefaultNotificationBuilder(context)
                ?: XGBasicPushNotificationBuilder()
            val flags = runCatching { builder.flags }.getOrDefault(0)
            builder.setFlags(flags and Notification.FLAG_AUTO_CANCEL.inv())
            XGPushManager.setDefaultNotificationBuilder(context, builder)
            Log.i(TAG, "TPNS notification auto-cancel disabled")
        } catch (e: Exception) {
            // 某些厂商 TPNS 适配器不暴露默认 builder，不能因此阻断推送初始化。
            Log.w(TAG, "configure TPNS notification builder failed", e)
        }
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
        private const val TPNS_CHANNEL_NAME = "Dunes Push"
        /*
        private const val TPNS_CHANNEL_NAME = "沙丘推送"
        */
        private const val PREFS_NAME = "dunes_tpns_push"
        private const val PENDING_CLICK_KEY = "pending_click"
        /** TPNS：0=点击，2=清除。 */
        private const val ACTION_TYPE_DELETE = 2L
        private const val NOTIFICATION_INDEX_KEY = "notification_index"
        private const val MAX_NOTIFICATION_INDEX_SIZE = 512
        private const val NOTIFICATION_INDEX_TTL_MS =
            14L * 24L * 60L * 60L * 1000L
        const val CHANNEL_NAME = "dunes/tpns_push"

        @Volatile
        var methodChannel: MethodChannel? = null

        private val mainHandler = Handler(Looper.getMainLooper())
        @Volatile
        private var appContext: Context? = null
        @Volatile
        private var dartHandlerReady = false
        private val notificationIndexLock = Any()

        fun notifyToken(token: String) {
            if (token.isBlank()) return
            methodChannel?.invokeMethod("onToken", token)
        }

        /**
         * Records the Android notification id assigned by TPNS together with
         * the IM conversation id carried in custom_content.  TPNS exposes the
         * notification id on the shown callback, but not on the clicked
         * callback, so this small persistent index is needed for clearing all
         * notifications belonging to one conversation after navigation.
         */
        fun recordNotificationShown(
            context: Context?,
            message: XGPushShowedResult?,
        ) {
            val target = context?.applicationContext ?: return
            val notificationId = message?.getNotifactionId() ?: 0
            val conversationId = conversationIdFromCustomContent(
                message?.getCustomContent(),
            )
            if (notificationId <= 0 || conversationId <= 0L) return
            val messageId = message?.getMsgId() ?: 0L
            val now = System.currentTimeMillis()
            synchronized(notificationIndexLock) {
                val prefs = target.getSharedPreferences(
                    PREFS_NAME,
                    Context.MODE_PRIVATE,
                )
                val records = readNotificationIndex(prefs, now)
                records.removeAll { record ->
                    record.optInt("notificationId", 0) == notificationId ||
                        (messageId > 0L &&
                            record.optLong("messageId", 0L) == messageId)
                }
                records.add(
                    JSONObject().apply {
                        put("notificationId", notificationId)
                        put("messageId", messageId)
                        put("conversationId", conversationId)
                        put("createdAt", now)
                    },
                )
                while (records.size > MAX_NOTIFICATION_INDEX_SIZE) {
                    records.removeAt(0)
                }
                writeNotificationIndex(prefs, records)
            }
            Log.i(
                TAG,
                "tracked notification=$notificationId conversation=$conversationId",
            )
        }

        /** Clears only the TPNS notifications previously associated with a conversation. */
        fun clearConversationNotifications(
            context: Context?,
            conversationId: Long,
        ): Int {
            val target = context?.applicationContext ?: return 0
            if (conversationId <= 0L) return 0
            val notificationIds = linkedSetOf<Int>()
            synchronized(notificationIndexLock) {
                val prefs = target.getSharedPreferences(
                    PREFS_NAME,
                    Context.MODE_PRIVATE,
                )
                val records = readNotificationIndex(
                    prefs,
                    System.currentTimeMillis(),
                )
                val remaining = records.filter { record ->
                    val belongs =
                        record.optLong("conversationId", 0L) == conversationId
                    if (belongs) {
                        val notificationId = record.optInt("notificationId", 0)
                        if (notificationId > 0) notificationIds.add(notificationId)
                    }
                    !belongs
                }
                writeNotificationIndex(prefs, remaining)
            }

            val manager = target.getSystemService(NotificationManager::class.java)
            for (notificationId in notificationIds) {
                runCatching {
                    // TPNS delegates this call to NotificationManager.cancel,
                    // keeping the cancellation scoped to one notification id.
                    XGPushManager.cancelNotifaction(target, notificationId)
                }.onFailure { error ->
                    Log.w(TAG, "cancel TPNS notification failed id=$notificationId", error)
                }
                runCatching { manager?.cancel(notificationId) }
            }
            Log.i(
                TAG,
                "cleared ${notificationIds.size} notifications for conversation=$conversationId",
            )
            return notificationIds.size
        }

        fun notifyNotificationShown() {
            methodChannel?.invokeMethod("onNotificationShown", null)
        }

        fun notifyNotificationClicked(context: Context?, message: XGPushClickedResult?) {
            val payload = notificationClickPayload(message)
            val actionType = (payload["actionType"] as? Number)?.toLong() ?: 0L
            // 双保险：清除通知不写 pending、不转发 Flutter，避免误进会话。
            if (actionType == ACTION_TYPE_DELETE) {
                Log.i(TAG, "ignore TPNS notification clear actionType=$actionType")
                return
            }
            val target = context?.applicationContext
            if (methodChannel == null || !dartHandlerReady) {
                if (target == null) return
                appContext = target
                target.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(PENDING_CLICK_KEY, JSONObject().apply {
                        put("messageId", payload["messageId"])
                        put("title", payload["title"])
                        put("body", payload["body"])
                        put("customContent", payload["customContent"])
                        put("actionType", payload["actionType"])
                        payload["eventType"]?.let { put("eventType", it) }
                        payload["tab"]?.let { put("tab", it) }
                        payload["conversationId"]?.let { put("conversationId", it) }
                        payload["noticeId"]?.let { put("noticeId", it) }
                    }.toString())
                    .apply()
                return
            }
            dispatchNotificationClicked(payload)
        }

        private fun notificationClickPayload(message: XGPushClickedResult?): HashMap<String, Any> {
            val customContent = message?.customContent ?: ""
            val payload = hashMapOf<String, Any>(
                "messageId" to (message?.getMsgId() ?: 0L),
                "title" to (message?.title ?: ""),
                "body" to (message?.content ?: ""),
                "customContent" to customContent,
                "actionType" to (message?.getActionType() ?: 0L),
            )
            val custom = parseCustomContent(customContent) ?: return payload
            custom.optString("eventType").trim().takeIf { it.isNotEmpty }?.let {
                payload["eventType"] = it
            }
            custom.optString("tab").trim().takeIf { it.isNotEmpty }?.let {
                payload["tab"] = it
            }
            custom.optLong("conversationId", 0L).takeIf { it > 0L }?.let {
                payload["conversationId"] = it
            }
            custom.optLong("noticeId", 0L).takeIf { it > 0L }?.let {
                payload["noticeId"] = it
            }
            return payload
        }

        private fun parseCustomContent(customContent: String?): JSONObject? {
            val raw = customContent?.trim().orEmpty()
            if (raw.isEmpty()) return null
            return runCatching { JSONObject(raw) }.getOrNull()
        }

        private fun conversationIdFromCustomContent(customContent: String?): Long {
            val json = parseCustomContent(customContent) ?: return 0L
            val eventType = json.optString("eventType").trim()
            if (!eventType.equals("im", ignoreCase = true) &&
                !eventType.equals("dune_announcement", ignoreCase = true) &&
                !eventType.equals("broadcast", ignoreCase = true) &&
                !eventType.equals("admin_notice", ignoreCase = true) &&
                !eventType.equals("administrative_notice", ignoreCase = true)
            ) {
                return 0L
            }
            return json.optLong("conversationId", 0L)
        }

        private fun readNotificationIndex(
            prefs: android.content.SharedPreferences,
            now: Long,
        ): MutableList<JSONObject> {
            val raw = prefs.getString(NOTIFICATION_INDEX_KEY, null)
            if (raw.isNullOrBlank()) return mutableListOf()
            val array = runCatching { JSONArray(raw) }.getOrNull()
                ?: return mutableListOf()
            val records = mutableListOf<JSONObject>()
            for (index in 0 until array.length()) {
                val record = array.optJSONObject(index) ?: continue
                val createdAt = record.optLong("createdAt", 0L)
                if (createdAt > 0L && now - createdAt > NOTIFICATION_INDEX_TTL_MS) {
                    continue
                }
                records.add(record)
            }
            return records
        }

        private fun writeNotificationIndex(
            prefs: android.content.SharedPreferences,
            records: List<JSONObject>,
        ) {
            val array = JSONArray()
            records.forEach { array.put(it) }
            prefs.edit().putString(NOTIFICATION_INDEX_KEY, array.toString()).apply()
        }

        private fun dispatchNotificationClicked(payload: Map<String, Any>) {
            mainHandler.post {
                methodChannel?.invokeMethod("onNotificationClicked", payload)
            }
        }

        private fun drainPendingClick() {
            val context = appContext ?: return
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(PENDING_CLICK_KEY, null) ?: return
            prefs.edit().remove(PENDING_CLICK_KEY).apply()
            try {
                val json = JSONObject(raw)
                val actionType = json.optLong("actionType", 0L)
                // 兼容升级前已误存的「清除」pending，丢弃不跳转。
                if (actionType == ACTION_TYPE_DELETE) {
                    Log.i(TAG, "drop pending TPNS clear actionType=$actionType")
                    return
                }
                dispatchNotificationClicked(
                    hashMapOf<String, Any>(
                        "messageId" to json.optLong("messageId", 0L),
                        "title" to json.optString("title", ""),
                        "body" to json.optString("body", ""),
                        "customContent" to json.optString("customContent", ""),
                        "actionType" to actionType,
                    ).apply {
                        json.optString("eventType").takeIf { it.isNotEmpty }?.let {
                            put("eventType", it)
                        }
                        json.optString("tab").takeIf { it.isNotEmpty }?.let {
                            put("tab", it)
                        }
                        json.optLong("conversationId", 0L).takeIf { it > 0L }?.let {
                            put("conversationId", it)
                        }
                        json.optLong("noticeId", 0L).takeIf { it > 0L }?.let {
                            put("noticeId", it)
                        }
                    },
                )
            } catch (e: Exception) {
                Log.w(TAG, "restore pending TPNS click failed", e)
            }
        }
    }
}
