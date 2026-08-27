package dev.chat_scroll.emoji_data

import android.graphics.Paint
import androidx.annotation.NonNull
import androidx.core.graphics.PaintCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Host-side emoji glyph support probe for catalog filtering. */
class EmojiDataPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val paint = Paint()

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "emoji_data")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getSupportedEmojis" -> {
                val list = call.argument<List<String>>("source")
                val supportedList: List<Boolean>? = list?.map { glyph ->
                    PaintCompat.hasGlyph(paint, glyph)
                }
                result.success(supportedList)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
