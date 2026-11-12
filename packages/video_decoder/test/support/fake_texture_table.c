/*
 * A texture host's C entry points over plain memory, for tests: the lock and
 * post of FrameTextureEntryPoints (catalog_assets), plus what a test needs to
 * make textures and look at them. The plugin's real table
 * (packages/frame_texture) is not a dependency of a decoder, so the decoders'
 * tests compile this one instead (test/support/texture_table.dart).
 *
 * Calls come from the test's isolate and from a render isolate, never at the
 * same time on one texture, so there is no lock.
 */
#include <stdint.h>
#include <stdlib.h>

#define EXPORT __attribute__((visibility("default")))
#define MAX_TEXTURES 64

typedef struct {
  int32_t width;
  int32_t height;
  int32_t stride;
  int32_t locked;
  int32_t refuse;
  int32_t posts;
  uint8_t* pixels;
} texture;

static texture textures[MAX_TEXTURES + 1];
static int64_t next_id = 1;

static texture* find(int64_t id) {
  if (id <= 0 || id >= next_id || id > MAX_TEXTURES) return NULL;
  texture* t = &textures[id];
  return t->pixels == NULL ? NULL : t;
}

/* A new texture of width x height, rows padded by `padding` pixels, filled
 * with `fill`; its id, or 0 when the table is full. */
EXPORT int64_t fake_texture_new(int32_t width, int32_t height,
                                int32_t padding, int32_t fill) {
  if (next_id > MAX_TEXTURES) return 0;
  int64_t id = next_id++;
  texture* t = &textures[id];
  t->width = width;
  t->height = height;
  t->stride = (width + padding) * 4;
  t->locked = 0;
  t->refuse = 0;
  t->posts = 0;
  t->pixels = malloc((size_t)t->stride * (size_t)height);
  for (int64_t i = 0; i < (int64_t)t->stride * height; i++) {
    t->pixels[i] = (uint8_t)fill;
  }
  return id;
}

EXPORT void* fake_texture_lock(int64_t id, int32_t* row_stride) {
  texture* t = find(id);
  if (t == NULL || t->locked || t->refuse) return NULL;
  t->locked = 1;
  *row_stride = t->stride;
  return t->pixels;
}

EXPORT void fake_texture_post(int64_t id) {
  texture* t = find(id);
  if (t == NULL || !t->locked) return;
  t->locked = 0;
  t->posts++;
}

EXPORT uint8_t* fake_texture_pixels(int64_t id) {
  texture* t = find(id);
  return t == NULL ? NULL : t->pixels;
}

EXPORT int32_t fake_texture_stride(int64_t id) {
  texture* t = find(id);
  return t == NULL ? 0 : t->stride;
}

EXPORT int32_t fake_texture_posts(int64_t id) {
  texture* t = find(id);
  return t == NULL ? -1 : t->posts;
}

EXPORT int32_t fake_texture_is_locked(int64_t id) {
  texture* t = find(id);
  return t == NULL ? 0 : t->locked;
}

EXPORT void fake_texture_refuse(int64_t id, int32_t refuse) {
  texture* t = find(id);
  if (t != NULL) t->refuse = refuse;
}
