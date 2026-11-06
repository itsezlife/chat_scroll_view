/* chat_lottie: C ABI over tlottie. Hand-written; keep in step with src/lib.rs.
 *
 * Threading: a ChatLottie handle is used by one thread at a time. Handles are
 * independent, so rendering different handles on different threads in
 * parallel is fine.
 *
 * Lifetime: a handle is freed exactly once; a second free is undefined.
 *
 * Panics never cross this boundary: a panic inside a call becomes the
 * "internal" status (-6), which is a bug in this library and never the
 * file's fault.
 */
#ifndef CHAT_LOTTIE_H
#define CHAT_LOTTIE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Status codes. 0 is success, every failure is negative, and a code means
 * one thing across load and render. */
enum {
  CHAT_LOTTIE_OK = 0,
  CHAT_LOTTIE_INVALID_ARGUMENT = -1, /* a null pointer or a bad enum */
  CHAT_LOTTIE_TOO_LARGE = -2,        /* load: encoded or inflated input over its cap; compress: dst_cap too small */
  CHAT_LOTTIE_MALFORMED = -3,        /* load: not gzip, not JSON, parse error; decompress: corrupt or wrong-size stream */
  CHAT_LOTTIE_LIMIT_EXCEEDED = -4,   /* load: a tlottie Limits budget tripped */
  CHAT_LOTTIE_UNSUPPORTED = -5,      /* load: nothing to draw, or non-finite frame rate */
  CHAT_LOTTIE_INTERNAL = -6,         /* a panic caught at the boundary: a bug, never the file's fault */
  CHAT_LOTTIE_BAD_SIZE = -7,         /* render, lz4: zero edge, edge over 512, stride under the row width, byte-size overflow */
  CHAT_LOTTIE_RENDER_FAILED = -8     /* render: the frame could not be drawn */
};

/* Features of the file that tlottie does not render. Informational: a file
 * using them still loads. */
enum {
  CHAT_LOTTIE_FEATURE_EFFECTS = 1,
  CHAT_LOTTIE_FEATURE_EXPRESSIONS = 2,
  CHAT_LOTTIE_FEATURE_IMAGES = 4,
  CHAT_LOTTIE_FEATURE_TEXT = 8
};

typedef struct ChatLottie ChatLottie; /* opaque */

typedef struct {
  uint32_t width;
  uint32_t height;
  uint32_t frame_count;
  float frame_rate;
  uint32_t features; /* CHAT_LOTTIE_FEATURE_* bitmask */
} ChatLottieInfo;

typedef struct {
  ChatLottie *handle;
  float frame;
  uint32_t width;  /* 1..512 */
  uint32_t height; /* 1..512 */
  uint8_t *target; /* top-left pixel of the slot inside page memory */
  size_t stride_bytes; /* distance between rows; at least width * 4 */
} ChatLottieJob;

/* The load probe: returns 1. */
uint32_t chat_lottie_abi_version(void);

/* Loads a Lottie animation. Data starting with 1f 8b is gunzipped (TGS),
 * anything else is taken as JSON. Encoded input is capped at 4 MiB and the
 * inflated output at 8 MiB. On success returns 0, fills out_info and
 * out_handle; on failure returns a negative status and sets *out_handle to
 * NULL. */
int32_t chat_lottie_load(const uint8_t *data, size_t len, ChatLottieInfo *out_info,
                         ChatLottie **out_handle);

/* Releases a handle. NULL is accepted; any other handle is freed exactly
 * once (a second free is undefined). */
void chat_lottie_free(ChatLottie *handle);

/* Renders every job as premultiplied RGBA, bytes [R, G, B, A], writing only
 * the first width * 4 bytes of each of height rows at target. statuses[i] is
 * 0 or a negative code (-1 null handle or target, -6 internal, -7 bad size,
 * -8 render failed); one bad job never stops the others. Returns 0 when the batch ran, -1 when jobs or statuses is NULL
 * with count > 0. */
int32_t chat_lottie_render_batch(const ChatLottieJob *jobs, size_t count, int32_t *statuses);

/* Frame codec: lz4 over a region of page memory, `height` rows of width * 4
 * bytes, rows stride_bytes apart. Edges are 1..512 and stride_bytes is at
 * least width * 4. A region is packed as one lz4 block of its tight pixels,
 * so the packed form does not depend on the stride. Nothing outside the
 * described bytes is read or written. */

/* The most bytes a compressed width x height region can take (the lz4 worst
 * case for width * height * 4), or 0 for a size the codec does not accept. */
size_t chat_lottie_lz4_bound(uint32_t width, uint32_t height);

/* Compresses the region at target into dst and stores the packed length in
 * *out_len (left untouched on failure). Returns 0, -1 for a NULL pointer, -7
 * for a bad size or stride, -2 when the packed form is longer than dst_cap
 * (a dst_cap of chat_lottie_lz4_bound always suffices). */
int32_t chat_lottie_compress_region(const uint8_t *target, size_t stride_bytes, uint32_t width,
                                    uint32_t height, uint8_t *dst, size_t dst_cap, size_t *out_len);

/* Decompresses src into the region at target. The stream must unpack to
 * exactly width * height * 4 bytes. Returns 0, -1 for a NULL pointer, -7 for
 * a bad size or stride, -3 for a corrupt or wrong-size stream; on any
 * failure the region is left untouched. Never reads or writes out of
 * bounds. */
int32_t chat_lottie_decompress_region(const uint8_t *src, size_t src_len, uint8_t *target,
                                      size_t stride_bytes, uint32_t width, uint32_t height);

/* Web only (compiled for wasm32, absent from native libraries): JavaScript
 * cannot write into the module's memory without owning a region of it, so the
 * module hands out its own. chat_lottie_alloc returns len bytes (4-aligned,
 * uninitialised), or NULL when len is 0 or over 256 MiB; chat_lottie_dealloc
 * takes the pointer back with the same len (NULL is accepted). */
uint8_t *chat_lottie_alloc(size_t len);
void chat_lottie_dealloc(uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* CHAT_LOTTIE_H */
