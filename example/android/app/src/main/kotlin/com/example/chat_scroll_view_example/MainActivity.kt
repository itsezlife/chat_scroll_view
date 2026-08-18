package com.example.chat_scroll_view_example

import android.content.Context
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "playError") {
                playSelectionLimit()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    /// Telegram `ChatActivity.addToSelectedMessages` at the 100 cap:
    /// `vibrator.vibrate(200)` — a 200 ms one-shot, not `APP_ERROR`.
    private fun playSelectionLimit() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        // Same API Telegram uses (`vibrator.vibrate(200)`). createOneShot with
        // DEFAULT_AMPLITUDE is routed as a weak haptic on many devices.
        @Suppress("DEPRECATION")
        vibrator.vibrate(200)
    }

    companion object {
        private const val CHANNEL = "chat_scroll_view_example/selection_cap_haptic"
    }
}
