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
        Log.i(TAG, "notification clicked title=${message?.title}")
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
    }
}
