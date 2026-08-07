package nova.dunes.dunes_app

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import com.tencent.android.tpush.XGPushBaseReceiver
import com.tencent.android.tpush.XGPushClickedResult
import com.tencent.android.tpush.XGPushRegisterResult
import com.tencent.android.tpush.XGPushShowedResult
import com.tencent.android.tpush.XGPushTextMessage
import org.json.JSONObject

class DunesTpnsReceiver : XGPushBaseReceiver() {
    override fun onRegisterResult(
        context: Context?,
        errorCode: Int,
        message: XGPushRegisterResult?,
    ) {
        if (context == null || message == null) return
        if (errorCode != SUCCESS) {
            Log.w(TAG, "TPNS register failed: code=$errorCode token=${message.token}")
            return
        }
        val token = message.token
        if (token.isNullOrBlank()) return
        Log.i(TAG, "TPNS register success")
        TpnsPushBridge.notifyToken(token)
    }

    override fun onUnregisterResult(context: Context?, errorCode: Int) {}

    override fun onSetTagResult(context: Context?, errorCode: Int, tagName: String?) {}

    override fun onDeleteTagResult(context: Context?, errorCode: Int, tagName: String?) {}

    override fun onSetAccountResult(context: Context?, errorCode: Int, account: String?) {}

    override fun onDeleteAccountResult(context: Context?, errorCode: Int, account: String?) {}

    override fun onSetAttributeResult(context: Context?, errorCode: Int, attribute: String?) {}

    override fun onQueryTagsResult(
        context: Context?,
        errorCode: Int,
        tagName: String?,
        tagList: String?,
    ) {}

    override fun onDeleteAttributeResult(context: Context?, errorCode: Int, attribute: String?) {}

    override fun onTextMessage(context: Context?, message: XGPushTextMessage?) {}

    override fun onNotificationClickedResult(
        context: Context?,
        message: XGPushClickedResult?,
    ) {
        // TPNS：actionType=0 点击，actionType=2 清除。
        // 划掉通知不能当点击，否则会写入 pending_click，下次打开 App 误进会话。
        val actionType = message?.getActionType() ?: 0L
        if (actionType == ACTION_TYPE_DELETE) {
            Log.i(TAG, "notification cleared title=${message?.title}, ignore routing")
            return
        }
        Log.i(TAG, "notification clicked title=${message?.title} actionType=$actionType")
        // TPNS 通知的点击不会被主动 cancel；同时把 payload 暂存给 Flutter，
        // 兼容 APP 冷启动时 Flutter 引擎尚未 attach 的情况。
        TpnsPushBridge.notifyNotificationClicked(context, message)
    }

    override fun onNotificationShowedResult(
        context: Context?,
        message: XGPushShowedResult?,
    ) {
        if (context == null) return
        Log.i(TAG, "notification showed title=${message?.title}")
        // 不再裁剪通知：MIUI 桌面角标取决于通知栏条数，删通知会把角标拽回 1。
        // 让通知自然累加（条数=未读数），角标即可正确显示；归零由 applyCount(0) 清通知。
        val badge = parseBadgeCount(message?.customContent)
        if (badge != null) {
            Log.i(TAG, "notification badge from server=$badge")
            BadgeHelper.applyCount(context, badge)
        }
        TpnsPushBridge.recordNotificationShown(context, message)
        TpnsPushBridge.notifyNotificationShown()
    }

    private fun parseBadgeCount(customContent: String?): Int? {
        val raw = customContent?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return try {
            val json = JSONObject(raw)
            when {
                json.has("badgeCount") -> json.optInt("badgeCount", -1)
                json.has("badge") -> json.optInt("badge", -1)
                else -> -1
            }.takeIf { it >= 0 }
        } catch (e: Exception) {
            Log.w(TAG, "parse badge customContent failed: ${e.message}")
            null
        }
    }

    companion object {
        private const val TAG = "DunesTpns"
        private const val ACTION_TYPE_DELETE = 2L
    }
}
