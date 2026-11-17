package com.workmate4u.workmate4u

import android.os.Build
import android.os.Bundle
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.workmate4u/navigation"
    private var backCallback: OnBackInvokedCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Android 13+ (API 33): use OnBackInvokedCallback so we intercept
        // the new predictive-back gesture before Flutter's own callback.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            backCallback = OnBackInvokedCallback {
                sendBackToFlutter()
            }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                backCallback!!
            )
        }
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && backCallback != null) {
            try {
                onBackInvokedDispatcher.unregisterOnBackInvokedCallback(backCallback!!)
            } catch (_: Exception) {
            }
            backCallback = null
        }
        super.onDestroy()
    }

    // Handles back across all Android versions (3-button navigation, hardware back,
    // or as fallback whenever onBackPressed() is dispatched by the OS).
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        sendBackToFlutter()
    }

    private fun sendBackToFlutter() {
        val engine = flutterEngine
        if (engine == null) {
            defaultBack()
            return
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .invokeMethod(
                "back_pressed",
                null,
                object : MethodChannel.Result {
                    // Flutter returns true  → it handled the back (do nothing).
                    // Flutter returns false/error → fall through to Android default.
                    override fun success(result: Any?) {
                        if (result != true) defaultBack()
                    }
                    override fun error(code: String, msg: String?, details: Any?) = defaultBack()
                    override fun notImplemented() = defaultBack()
                }
            )
    }

    @Suppress("OVERRIDE_DEPRECATION")
    private fun defaultBack() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            finish()
        } else {
            super.onBackPressed()
        }
    }
}
