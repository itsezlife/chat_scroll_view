/*
 * The texture table: windows by texture id, and the lock state of each.
 * See frame_texture.h for the contract.
 *
 * A texture is idle, busy (a caller is between taking it and the platform's
 * lock or post returning) or locked (a buffer is out to a writer). Only an
 * idle texture with a window locks, so a second caller is answered NULL at
 * once instead of waiting. The table's mutex guards lookups only; the
 * platform calls run outside it, on a window reference the caller took, so a
 * detach or a forget during a lock never frees the window under the writer.
 */
#include "frame_texture.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef enum { STATE_IDLE, STATE_BUSY, STATE_LOCKED } texture_state;

typedef struct {
  int64_t id;
  /* The table's reference to the surface, or NULL while there is none. */
  ANativeWindow* window;
  /* The reference the lock in progress holds, or NULL when idle. */
  ANativeWindow* locked;
  int32_t width;
  int32_t height;
  texture_state state;
  /* Destroyed while busy or locked: removed when the lock ends. */
  bool forgotten;
} texture;

static pthread_mutex_t table_mutex = PTHREAD_MUTEX_INITIALIZER;
static texture* table = NULL;
static int32_t table_length = 0;
static int32_t table_capacity = 0;

/* With table_mutex held. */
static texture* find(int64_t id) {
  for (int32_t i = 0; i < table_length; i++) {
    if (table[i].id == id) return &table[i];
  }
  return NULL;
}

/* With table_mutex held; `entry` points into the table. */
static void remove_entry(texture* entry) {
  int32_t index = (int32_t)(entry - table);
  table[index] = table[table_length - 1];
  table_length--;
}

/* With table_mutex held: the entry of `id`, made when absent; NULL when there
 * is no memory for it. */
static texture* find_or_add(int64_t id) {
  texture* entry = find(id);
  if (entry != NULL) return entry;
  if (table_length == table_capacity) {
    int32_t capacity = table_capacity == 0 ? 32 : table_capacity * 2;
    texture* grown = realloc(table, (size_t)capacity * sizeof(texture));
    if (grown == NULL) return NULL;
    table = grown;
    table_capacity = capacity;
  }
  entry = &table[table_length++];
  memset(entry, 0, sizeof(texture));
  entry->id = id;
  return entry;
}

/* Ends the lock of `id` that holds `window`, and drops that reference. */
static void end_lock(int64_t id, ANativeWindow* window) {
  pthread_mutex_lock(&table_mutex);
  texture* entry = find(id);
  if (entry != NULL && entry->locked == window) {
    entry->locked = NULL;
    entry->state = STATE_IDLE;
    if (entry->forgotten) remove_entry(entry);
  }
  pthread_mutex_unlock(&table_mutex);
  ANativeWindow_release(window);
}

void* frame_texture_lock(int64_t id, int32_t* row_stride) {
  if (row_stride == NULL) return NULL;
  pthread_mutex_lock(&table_mutex);
  texture* entry = find(id);
  if (entry == NULL || entry->forgotten || entry->state != STATE_IDLE ||
      entry->window == NULL) {
    pthread_mutex_unlock(&table_mutex);
    return NULL;
  }
  ANativeWindow* window = entry->window;
  int32_t width = entry->width;
  int32_t height = entry->height;
  ANativeWindow_acquire(window);
  entry->locked = window;
  entry->state = STATE_BUSY;
  pthread_mutex_unlock(&table_mutex);

  ANativeWindow_Buffer buffer;
  memset(&buffer, 0, sizeof(buffer));
  if (ANativeWindow_lock(window, &buffer, NULL) != 0) {
    end_lock(id, window);
    return NULL;
  }
  if (buffer.bits == NULL || buffer.format != WINDOW_FORMAT_RGBA_8888 ||
      buffer.width < width || buffer.height < height ||
      buffer.stride < buffer.width) {
    /* Not the buffer the geometry asked for: writing `width` pixels a row
     * into it could run past its end. The window has no unlock without a
     * post, so the buffer goes back unwritten. */
    ANativeWindow_unlockAndPost(window);
    end_lock(id, window);
    return NULL;
  }

  pthread_mutex_lock(&table_mutex);
  entry = find(id);
  /* The entry stays while it is busy (a forget only marks it). */
  if (entry != NULL) entry->state = STATE_LOCKED;
  pthread_mutex_unlock(&table_mutex);
  *row_stride = buffer.stride * 4;
  return buffer.bits;
}

void frame_texture_post(int64_t id) {
  pthread_mutex_lock(&table_mutex);
  texture* entry = find(id);
  if (entry == NULL || entry->state != STATE_LOCKED) {
    pthread_mutex_unlock(&table_mutex);
    return;
  }
  ANativeWindow* window = entry->locked;
  entry->state = STATE_BUSY;
  pthread_mutex_unlock(&table_mutex);

  /* Fails harmlessly on a surface the producer has released meanwhile. */
  ANativeWindow_unlockAndPost(window);
  end_lock(id, window);
}

int32_t frame_texture_count(void) {
  pthread_mutex_lock(&table_mutex);
  int32_t count = 0;
  for (int32_t i = 0; i < table_length; i++) {
    if (!table[i].forgotten) count++;
  }
  pthread_mutex_unlock(&table_mutex);
  return count;
}

int32_t frame_texture_attach(int64_t id, ANativeWindow* window, int32_t width,
                             int32_t height) {
  if (window == NULL) return FRAME_TEXTURE_INVALID;
  if (width <= 0 || height <= 0) {
    ANativeWindow_release(window);
    return FRAME_TEXTURE_INVALID;
  }
  if (ANativeWindow_setBuffersGeometry(window, width, height,
                                       WINDOW_FORMAT_RGBA_8888) != 0) {
    ANativeWindow_release(window);
    return FRAME_TEXTURE_GEOMETRY;
  }
  pthread_mutex_lock(&table_mutex);
  texture* entry = find(id);
  if (entry != NULL && entry->forgotten) {
    pthread_mutex_unlock(&table_mutex);
    ANativeWindow_release(window);
    return FRAME_TEXTURE_DESTROYED;
  }
  entry = find_or_add(id);
  if (entry == NULL) {
    pthread_mutex_unlock(&table_mutex);
    ANativeWindow_release(window);
    return FRAME_TEXTURE_NO_MEMORY;
  }
  ANativeWindow* old = entry->window;
  entry->window = window;
  entry->width = width;
  entry->height = height;
  pthread_mutex_unlock(&table_mutex);
  if (old != NULL) ANativeWindow_release(old);
  return FRAME_TEXTURE_OK;
}

void frame_texture_detach(int64_t id) {
  pthread_mutex_lock(&table_mutex);
  texture* entry = find(id);
  ANativeWindow* old = NULL;
  if (entry != NULL) {
    old = entry->window;
    entry->window = NULL;
  }
  pthread_mutex_unlock(&table_mutex);
  if (old != NULL) ANativeWindow_release(old);
}

void frame_texture_forget(int64_t id) {
  pthread_mutex_lock(&table_mutex);
  texture* entry = find(id);
  ANativeWindow* old = NULL;
  if (entry != NULL) {
    old = entry->window;
    entry->window = NULL;
    if (entry->state == STATE_IDLE) {
      remove_entry(entry);
    } else {
      entry->forgotten = true;
    }
  }
  pthread_mutex_unlock(&table_mutex);
  if (old != NULL) ANativeWindow_release(old);
}
