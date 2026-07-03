package com.carriez.flutter_hbb

import android.Manifest.permission.*
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioRecord
import android.media.AudioRecord.READ_BLOCKING
import android.media.MediaCodecList
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.provider.Settings.*
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import android.app.Activity
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat.getSystemService
import com.alipay.sdk.app.PayTask
import com.hjq.permissions.Permission
import com.hjq.permissions.XXPermissions
import com.tencent.mm.opensdk.modelpay.PayReq
import com.tencent.mm.opensdk.openapi.WXAPIFactory
import ffi.FFI
import java.nio.ByteBuffer
import java.util.*


// intent action, extra
const val ACT_REQUEST_MEDIA_PROJECTION = "REQUEST_MEDIA_PROJECTION"
const val ACT_INIT_MEDIA_PROJECTION_AND_SERVICE = "INIT_MEDIA_PROJECTION_AND_SERVICE"
const val ACT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"
const val EXT_INIT_FROM_BOOT = "EXT_INIT_FROM_BOOT"
const val EXT_MEDIA_PROJECTION_RES_INTENT = "MEDIA_PROJECTION_RES_INTENT"
const val EXT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"

// Activity requestCode
const val REQ_INVOKE_PERMISSION_ACTIVITY_MEDIA_PROJECTION = 101
const val REQ_REQUEST_MEDIA_PROJECTION = 201

// Activity responseCode
const val RES_FAILED = -100

// Flutter channel
const val START_ACTION = "start_action"
const val GET_START_ON_BOOT_OPT = "get_start_on_boot_opt"
const val SET_START_ON_BOOT_OPT = "set_start_on_boot_opt"
const val SYNC_APP_DIR_CONFIG_PATH = "sync_app_dir"
const val GET_VALUE = "get_value"
const val OPEN_PAYMENT_URI = "open_payment_uri"
const val OPEN_WECHAT_PAY = "open_wechat_pay"
const val OPEN_ALIPAY_ORDER = "open_alipay_order"
const val OPEN_ALIPAY_HTML = "open_alipay_html"
const val WECHAT_PACKAGE_NAME = "com.tencent.mm"
const val ALIPAY_PACKAGE_NAME = "com.eg.android.AlipayGphone"

const val KEY_IS_SUPPORT_VOICE_CALL = "KEY_IS_SUPPORT_VOICE_CALL"

const val KEY_SHARED_PREFERENCES = "KEY_SHARED_PREFERENCES"
const val KEY_START_ON_BOOT_OPT = "KEY_START_ON_BOOT_OPT"
const val KEY_APP_DIR_CONFIG_PATH = "KEY_APP_DIR_CONFIG_PATH"
const val KEY_WECHAT_PAY_APP_ID = "KEY_WECHAT_PAY_APP_ID"

@SuppressLint("ConstantLocale")
val LOCAL_NAME = Locale.getDefault().toString()
val SCREEN_INFO = Info(0, 0, 1, 200)

data class Info(
    var width: Int, var height: Int, var scale: Int, var dpi: Int
)

fun isSupportVoiceCall(): Boolean {
    // https://developer.android.com/reference/android/media/MediaRecorder.AudioSource#VOICE_COMMUNICATION
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
}

fun requestPermission(context: Context, type: String) {
    XXPermissions.with(context)
        .permission(type)
        .request { _, all ->
            if (all) {
                Handler(Looper.getMainLooper()).post {
                    MainActivity.flutterMethodChannel?.invokeMethod(
                        "on_android_permission_result",
                        mapOf("type" to type, "result" to all)
                    )
                }
            }
        }
}

fun startAction(context: Context, action: String) {
    try {
        context.startActivity(Intent(action).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // don't pass package name when launch ACTION_ACCESSIBILITY_SETTINGS
            if (ACTION_ACCESSIBILITY_SETTINGS != action) {
                data = Uri.parse("package:" + context.packageName)
            }
        })
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

fun isPackageInstalled(context: Context, packageName: String): Boolean {
    return try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(packageName, 0)
        }
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}

fun isAlipayInstalled(context: Context): Boolean {
    return isPackageInstalled(context, ALIPAY_PACKAGE_NAME)
}

fun openPaymentUri(context: Context, uri: String): Boolean {
    val lower = uri.trim().lowercase(Locale.ROOT)
    val isWechatUri = lower.startsWith("weixin://")
    val isAlipayUri = lower.startsWith("alipays://") || lower.startsWith("alipayqr://")
    if (isAlipayUri && !isAlipayInstalled(context)) {
        Log.w("common", "Alipay is not installed; skip payment uri launch")
        return false
    }
    return try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (isWechatUri) {
                setPackage(WECHAT_PACKAGE_NAME)
            } else if (isAlipayUri) {
                setPackage(ALIPAY_PACKAGE_NAME)
            }
        })
        true
    } catch (e: Exception) {
        Log.e("common", "Failed to open payment uri: ${e.message}", e)
        false
    }
}

