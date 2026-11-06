/* chat_video: see include/chat_video.h for the contract. */
#include "chat_video.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

/* --- Handle ----------------------------------------------------------- */

typedef enum {
  STATE_RUNNING,
  STATE_DRAINING, /* the flush packet is sent; frames still come out */
  STATE_DONE,     /* end of stream reached */
  STATE_SPENT     /* a failure; only a rewind revives the handle */
} State;

struct ChatVideo {
  /* The file, copied: AVIO reads from it through the cursor. */
  uint8_t *data;
  size_t size;
  size_t pos;

  AVIOContext *avio;
  AVFormatContext *fmt;
  AVCodecContext *dec;
  AVPacket *pkt;
  AVFrame *frame;
  struct SwsContext *sws;
  int stream;

  uint32_t target_w, target_h;
  ChatVideoInfo info;

  State state;
  int64_t packets; /* read since the last rewind */
  int64_t frames;  /* decoded since the last rewind */
  int skipped;     /* consecutive undecodable packets */
  int64_t last_pts_ms; /* -1 before the first frame of a pass */
};

/* --- In-memory AVIO --------------------------------------------------- */

static int read_memory(void *opaque, uint8_t *buf, int buf_size) {
  ChatVideo *h = opaque;
  size_t left = h->size - h->pos;
  if (left == 0) return AVERROR_EOF;
  size_t n = (size_t)buf_size < left ? (size_t)buf_size : left;
  memcpy(buf, h->data + h->pos, n);
  h->pos += n;
  return (int)n;
}

static int64_t seek_memory(void *opaque, int64_t offset, int whence) {
  ChatVideo *h = opaque;
  if (whence & AVSEEK_SIZE) return (int64_t)h->size;
  int64_t base;
  switch (whence & ~AVSEEK_FORCE) {
    case SEEK_SET: base = 0; break;
    case SEEK_CUR: base = (int64_t)h->pos; break;
    case SEEK_END: base = (int64_t)h->size; break;
    default: return AVERROR(EINVAL);
  }
  int64_t at = base + offset;
  if (at < 0 || at > (int64_t)h->size) return AVERROR(EINVAL);
  h->pos = (size_t)at;
  return at;
}

/* --- Lifetime ---------------------------------------------------------- */

void chat_video_free(ChatVideo *h) {
  if (!h) return;
  sws_freeContext(h->sws);
  av_frame_free(&h->frame);
  av_packet_free(&h->pkt);
  avcodec_free_context(&h->dec);
  /* Closes the input (with a custom pb it does not free the pb itself). */
  avformat_close_input(&h->fmt);
  if (h->avio) {
    av_freep(&h->avio->buffer);
    avio_context_free(&h->avio);
  }
  free(h->data);
  free(h);
}

static void quiet_ffmpeg_once(void) {
  static atomic_int done;
  if (atomic_exchange(&done, 1) == 0) av_log_set_level(AV_LOG_QUIET);
}

static int has_alpha_format(int format) {
  const AVPixFmtDescriptor *d = format >= 0 ? av_pix_fmt_desc_get(format) : NULL;
  return d && (d->flags & AV_PIX_FMT_FLAG_ALPHA);
}

