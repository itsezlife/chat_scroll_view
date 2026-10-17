package dev.chatscrollview.rich_clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * The Android side of rich_clipboard: one clip with the plain text and the
 * HTML (`ClipData.newHtmlText`), the form the reference client writes and
 * reads, so each reader takes the richest it knows.
 */
class RichClipboardPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "rich_clipboard")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val clipboard =
            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        when (call.method) {
            "write" -> {
                val plain = call.argument<String>("plain")
                val html = call.argument<String>("html")
                if (plain == null || html == null) {
                    result.error("bad-arguments", "write takes plain and html", null)
                    return
                }
                clipboard.setPrimaryClip(ClipData.newHtmlText("text", plain, html))
                result.success(null)
            }
            "read" -> {
                val clip = clipboard.primaryClip
                if (clip == null || clip.itemCount == 0) {
                    result.success(null)
                    return
                }
                val item = clip.getItemAt(0)
                val html = item.htmlText
                // An item may hold only a URI or an intent; its text form is
                // what a plain paste would insert.
                val plain = item.text?.toString() ?: item.coerceToText(context)?.toString()
                val held = HashMap<String, String>()
                if (!plain.isNullOrEmpty()) held["plain"] = plain
                if (!html.isNullOrEmpty()) held["html"] = html
                result.success(if (held.isEmpty()) null else held)
            }
            "readMedia" -> result.success(media(clipboard))
            else -> result.notImplemented()
        }
    }

    // The clip's items that point at content (an image or a file another app
    // copied), as data with its type and name. Text items are not media.
    private fun media(clipboard: ClipboardManager): List<Map<String, Any>> {
        val clip = clipboard.primaryClip ?: return emptyList()
        val resolver = context.contentResolver
        val found = ArrayList<Map<String, Any>>()
        for (index in 0 until clip.itemCount) {
            val uri = clip.getItemAt(index).uri ?: continue
            val mime = resolver.getType(uri)
                ?: clip.description.takeIf { it.mimeTypeCount > 0 }?.getMimeType(0)
                ?: continue
            if (mime.startsWith("text/")) continue
            val bytes = try {
                resolver.openInputStream(uri)?.use { it.readBytes() }
            } catch (_: Exception) {
                null
            } ?: continue
            val item = HashMap<String, Any>()
            item["bytes"] = bytes
            item["mimeType"] = mime
            nameOf(uri)?.let { item["name"] = it }
            found.add(item)
        }
        return found
    }

    private fun nameOf(uri: Uri): String? = try {
        context.contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }
}
