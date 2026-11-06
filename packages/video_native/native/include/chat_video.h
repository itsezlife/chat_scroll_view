/* chat_video: flat C ABI over FFmpeg (libavformat, libavcodec, libswscale)
 * and libvpx. Hand-written; the only API of this library. No FFmpeg type
 * crosses it.
 *
 * Threading: a ChatVideo handle is used by one thread at a time. Handles are
 * independent, so different handles may run on different threads in
 * parallel. There is no global state besides FFmpeg's log level.
 *
 * Lifetime: a handle is freed exactly once; a second free is undefined. The
 * bytes passed to chat_video_open are copied; the caller keeps its buffer.
 *
 * Output: frames are premultiplied BGRA (byte order B, G, R, A), scaled to
 * the target size given at open (stretched, not letterboxed).
 *
 * Hostile input: every size, packet and frame count is capped (see the
 * CHAT_VIDEO_MAX_* constants), every FFmpeg return is checked, and the
 * container cannot make FFmpeg open any file or URL.
 */
#ifndef CHAT_VIDEO_H
#define CHAT_VIDEO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The library is built with hidden visibility; only this ABI is exported. */
#define CHAT_VIDEO_API __attribute__((visibility("default")))

/* Status codes. 0 is success, END_OF_STREAM is the one positive non-failure,
 * every failure is negative, and a code means one thing across calls. */
enum {
  CHAT_VIDEO_END_OF_STREAM = 1,     /* next: no more frames until a rewind */
  CHAT_VIDEO_OK = 0,
  CHAT_VIDEO_INVALID_ARGUMENT = -1, /* a null pointer */
  CHAT_VIDEO_TOO_LARGE = -2,        /* open: len over CHAT_VIDEO_MAX_INPUT_BYTES, checked before the bytes are looked at */
  CHAT_VIDEO_MALFORMED = -3,        /* open: not a container this build reads, or no readable stream info */
  CHAT_VIDEO_LIMIT_EXCEEDED = -4,   /* open: source dimensions over the cap; next: packet or frame budget spent */
  CHAT_VIDEO_UNSUPPORTED = -5,      /* open: no video stream, or its codec is not built in */
  CHAT_VIDEO_INTERNAL = -6,         /* allocation or FFmpeg internal failure: not the file's fault */
  CHAT_VIDEO_BAD_SIZE = -7,         /* open: target edge zero or over the cap; next: stride under the row width */
  CHAT_VIDEO_DECODE_FAILED = -8     /* next: the stream is damaged beyond the tolerated bad packets; rewind: cannot seek */
};

/* Caps. Changing one is an ABI-visible behaviour change. */
enum {
  CHAT_VIDEO_MAX_INPUT_BYTES = 10 * 1024 * 1024, /* tdesktop's 10 MiB gif/sticker gate */
  CHAT_VIDEO_MAX_SOURCE_EDGE = 3840,             /* Android's per-side cap */
  CHAT_VIDEO_MAX_SOURCE_PIXELS = 3840 * 2160,
  CHAT_VIDEO_MAX_TARGET_EDGE = 2048,
  CHAT_VIDEO_MAX_PACKETS_PER_PASS = 20000,       /* packets read between rewinds */
  CHAT_VIDEO_MAX_FRAMES_PER_PASS = 10000,        /* frames decoded between rewinds */
  CHAT_VIDEO_MAX_SKIPPED_PACKETS = 10            /* consecutive undecodable packets tolerated (tdesktop) */
};

enum { CHAT_VIDEO_ABI_VERSION = 1 };

typedef struct ChatVideo ChatVideo; /* opaque */

typedef struct {
  uint32_t width;       /* source size */
  uint32_t height;
  int64_t duration_ms;  /* -1 when the container declares none */
  float frame_rate;     /* 0 when unknown */
  uint32_t has_alpha;   /* 1 when the stream declares alpha (WebM alpha_mode, or an alpha pixel format; never for GIF) */
} ChatVideoInfo;

/* The load probe: returns CHAT_VIDEO_ABI_VERSION. */
CHAT_VIDEO_API uint32_t chat_video_abi_version(void);

/* Opens an in-memory file for frames of target_w x target_h. On success
 * returns 0, fills *out_handle; on failure returns a negative status and
 * sets *out_handle to NULL. VP9 is always decoded by libvpx-vp9 (the native
 * decoder drops alpha, FFmpeg Trac #8344). */
CHAT_VIDEO_API int32_t chat_video_open(const uint8_t *data, size_t len, uint32_t target_w,
                        uint32_t target_h, ChatVideo **out_handle);

/* Describes the open video. */
CHAT_VIDEO_API int32_t chat_video_info(const ChatVideo *handle, ChatVideoInfo *out_info);

/* Decodes the next frame into dst (top-left pixel of a target_w x target_h
 * slot, rows stride bytes apart, stride >= target_w * 4) and stores its
 * presentation time in *out_pts_ms. Returns 0, CHAT_VIDEO_END_OF_STREAM
 * (dst untouched) or a failure. */
CHAT_VIDEO_API int32_t chat_video_next(ChatVideo *handle, uint8_t *dst, size_t stride,
                        int64_t *out_pts_ms);

/* Seeks to the start and flushes the decoder, for looping. Resets the
 * per-pass budgets. */
CHAT_VIDEO_API int32_t chat_video_rewind(ChatVideo *handle);

/* Releases a handle. NULL is accepted. */
CHAT_VIDEO_API void chat_video_free(ChatVideo *handle);

#ifdef __cplusplus
}
#endif

#endif
