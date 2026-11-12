/*
 * A fake ANativeWindow over plain memory, linked with the table into a host
 * library (built with FRAME_TEXTURE_TESTING) so the tests run the real table
 * without a device. Not part of any app build.
 *
 * A window is reference counted like the platform's: fake_window_new gives
 * one reference, as ANativeWindow_fromSurface does, and the last release
 * frees it; fake_window_live counts the windows not freed yet, so a test sees
 * a leaked or doubly released reference.
 */
#include <stdbool.h>
#include <stdlib.h>

#include "frame_texture.h"

#define FAKE_EXPORT __attribute__((visibility("default")))

struct ANativeWindow {
  int32_t references;
  int32_t width;
  int32_t height;
  int32_t format;
  /* Pixels a row beyond the width, as a platform's stride may have. */
  int32_t row_padding;
  bool locked;
  bool refuse_locks;
  /* A lock gives a buffer of this format instead of the geometry's. */
  int32_t forced_format;
  int32_t posts;
  uint8_t* pixels;
};

static int32_t live_windows = 0;

FAKE_EXPORT ANativeWindow* fake_window_new(int32_t row_padding) {
  ANativeWindow* window = calloc(1, sizeof(ANativeWindow));
  if (window == NULL) return NULL;
  window->references = 1;
  window->row_padding = row_padding;
  live_windows++;
  return window;
}

FAKE_EXPORT int32_t fake_window_live(void) { return live_windows; }

FAKE_EXPORT void fake_window_refuse_locks(ANativeWindow* window,
                                          int32_t refuse) {
  window->refuse_locks = refuse != 0;
}

FAKE_EXPORT void fake_window_force_format(ANativeWindow* window,
                                          int32_t format) {
  window->forced_format = format;
}

FAKE_EXPORT int32_t fake_window_posts(ANativeWindow* window) {
  return window->posts;
}

FAKE_EXPORT int32_t fake_window_is_locked(ANativeWindow* window) {
  return window->locked ? 1 : 0;
}

void ANativeWindow_acquire(ANativeWindow* window) { window->references++; }

void ANativeWindow_release(ANativeWindow* window) {
  if (--window->references > 0) return;
  free(window->pixels);
  free(window);
  live_windows--;
}

int32_t ANativeWindow_setBuffersGeometry(ANativeWindow* window, int32_t width,
                                         int32_t height, int32_t format) {
  if (width <= 0 || height <= 0) return -22;
  int32_t stride = width + window->row_padding;
  uint8_t* pixels = calloc((size_t)stride * (size_t)height, 4);
  if (pixels == NULL) return -12;
  free(window->pixels);
  window->pixels = pixels;
  window->width = width;
  window->height = height;
  window->format = format;
  return 0;
}

int32_t ANativeWindow_lock(ANativeWindow* window, ANativeWindow_Buffer* out,
                           ARect* dirty) {
  (void)dirty;
  if (window->refuse_locks || window->locked || window->pixels == NULL) {
    return -22;
  }
  window->locked = true;
  out->width = window->width;
  out->height = window->height;
  out->stride = window->width + window->row_padding;
  out->format =
      window->forced_format != 0 ? window->forced_format : window->format;
  out->bits = window->pixels;
  return 0;
}

int32_t ANativeWindow_unlockAndPost(ANativeWindow* window) {
  if (!window->locked) return -22;
  window->locked = false;
  window->posts++;
  return 0;
}
