package com.workmate4u.workmate4u

import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.workmate4u/navigation"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Add AFTER super.onCreate so our callback is registered LAST
        // and therefore has the HIGHEST priority in OnBackPressedDispatcher.
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    val engine = flutterEngine
                    if (engine == null) {
                        // No Flutter engine yet — let Android handle it
                        fallback()
                        return
                    }
                    MethodChannel(
                        engine.dartExecutor.binaryMessenger,
                        CHANNEL
                    ).invokeMethod(
                        "back_pressed",
                        null,
                        object : MethodChannel.Result {
                            override fun success(result: Any?) {
                                // Flutter returns true  → handled, do nothing.
                                // Flutter returns false → let Android do its default back.
                                if (result != true) fallback()
                            }
                            override fun error(
                                errorCode: String,
                                errorMessage: String?,
                                errorDetails: Any?
                            ) = fallback()
                            override fun notImplemented() = fallback()
                        }
                    )
                }

                private fun fallback() {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                    isEnabled = true
                }
            }
        )
    }
}