private fun mapStringArg(args: Map<*, *>, key: String): String {
    return args[key]?.toString()?.trim() ?: ""
}

fun openWechatPay(activity: Activity, args: Map<*, *>): Map<String, Any> {
    val appId = mapStringArg(args, "appId")
    val partnerId = mapStringArg(args, "partnerId")
    val prepayId = mapStringArg(args, "prepayId")
    val packageValue = mapStringArg(args, "packageValue").ifEmpty { "Sign=WXPay" }
    val nonceStr = mapStringArg(args, "nonceStr")
    val timeStamp = mapStringArg(args, "timeStamp")
    val sign = mapStringArg(args, "sign")

    if (appId.isEmpty() || partnerId.isEmpty() || prepayId.isEmpty() ||
        packageValue.isEmpty() || nonceStr.isEmpty() || timeStamp.isEmpty() || sign.isEmpty()
    ) {
        return mapOf(
            "opened" to false,
            "error" to "Missing WeChat Pay request parameter"
        )
    }

    return try {
        activity.getSharedPreferences(KEY_SHARED_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_WECHAT_PAY_APP_ID, appId)
            .apply()
        val api = WXAPIFactory.createWXAPI(activity, appId, false)
        api.registerApp(appId)
        if (!api.isWXAppInstalled) {
            return mapOf(
                "opened" to false,
                "error" to "WeChat is not installed"
            )
        }
        val request = PayReq().apply {
            this.appId = appId
            this.partnerId = partnerId
            this.prepayId = prepayId
            this.packageValue = packageValue
            this.nonceStr = nonceStr
            this.timeStamp = timeStamp
            this.sign = sign
        }
        val opened = api.sendReq(request)
        mapOf(
            "opened" to opened,
            "error" to if (opened) "" else "WeChat OpenSDK sendReq returned false"
        )
    } catch (e: Exception) {
        Log.e("common", "Failed to open WeChat Pay: ${e.message}", e)
        mapOf(
            "opened" to false,
            "error" to (e.message ?: "WeChat Pay SDK launch failed")
        )
    }
}

fun openAlipayOrder(activity: Activity, orderInfo: String): Map<String, String> {
    return try {
        val result = PayTask(activity).payV2(orderInfo, true)
        Log.d("common", "Alipay payV2 resultStatus=${result["resultStatus"]}, memo=${result["memo"]}")
        result.mapValues { it.value?.toString() ?: "" }
    } catch (e: Exception) {
        Log.e("common", "Failed to open Alipay order: ${e.message}", e)
        mapOf(
            "resultStatus" to "",
            "memo" to (e.message ?: "Alipay SDK launch failed"),
            "result" to ""
        )
    }
}

fun openAlipayHtmlCheckout(context: Context, html: String): Boolean {
    if (html.isBlank()) return false
    if (!isAlipayInstalled(context)) {
        Log.w("common", "Alipay is not installed; skip HTML checkout activity")
        return false
    }
    return try {
        context.startActivity(Intent(context, AlipayCheckoutActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(EXTRA_ALIPAY_HTML, html)
        })
        true
    } catch (e: Exception) {
        Log.e("common", "Failed to open Alipay HTML checkout: ${e.message}", e)
        false
    }
}

class AudioReader(val bufSize: Int, private val maxFrames: Int) {
    private var currentPos = 0
    private val bufferPool: Array<ByteBuffer>

    init {
        if (maxFrames < 0 || maxFrames > 32) {
            throw Exception("Out of bounds")
        }
        if (bufSize <= 0) {
            throw Exception("Wrong bufSize")
        }
        bufferPool = Array(maxFrames) {
            ByteBuffer.allocateDirect(bufSize)
        }
    }

    private fun next() {
        currentPos++
        if (currentPos >= maxFrames) {
            currentPos = 0
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun readSync(audioRecord: AudioRecord): ByteBuffer? {
        val buffer = bufferPool[currentPos]
        val res = audioRecord.read(buffer, bufSize, READ_BLOCKING)
        return if (res > 0) {
            next()
            buffer
        } else {
            null
        }
    }
}


fun getScreenSize(windowManager: WindowManager) : Pair<Int, Int>{
    var w = 0
    var h = 0
    @Suppress("DEPRECATION")
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val m = windowManager.maximumWindowMetrics
        w = m.bounds.width()
        h = m.bounds.height()
    } else {
        val dm = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(dm)
        w = dm.widthPixels
        h = dm.heightPixels
    }
    return Pair(w, h)
}

 fun translate(input: String): String {
    Log.d("common", "translate:$LOCAL_NAME")
    return FFI.translateLocale(LOCAL_NAME, input)
}
