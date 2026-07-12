package com.workmate4u.workmate4u

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.workmate4u/navigation"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Android 13+ (API 33): use OnBackInvokedCallback so we intercept
        // the new predictive-back gesture before Flutter's own callback.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            window.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY, // 100 > Flutter default 0
            ) {
                sendBackToFlutter()
            }
        }
    }

    // Android < 13: the classic onBackPressed() path.
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            sendBackToFlutter()
        } else {
            // On Android 13+ the OnBackInvokedCallback above handles it.
            super.onBackPressed()
        }
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
        super.onBackPressed()
    }
}

