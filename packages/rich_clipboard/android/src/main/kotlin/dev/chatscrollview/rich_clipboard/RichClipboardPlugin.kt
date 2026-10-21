package dev.chatscrollview.rich_clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Android side of rich_clipboard: one clip with the plain text and the
 * HTML (`ClipData.newHtmlText`), the form the reference client writes and
 * reads, so each reader takes the richest it knows.
 */
class RichClipboardPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // Reads run here, one at a time: an item's text may be read from a
    // content provider, and media is copied out of one, neither of which the
    // main thread can wait for.
    private val reader: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "rich_clipboard")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        reader.shutdown()
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
                val withMedia = call.argument<Boolean>("media") == true
                reader.execute {
                    try {
                        val held = contents(clipboard.primaryClip, withMedia)
                        main.post { result.success(held) }
                    } catch (error: Exception) {
                        main.post { result.error("unavailable", error.message, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // The first item's plain text and HTML, and with [withMedia] the clip's
    // media; a type the clip does not hold is left out, and null for none.
    private fun contents(clip: ClipData?, withMedia: Boolean): Map<String, Any>? {
        if (clip == null || clip.itemCount == 0) return null
        val held = HashMap<String, Any>()
        val item = clip.getItemAt(0)
        val html = item.htmlText
        // An item that points at content (an image another app copied) has
        // no text: the text form of its URI is not what was copied. An item
        // that holds only an intent, or a URI to text, gives the text a plain
        // paste would insert.
        val plain = item.text?.toString()
            ?: if (item.uri?.let { mediaType(it, clip) } != null) {
                null
            } else {
                item.coerceToText(context)?.toString()
            }
        if (!plain.isNullOrEmpty()) held["plain"] = plain
        if (!html.isNullOrEmpty()) held["html"] = html
        if (withMedia) {
            val media = media(clip)
            if (media.isNotEmpty()) held["media"] = media
        }
        return if (held.isEmpty()) null else held
    }

    // The clip's items that point at content (an image or a file another app
    // copied), each copied into the app's cache, as the reference client does
    // with a pasted image: the content may be large, and the provider's grant
    // may not outlive the paste.
    private fun media(clip: ClipData): List<Map<String, Any>> {
        val found = ArrayList<Map<String, Any>>()
        for (index in 0 until clip.itemCount) {
            val uri = clip.getItemAt(index).uri ?: continue
            val mime = mediaType(uri, clip) ?: continue
            val file = copied(uri, nameOf(uri, mime)) ?: continue
            found.add(hashMapOf("path" to file.path, "mimeType" to mime))
        }
        return found
    }

    // The type of the content [uri] points at, null when it is text.
    private fun mediaType(uri: Uri, clip: ClipData): String? {
        val mime = try {
            context.contentResolver.getType(uri)
        } catch (_: Exception) {
            null
        } ?: clip.description.takeIf { it.mimeTypeCount > 0 }?.getMimeType(0)
            ?: return null
        return if (mime.startsWith("text/")) null else mime
    }

    // [uri]'s content in a folder of its own in the cache, under [name]. The
    // system clears the cache; the host reads the file from there.
    private fun copied(uri: Uri, name: String): File? = try {
        val folder = File(context.cacheDir, "rich_clipboard/${UUID.randomUUID()}")
        folder.mkdirs()
        val file = File(folder, name)
        val input = context.contentResolver.openInputStream(uri)
        if (input == null) {
            null
        } else {
            input.use { source -> file.outputStream().use { source.copyTo(it) } }
            file
        }
    } catch (_: Exception) {
        null
    }

    // The name the provider gives [uri], else one with [mime]'s extension.
    private fun nameOf(uri: Uri, mime: String): String {
        val given = try {
            context.contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
        val safe = given?.replace('/', '_')?.takeIf { it.isNotBlank() }
        if (safe != null) return safe
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        return if (extension == null) "pasted" else "pasted.$extension"
    }
}
