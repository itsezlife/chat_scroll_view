/*
 * frame_texture: the texture table the render workers write through
 * (ADR 043).
 *
 * The plugin's Kotlin side makes a SurfaceProducer per texture and hands its
 * window to this library under the texture id (frame_texture_attach); a render
 * worker then locks and posts by id through FFI. Both sides share one copy of
 * the library in the process: the plugin loads it with System.loadLibrary and
 * the Dart side opens the same file by name.
 *
 * Pixels are RGBA_8888, premultiplied: the window's geometry is set to that
 * format at attach.
 *
 * Thread safety: every function may be called from any thread. The table's
 * mutex is held only around a lookup, never across a platform call, so no
 * call waits on another caller's lock or post: a texture another caller is
 * locking, holds locked or is posting answers NULL at once. What the table
 * cannot shorten is ANativeWindow_lock itself, which dequeues a buffer and
 * waits only when the consumer holds every buffer of the queue (the producer's
 * ImageReader frees them as the engine draws; posting at most once per frame
 * keeps the queue from filling).
 */
#ifndef FRAME_TEXTURE_H
#define FRAME_TEXTURE_H

#include <stdint.h>

#ifdef __ANDROID__
#include <android/native_window.h>
#else
/* The subset of <android/native_window.h> the table uses, declared for a host
 * build that links a fake window (native/test/fake_window.c). */
typedef struct ANativeWindow ANativeWindow;
typedef struct ARect {
  int32_t left;
  int32_t top;
  int32_t right;
  int32_t bottom;
} ARect;
typedef struct ANativeWindow_Buffer {
  int32_t width;
  int32_t height;
  int32_t stride;
  int32_t format;
  void* bits;
  uint32_t reserved[6];
} ANativeWindow_Buffer;
enum { WINDOW_FORMAT_RGBA_8888 = 1 };
void ANativeWindow_acquire(ANativeWindow* window);
void ANativeWindow_release(ANativeWindow* window);
int32_t ANativeWindow_setBuffersGeometry(ANativeWindow* window, int32_t width,
                                         int32_t height, int32_t format);
int32_t ANativeWindow_lock(ANativeWindow* window, ANativeWindow_Buffer* out,
                           ARect* dirty);
int32_t ANativeWindow_unlockAndPost(ANativeWindow* window);
#endif

#define FRAME_TEXTURE_EXPORT __attribute__((visibility("default")))

/* The plugin's entry points are exported only from a test build, which calls
 * them in place of the JNI wrappers. */
#ifdef FRAME_TEXTURE_TESTING
#define FRAME_TEXTURE_PLUGIN FRAME_TEXTURE_EXPORT
#else
#define FRAME_TEXTURE_PLUGIN
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ---- The worker's ABI (FrameTextureEntryPoints in catalog_assets) ---- */

/* The first byte of texture `id`'s next buffer, with its row stride in bytes
 * written to *row_stride; NULL when the texture cannot be locked at once:
 * unknown, destroyed, without a surface now (the producer released it), being
 * locked or posted by another caller, already locked, or the platform refused
 * the lock (or gave a buffer of another size or format, which is posted back
 * unwritten). The buffer is at least the texture's size. */
FRAME_TEXTURE_EXPORT void* frame_texture_lock(int64_t id, int32_t* row_stride);

/* Publishes what was written since the lock of texture `id` and ends the
 * lock; does nothing for a texture that is not locked. */
FRAME_TEXTURE_EXPORT void frame_texture_post(int64_t id);

/* How many textures the table holds now: a probe that the plugin and the
 * Dart side share one copy of the library. */
FRAME_TEXTURE_EXPORT int32_t frame_texture_count(void);

/* ---- The plugin's side (called through JNI) ---- */

/* Status codes of frame_texture_attach. */
enum {
  FRAME_TEXTURE_OK = 0,
  /* No window, or a size that is not positive. */
  FRAME_TEXTURE_INVALID = -1,
  /* The id was destroyed (frame_texture_forget) and its last lock has not
   * been posted yet. */
  FRAME_TEXTURE_DESTROYED = -2,
  /* No memory for the table. */
  FRAME_TEXTURE_NO_MEMORY = -3,
  /* ANativeWindow_setBuffersGeometry refused the size or format. */
  FRAME_TEXTURE_GEOMETRY = -4,
};

/* Makes `window` the surface of texture `id`, at `width` x `height` RGBA_8888,
 * taking over the caller's reference to it (released here on failure).
 * Replaces the window the id had (a producer that made a new surface); a lock
 * in progress keeps the window it locked until its post. */
FRAME_TEXTURE_PLUGIN int32_t frame_texture_attach(int64_t id,
                                                  ANativeWindow* window,
                                                  int32_t width,
                                                  int32_t height);

/* Drops the surface of texture `id` (the producer is about to release it);
 * the texture stays and locks nothing until a window is attached again. */
FRAME_TEXTURE_PLUGIN void frame_texture_detach(int64_t id);

/* Ends texture `id` for good: it locks nothing from now on, and an attach
 * while a lock of it is still in progress is refused. A lock in progress ends
 * at its post. */
FRAME_TEXTURE_PLUGIN void frame_texture_forget(int64_t id);

#ifdef __cplusplus
}
#endif

#endif /* FRAME_TEXTURE_H */
