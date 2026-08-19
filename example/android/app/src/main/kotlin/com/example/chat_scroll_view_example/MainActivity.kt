package com.example.chat_scroll_view_example

import android.content.Context
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var interceptPreImeBack = false
    private var preImeBackChannel: MethodChannel? = null
    private var backCallbackRegistered = false

    private val preImeOnBackCallback: OnBackInvokedCallback? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            OnBackInvokedCallback { deliverPreImeBack() }
        } else {
            null
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HAPTIC_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "playError") {
                playSelectionLimit()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        preImeBackChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRE_IME_BACK_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        setIntercepting(true)
                        result.success(null)
                    }
                    "release" -> {
                        setIntercepting(false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        setIntercepting(false)
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (interceptPreImeBack) {
            deliverPreImeBack()
            return
        }
        super.onBackPressed()
    }

    /// [Activity] has no `dispatchKeyEventPreIme`. Wrap the Flutter view so
    /// Back is claimed before the IME while a pre-IME back claim is active.
    override fun setContentView(view: View?) {
        super.setContentView(view?.let(::wrapPreImeBack))
    }

    override fun setContentView(view: View?, params: ViewGroup.LayoutParams?) {
        super.setContentView(view?.let(::wrapPreImeBack), params)
    }

    private fun wrapPreImeBack(view: View): View {
        if (view is PreImeBackFrame) return view
        val wrapper = PreImeBackFrame()
        wrapper.addView(
            view,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        return wrapper
    }

    private fun setIntercepting(enabled: Boolean) {
        interceptPreImeBack = enabled
        val callback = preImeOnBackCallback
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || callback == null) {
            return
        }
        if (enabled && !backCallbackRegistered) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                callback,
            )
            backCallbackRegistered = true
        } else if (!enabled && backCallbackRegistered) {
            onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback)
            backCallbackRegistered = false
        }
    }

    private fun deliverPreImeBack() {
        preImeBackChannel?.invokeMethod("onBack", null)
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
        @Suppress("DEPRECATION")
        vibrator.vibrate(200)
    }

    private inner class PreImeBackFrame : FrameLayout(this@MainActivity) {
        override fun dispatchKeyEventPreIme(event: KeyEvent): Boolean {
            if (interceptPreImeBack && event.keyCode == KeyEvent.KEYCODE_BACK) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    deliverPreImeBack()
                }
                return true
            }
            return super.dispatchKeyEventPreIme(event)
        }
    }

    companion object {
        private const val HAPTIC_CHANNEL = "chat_scroll_view_example/selection_cap_haptic"
        private const val PRE_IME_BACK_CHANNEL = "chat_scroll_view_example/pre_ime_back"
    }
}
