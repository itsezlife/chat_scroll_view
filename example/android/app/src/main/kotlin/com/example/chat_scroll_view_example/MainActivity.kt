package com.example.chat_scroll_view_example

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager
import android.view.KeyEvent
import android.view.Surface
import android.view.SurfaceView
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

    private var labChannel: MethodChannel? = null

    /// `adb shell am broadcast -a lab.SET --es key snap --ez value true`
    /// flips a lab switch without touching the screen;
    /// `--es key net --es value off|record|replay --es name <tape>` selects
    /// the network tape.
    private val labReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            labChannel?.invokeMethod(
                "set",
                mapOf(
                    "key" to intent.getStringExtra("key"),
                    "value" to intent.getBooleanExtra("value", false),
                    // `--es value replay`, for the keys that take a word.
                    "text" to intent.getStringExtra("value"),
                    "name" to intent.getStringExtra("name"),
                ),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        labChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAB_CHANNEL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(labReceiver, IntentFilter("lab.SET"), Context.RECEIVER_EXPORTED)
        }
        labChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(getExternalFilesDir(null)?.path)
                else -> result.notImplemented()
            }
        }
        // The app's cache folder, for the caches the Dart side keeps on disk
        // (the example takes no path_provider).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PATHS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "cacheDir" -> result.success(cacheDir.path)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FRAME_RATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "high" -> voteFrameRate(high = true)
                "default" -> voteFrameRate(high = false)
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(null)
        }
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

        // What decides whether the system confirms a copy by itself
        // (the system's clipboard-toast rule).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "clipboardToast") {
                result.success(
                    mapOf("sdkInt" to Build.VERSION.SDK_INT, "oneUi40" to isOneUi40()),
                )
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

    private var flutterSurfaceView: SurfaceView? = null

    /// Votes the display's top refresh rate for Flutter's surface while it
    /// animates, and no preference once it stops.
    ///
    /// An idle display drops to a low rate (24 Hz here). A touch raises it at
    /// once, but an animation no finger started (a scroll to a new message)
    /// waited about 250 ms for the system to notice the frames and spent them
    /// at 24 Hz; a vote on the surface switches the mode now.
    private fun voteFrameRate(high: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val view = flutterSurfaceView?.takeIf { it.isAttachedToWindow }
            ?: findSurfaceView(window.decorView)?.also { flutterSurfaceView = it }
            ?: return
        // The surface is recreated with the view's; take the current one.
        val surface = view.holder.surface
        if (!surface.isValid) return
        val rate = if (high) {
            display?.supportedModes?.maxOfOrNull { it.refreshRate } ?: 0f
        } else {
            0f
        }
        surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
    }

    private fun findSurfaceView(view: View): SurfaceView? = when (view) {
        is SurfaceView -> view
        is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull {
            findSurfaceView(view.getChildAt(it))
        }
        else -> null
    }

    /// Selecting past the 100-message cap: `vibrator.vibrate(200)` — a 200 ms
    /// one-shot, not `APP_ERROR`.
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

    /// `OneUIUtilities.hasBuiltInClipboardToasts`: One UI 4.0 exactly.
    private fun isOneUi40(): Boolean = try {
        val field = Build.VERSION::class.java.getDeclaredField("SEM_PLATFORM_INT")
        field.isAccessible = true
        val sem = field.getInt(null)
        sem >= 100000 && sem - 90000 == 40000
    } catch (e: Exception) {
        false
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
        private const val FRAME_RATE_CHANNEL = "chat_scroll_view_example/frame_rate"
        private const val HAPTIC_CHANNEL = "chat_scroll_view_example/selection_cap_haptic"
        private const val LAB_CHANNEL = "chat_scroll_view_example/lab"
        private const val PATHS_CHANNEL = "chat_scroll_view_example/paths"
        private const val PRE_IME_BACK_CHANNEL = "chat_scroll_view_example/pre_ime_back"
        private const val SYSTEM_CHANNEL = "chat_scroll_view_example/system"
    }
}
