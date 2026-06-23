package com.carriez.flutter_hbb.wxapi

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.carriez.flutter_hbb.KEY_SHARED_PREFERENCES
import com.carriez.flutter_hbb.KEY_WECHAT_PAY_APP_ID
import com.carriez.flutter_hbb.MainActivity
import com.tencent.mm.opensdk.constants.ConstantsAPI
import com.tencent.mm.opensdk.modelbase.BaseReq
import com.tencent.mm.opensdk.modelbase.BaseResp
import com.tencent.mm.opensdk.openapi.IWXAPI
import com.tencent.mm.opensdk.openapi.IWXAPIEventHandler
import com.tencent.mm.opensdk.openapi.WXAPIFactory

class WXPayEntryActivity : Activity(), IWXAPIEventHandler {
    private var api: IWXAPI? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWechatIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWechatIntent(intent)
    }

    private fun handleWechatIntent(intent: Intent?) {
        if (intent == null) {
            finish()
            return
        }
        val appId = getSharedPreferences(KEY_SHARED_PREFERENCES, MODE_PRIVATE)
            .getString(KEY_WECHAT_PAY_APP_ID, "") ?: ""
        api = WXAPIFactory.createWXAPI(this, appId, false)
        try {
            api?.handleIntent(intent, this)
        } catch (e: Exception) {
            Log.e("WXPayEntryActivity", "Failed to handle WeChat Pay callback: ${e.message}", e)
            finish()
        }
    }

    override fun onReq(req: BaseReq) {
        finish()
    }

    override fun onResp(resp: BaseResp) {
        if (resp.type == ConstantsAPI.COMMAND_PAY_BY_WX) {
            MainActivity.flutterMethodChannel?.invokeMethod(
                "on_wechat_pay_result",
                mapOf(
                    "errCode" to resp.errCode,
                    "errStr" to (resp.errStr ?: ""),
                    "transaction" to (resp.transaction ?: ""),
                    "openId" to (resp.openId ?: "")
                )
            )
            Log.d("WXPayEntryActivity", "WeChat Pay finished errCode=${resp.errCode}")
        }
        finish()
    }
}
