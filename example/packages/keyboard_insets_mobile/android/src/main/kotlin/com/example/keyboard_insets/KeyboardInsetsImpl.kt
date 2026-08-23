package com.example.keyboard_insets

import android.app.Activity
import androidx.annotation.Keep
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsCompat.Type

// Native callback (into C)
private external fun platform_update_inset(inset: Float, target: Float)

object KeyboardInsets {
    private var activity: Activity? = null
    private var rootView: android.view.View? = null
    /** Upper bound from the in-flight IME animation; valid only while [imeAnimationCount] > 0. */
    private var targetInsetDp: Float = 0f
    private var imeAnimationCount: Int = 0
    private var isKeyboardAnimationEnabled: Boolean = true

    fun setActivity(act: Activity?) {
        activity = act
    }

    private val density: Float
        get() = activity?.resources?.displayMetrics?.density ?: 1f

    @Keep
    @JvmStatic
    fun setKeyboardAnimation(isEnabled: Boolean) {
        isKeyboardAnimationEnabled = isEnabled
    }

    @Keep
    @JvmStatic
    fun startKeyboardObserver() {
        rootView =
                activity?.window?.decorView
                        ?: run {
                            return
                        }
        val view = rootView!!

        // First immediate push — settled IME only (no stale animation target).
        imeAnimationCount = 0
        targetInsetDp = 0f
        val insets = ViewCompat.getRootWindowInsets(view)
        pushInset(insets)

        // Listen for changes
        ViewCompat.setOnApplyWindowInsetsListener(view) { _, newInsets ->
            pushInset(newInsets)
            newInsets
        }

        // Animation callback
        ViewCompat.setWindowInsetsAnimationCallback(
                view,
                object :
                        WindowInsetsAnimationCompat.Callback(
                                WindowInsetsAnimationCompat.Callback
                                        .DISPATCH_MODE_CONTINUE_ON_SUBTREE
                        ) {
                    override fun onPrepare(animation: WindowInsetsAnimationCompat) {
                        if (animation.typeMask and Type.ime() != 0) {
                            imeAnimationCount++
                        }
                    }

                    override fun onStart(
                            animation: WindowInsetsAnimationCompat,
                            bounds: WindowInsetsAnimationCompat.BoundsCompat
                    ): WindowInsetsAnimationCompat.BoundsCompat {
                        if (animation.typeMask and Type.ime() != 0) {
                            targetInsetDp = bounds.upperBound.bottom / density
                        }
                        return bounds
                    }

                    override fun onProgress(
                            insets: WindowInsetsCompat,
                            runningAnimations: MutableList<WindowInsetsAnimationCompat>
                    ): WindowInsetsCompat {
                        if (isKeyboardAnimationEnabled) {
                            pushInset(insets)
                        }
                        return insets
                    }

                    override fun onEnd(animation: WindowInsetsAnimationCompat) {
                        if (animation.typeMask and Type.ime() != 0) {
                            imeAnimationCount = (imeAnimationCount - 1).coerceAtLeast(0)
                            if (imeAnimationCount == 0) {
                                // Animation finished — drop stale upper bound so
                                // hidden IME reports target=0 (not last peak).
                                targetInsetDp = 0f
                            }
                            pushInset(ViewCompat.getRootWindowInsets(view))
                        }
                    }
                }
        )
    }

    @Keep
    @JvmStatic
    fun stopKeyboardObserver() {
        rootView?.let { view ->
            ViewCompat.setOnApplyWindowInsetsListener(view, null)
            ViewCompat.setWindowInsetsAnimationCallback(view, null)
        }
        rootView = null
        imeAnimationCount = 0
        targetInsetDp = 0f
    }

    private fun pushInset(insets: WindowInsetsCompat?) {
        val navBottom = insets?.getInsets(WindowInsetsCompat.Type.systemBars())?.bottom ?: 0

        val imeBottomPx =
                ((insets?.getInsets(Type.ime())?.bottom ?: 0) - navBottom).coerceAtLeast(0)
        val keyboardDp = imeBottomPx / density

        // Settled: target == current. Only during an IME animation may target
        // differ (upper bound). Never keep a previous keyboard peak as target
        // after the keyboard is gone — that made isVisible/isAnimating stick
        // true across Flutter hot restarts and layout-only inset passes.
        val target =
                if (imeAnimationCount > 0) {
                    (targetInsetDp - navBottom / density).coerceAtLeast(0f)
                } else {
                    keyboardDp
                }

        platform_update_inset(keyboardDp.toFloat(), target.toFloat())
    }
}