static int32_t open_decoder(ChatVideo *h) {
  AVDictionary *opts = NULL;
  /* The container must not make FFmpeg open anything but our memory. */
  av_dict_set(&opts, "protocol_whitelist", "", 0);

  h->fmt = avformat_alloc_context();
  if (!h->fmt) return CHAT_VIDEO_INTERNAL;
  h->fmt->pb = h->avio;
  h->fmt->flags |= AVFMT_FLAG_CUSTOM_IO;
  int r = avformat_open_input(&h->fmt, NULL, NULL, &opts);
  av_dict_free(&opts);
  if (r < 0) return CHAT_VIDEO_MALFORMED; /* h->fmt is freed and NULL */
  if (avformat_find_stream_info(h->fmt, NULL) < 0) return CHAT_VIDEO_MALFORMED;

  h->stream = av_find_best_stream(h->fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
  if (h->stream < 0) return CHAT_VIDEO_UNSUPPORTED;
  AVStream *st = h->fmt->streams[h->stream];
  AVCodecParameters *par = st->codecpar;

  if (par->width <= 0 || par->height <= 0) return CHAT_VIDEO_MALFORMED;
  if (par->width > CHAT_VIDEO_MAX_SOURCE_EDGE ||
      par->height > CHAT_VIDEO_MAX_SOURCE_EDGE ||
      (int64_t)par->width * par->height > CHAT_VIDEO_MAX_SOURCE_PIXELS)
    return CHAT_VIDEO_LIMIT_EXCEEDED;

  const AVCodec *codec = NULL;
  if (par->codec_id == AV_CODEC_ID_VP9) {
    /* Forced: FFmpeg's own vp9 decoder drops the alpha plane (Trac #8344),
     * as tdesktop's ffmpeg_utility.cpp does the same. */
    codec = avcodec_find_decoder_by_name("libvpx-vp9");
  } else {
    codec = avcodec_find_decoder(par->codec_id);
  }
  if (!codec) return CHAT_VIDEO_UNSUPPORTED;

  h->dec = avcodec_alloc_context3(codec);
  if (!h->dec) return CHAT_VIDEO_INTERNAL;
  if (avcodec_parameters_to_context(h->dec, par) < 0) return CHAT_VIDEO_INTERNAL;
  /* The decoder refuses frames over the area cap, with slack for padding. */
  h->dec->max_pixels = CHAT_VIDEO_MAX_SOURCE_PIXELS + CHAT_VIDEO_MAX_SOURCE_PIXELS / 32 + 64 * 1024;
  if (avcodec_open2(h->dec, codec, NULL) < 0) return CHAT_VIDEO_UNSUPPORTED;

  h->pkt = av_packet_alloc();
  h->frame = av_frame_alloc();
  if (!h->pkt || !h->frame) return CHAT_VIDEO_INTERNAL;

  AVRational rate = av_guess_frame_rate(h->fmt, st, NULL);
  const AVDictionaryEntry *alpha_mode = av_dict_get(st->metadata, "alpha_mode", NULL, 0);
  h->info.width = (uint32_t)par->width;
  h->info.height = (uint32_t)par->height;
  h->info.duration_ms = h->fmt->duration != AV_NOPTS_VALUE ? h->fmt->duration / 1000 : -1;
  h->info.frame_rate = rate.den > 0 && rate.num > 0 ? (float)av_q2d(rate) : 0.0f;
  /* GIF always decodes to BGRA whatever the file holds, so its pixel format
   * says nothing; every other codec's declared format does. */
  h->info.has_alpha = (alpha_mode && strcmp(alpha_mode->value, "1") == 0) ||
                      (par->codec_id != AV_CODEC_ID_GIF && has_alpha_format(par->format));
  return CHAT_VIDEO_OK;
}

int32_t chat_video_open(const uint8_t *data, size_t len, uint32_t target_w,
                        uint32_t target_h, ChatVideo **out_handle) {
  if (!out_handle) return CHAT_VIDEO_INVALID_ARGUMENT;
  *out_handle = NULL;
  if (!data) return CHAT_VIDEO_INVALID_ARGUMENT;
  /* Before the bytes are looked at. */
  if (len > CHAT_VIDEO_MAX_INPUT_BYTES) return CHAT_VIDEO_TOO_LARGE;
  if (len == 0) return CHAT_VIDEO_MALFORMED;
  if (target_w == 0 || target_h == 0 || target_w > CHAT_VIDEO_MAX_TARGET_EDGE ||
      target_h > CHAT_VIDEO_MAX_TARGET_EDGE)
    return CHAT_VIDEO_BAD_SIZE;
  quiet_ffmpeg_once();

  ChatVideo *h = calloc(1, sizeof *h);
  if (!h) return CHAT_VIDEO_INTERNAL;
  int32_t status = CHAT_VIDEO_INTERNAL;
  h->data = malloc(len);
  if (!h->data) goto fail;
  memcpy(h->data, data, len);
  h->size = len;
  h->target_w = target_w;
  h->target_h = target_h;
  h->last_pts_ms = -1;

  const int io_size = 32 * 1024;
  uint8_t *io_buffer = av_malloc(io_size);
  if (!io_buffer) goto fail;
  h->avio = avio_alloc_context(io_buffer, io_size, 0, h, read_memory, NULL, seek_memory);
  if (!h->avio) {
    av_free(io_buffer);
    goto fail;
  }

  status = open_decoder(h);
  if (status != CHAT_VIDEO_OK) goto fail;
  *out_handle = h;
  return CHAT_VIDEO_OK;

fail:
  chat_video_free(h);
  return status;
}

int32_t chat_video_info(const ChatVideo *h, ChatVideoInfo *out_info) {
  if (!h || !out_info) return CHAT_VIDEO_INVALID_ARGUMENT;
  *out_info = h->info;
  return CHAT_VIDEO_OK;
}

/* --- Decoding ---------------------------------------------------------- */

/* c = c * a / 255, rounded, on straight BGRA rows. */
static void premultiply(uint8_t *dst, size_t stride, uint32_t w, uint32_t h) {
  for (uint32_t y = 0; y < h; y++) {
    uint8_t *p = dst + y * stride;
    for (uint32_t x = 0; x < w; x++, p += 4) {
      uint32_t a = p[3];
      if (a == 255) continue;
      p[0] = (uint8_t)((p[0] * a + 127) / 255);
      p[1] = (uint8_t)((p[1] * a + 127) / 255);
      p[2] = (uint8_t)((p[2] * a + 127) / 255);
    }
  }
}

/* Scales the decoded frame into dst as BGRA. */
static int32_t convert(ChatVideo *h, uint8_t *dst, size_t stride) {
  const AVFrame *f = h->frame;
  if (f->width <= 0 || f->height <= 0 || f->width > CHAT_VIDEO_MAX_SOURCE_EDGE ||
      f->height > CHAT_VIDEO_MAX_SOURCE_EDGE ||
      (int64_t)f->width * f->height > CHAT_VIDEO_MAX_SOURCE_PIXELS)
    return CHAT_VIDEO_LIMIT_EXCEEDED;
  h->sws = sws_getCachedContext(h->sws, f->width, f->height, f->format, (int)h->target_w,
                                (int)h->target_h, AV_PIX_FMT_BGRA, SWS_BILINEAR, NULL, NULL, NULL);
  if (!h->sws) return CHAT_VIDEO_DECODE_FAILED; /* a format swscale cannot read */
  uint8_t *planes[4] = {dst, NULL, NULL, NULL};
  int strides[4] = {(int)stride, 0, 0, 0};
  if (sws_scale(h->sws, (const uint8_t *const *)f->data, f->linesize, 0, f->height, planes,
                strides) != (int)h->target_h)
    return CHAT_VIDEO_DECODE_FAILED;
  if (has_alpha_format(f->format)) premultiply(dst, stride, h->target_w, h->target_h);
  return CHAT_VIDEO_OK;
}

static int64_t frame_pts_ms(ChatVideo *h) {
  int64_t ts = h->frame->best_effort_timestamp;
  AVStream *st = h->fmt->streams[h->stream];
  if (ts == AV_NOPTS_VALUE) {
    /* Without a timestamp, one frame period after the last one. */
    int64_t period = h->info.frame_rate > 0 ? (int64_t)(1000.0f / h->info.frame_rate) : 40;
    return h->last_pts_ms < 0 ? 0 : h->last_pts_ms + period;
  }
  if (st->start_time != AV_NOPTS_VALUE) ts -= st->start_time;
  int64_t ms = av_rescale_q(ts, st->time_base, (AVRational){1, 1000});
  return ms < 0 ? 0 : ms;
}

static int32_t spend(ChatVideo *h, int32_t status) {
  h->state = STATE_SPENT;
  return status;
}

int32_t chat_video_next(ChatVideo *h, uint8_t *dst, size_t stride, int64_t *out_pts_ms) {
  if (!h || !dst || !out_pts_ms) return CHAT_VIDEO_INVALID_ARGUMENT;
  if (stride < (size_t)h->target_w * 4) return CHAT_VIDEO_BAD_SIZE;
  if (h->state == STATE_DONE) return CHAT_VIDEO_END_OF_STREAM;
  if (h->state == STATE_SPENT) return CHAT_VIDEO_DECODE_FAILED;

  for (;;) {
    int r = avcodec_receive_frame(h->dec, h->frame);
    if (r == 0) {
      if (h->frames >= CHAT_VIDEO_MAX_FRAMES_PER_PASS) {
        av_frame_unref(h->frame);
        return spend(h, CHAT_VIDEO_LIMIT_EXCEEDED);
      }
      h->frames++;
      int32_t status = convert(h, dst, stride);
      if (status == CHAT_VIDEO_OK) {
        *out_pts_ms = h->last_pts_ms = frame_pts_ms(h);
        h->skipped = 0;
      }
      av_frame_unref(h->frame);
      return status == CHAT_VIDEO_OK ? CHAT_VIDEO_OK : spend(h, status);
    }
    if (r == AVERROR_EOF) {
      h->state = STATE_DONE;
      return CHAT_VIDEO_END_OF_STREAM;
    }
    if (r != AVERROR(EAGAIN)) return spend(h, CHAT_VIDEO_DECODE_FAILED);
    /* EAGAIN after the flush packet cannot happen; do not wait for it. */
    if (h->state == STATE_DRAINING) {
      h->state = STATE_DONE;
      return CHAT_VIDEO_END_OF_STREAM;
    }

    /* The decoder wants a packet. */
    if (h->packets >= CHAT_VIDEO_MAX_PACKETS_PER_PASS) return spend(h, CHAT_VIDEO_LIMIT_EXCEEDED);
    r = av_read_frame(h->fmt, h->pkt);
    if (r == AVERROR_EOF) {
      h->state = STATE_DRAINING;
      if (avcodec_send_packet(h->dec, NULL) < 0) return spend(h, CHAT_VIDEO_DECODE_FAILED);
      continue;
    }
    if (r < 0) return spend(h, CHAT_VIDEO_DECODE_FAILED);
    h->packets++;
    if (h->pkt->stream_index != h->stream) {
      av_packet_unref(h->pkt);
      continue;
    }
    r = avcodec_send_packet(h->dec, h->pkt);
    av_packet_unref(h->pkt);
    if (r == AVERROR_INVALIDDATA && ++h->skipped <= CHAT_VIDEO_MAX_SKIPPED_PACKETS) continue;
    if (r < 0 && r != AVERROR(EAGAIN)) return spend(h, CHAT_VIDEO_DECODE_FAILED);
  }
}

int32_t chat_video_rewind(ChatVideo *h) {
  if (!h) return CHAT_VIDEO_INVALID_ARGUMENT;
  AVStream *st = h->fmt->streams[h->stream];
  int64_t start = st->start_time != AV_NOPTS_VALUE ? st->start_time : 0;
  /* tdesktop's fallback chain, shortened: by timestamp, by a seek window,
   * then by byte offset. */
  int r = av_seek_frame(h->fmt, h->stream, start, AVSEEK_FLAG_BACKWARD);
  if (r < 0) r = avformat_seek_file(h->fmt, h->stream, INT64_MIN, start, start, 0);
  if (r < 0) r = av_seek_frame(h->fmt, h->stream, 0, AVSEEK_FLAG_BYTE);
  if (r < 0) return spend(h, CHAT_VIDEO_DECODE_FAILED);
  avcodec_flush_buffers(h->dec);
  h->state = STATE_RUNNING;
  h->packets = 0;
  h->frames = 0;
  h->skipped = 0;
  h->last_pts_ms = -1;
  return CHAT_VIDEO_OK;
}

uint32_t chat_video_abi_version(void) { return CHAT_VIDEO_ABI_VERSION; }
