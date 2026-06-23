package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient

const val EXTRA_ALIPAY_HTML = "extra_alipay_html"

class AlipayCheckoutActivity : Activity() {
    private lateinit var webView: WebView
    private var handoffStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)
        val html = intent.getStringExtra(EXTRA_ALIPAY_HTML).orEmpty()
        if (html.isBlank()) {
            finish()
            return
        }

        webView = WebView(this)
        webView.alpha = 0f
        webView.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        setContentView(
            webView,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.cacheMode = WebSettings.LOAD_NO_CACHE
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                return handleUrl(request.url.toString())
            }

            @Suppress("OVERRIDE_DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
                return handleUrl(url)
            }
        }
        webView.postDelayed({
            if (!handoffStarted && !isFinishing) {
                finish()
            }
        }, 8000)
        webView.loadDataWithBaseURL(
            "https://openapi.alipay.com/",
            html,
            "text/html",
            "UTF-8",
            null
        )
    }

    private fun handleUrl(url: String): Boolean {
        if (handoffStarted) return true
        val lower = url.lowercase()
        if (lower.startsWith("http://") || lower.startsWith("https://")) {
            return false
        }
        return try {
            val intent = if (lower.startsWith("intent://")) {
                Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
            } else {
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
            }.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (lower.startsWith("alipays://") || lower.startsWith("alipayqr://")) {
                    setPackage("com.eg.android.AlipayGphone")
                }
            }
            startActivity(intent)
            handoffStarted = true
            finish()
            true
        } catch (e: Exception) {
            Log.e("AlipayCheckout", "Failed to hand off checkout url: ${e.message}", e)
            false
        }
    }

    override fun onDestroy() {
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.destroy()
        }
        super.onDestroy()
    }
}
