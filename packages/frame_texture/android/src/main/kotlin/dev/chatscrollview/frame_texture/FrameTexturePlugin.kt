package dev.chatscrollview.frame_texture

import android.util.Log
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * The Android texture host of ADR 043: a [TextureRegistry.SurfaceProducer]
 * per texture, its window handed to libframe_texture under the texture id, so
 * a render worker locks and posts it by id through FFI.
 *
 * The channel has two methods, both on the platform thread: `create`
 * (`{width, height}`) answers the texture id, or null when the platform
 * cannot make one; `destroy` (the id) ends it. Everything here runs on the
 * platform thread; the library is what the workers share.
 */
class FrameTexturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var registry: TextureRegistry? = null
    private val textures = HashMap<Long, ProducedTexture>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        registry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        for (texture in textures.values) texture.release()
        textures.clear()
        registry = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                if (width == null || height == null || width <= 0 || height <= 0) {
                    result.error("bad_size", "width and height must be positive", null)
                    return
                }
                result.success(create(width, height))
            }
            "destroy" -> {
                val id = (call.arguments as? Number)?.toLong()
                if (id != null) textures.remove(id)?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** The new texture's id, or null when the platform refused one. */
    private fun create(width: Int, height: Int): Long? {
        val registry = registry ?: return null
        val producer = try {
            registry.createSurfaceProducer()
        } catch (error: RuntimeException) {
            Log.w(TAG, "createSurfaceProducer failed", error)
            return null
        }
        val texture = ProducedTexture(producer, width, height)
        val status = texture.attach()
        if (status != 0) {
            Log.w(TAG, "attaching a ${width}x$height texture failed: $status")
            texture.release()
            return null
        }
        textures[texture.id] = texture
        return texture.id
    }

    private companion object {
        const val CHANNEL = "dev.chatscrollview.frame_texture"
        const val TAG = "FrameTexture"
    }
}

/**
 * One texture: its producer, sized once, and its window in the table. A
 * producer that releases its surface (the app in the background, memory
 * pressure) says so through the callback; the window leaves the table, locks
 * answer null meanwhile, and the new surface is attached when it comes.
 */
private class ProducedTexture(
    private val producer: TextureRegistry.SurfaceProducer,
    private val width: Int,
    private val height: Int,
) : TextureRegistry.SurfaceProducer.Callback {
    val id: Long = producer.id()

    init {
        producer.setSize(width, height)
        producer.setCallback(this)
    }

    /** Hands the producer's current surface to the table; 0 when it took it. */
    fun attach(): Int {
        val surface: Surface = producer.surface ?: return FrameTextureNative.INVALID
        if (!surface.isValid) return FrameTextureNative.INVALID
        return FrameTextureNative.attach(id, surface, width, height)
    }

    override fun onSurfaceAvailable() {
        val status = attach()
        if (status != 0) Log.w("FrameTexture", "re-attaching texture $id failed: $status")
    }

    override fun onSurfaceCleanup() {
        FrameTextureNative.detach(id)
    }

    fun release() {
        producer.setCallback(null)
        FrameTextureNative.forget(id)
        producer.release()
    }
}

/** libframe_texture's JNI side (native/src/frame_texture_jni.c). */
internal object FrameTextureNative {
    /** `FRAME_TEXTURE_INVALID` of frame_texture.h. */
    const val INVALID = -1

    init {
        // The one copy of the library in the process: the Dart side opens the
        // same file by name, and the dynamic linker hands it this instance.
        System.loadLibrary("frame_texture")
    }

    @JvmStatic external fun attach(id: Long, surface: Surface, width: Int, height: Int): Int

    @JvmStatic external fun detach(id: Long)

    @JvmStatic external fun forget(id: Long)

    @JvmStatic external fun count(): Int
}
