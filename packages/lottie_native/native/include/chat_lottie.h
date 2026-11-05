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
  CHAT_LOTTIE_TOO_LARGE = -2,        /* load: encoded or inflated input over its cap */
  CHAT_LOTTIE_MALFORMED = -3,        /* load: not gzip, not JSON, parse error */
  CHAT_LOTTIE_LIMIT_EXCEEDED = -4,   /* load: a tlottie Limits budget tripped */
  CHAT_LOTTIE_UNSUPPORTED = -5,      /* load: nothing to draw, or non-finite frame rate */
  CHAT_LOTTIE_INTERNAL = -6,         /* a panic caught at the boundary: a bug, never the file's fault */
  CHAT_LOTTIE_BAD_SIZE = -7,         /* render: zero edge, edge over 512, stride under the row width, byte-size overflow */
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

#ifdef __cplusplus
}
#endif

#endif /* CHAT_LOTTIE_H */
