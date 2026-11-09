// Build-proof probe, not a product API. Opens a file, decodes every video
// frame, scales to BGRA and prints facts as key=value lines.
//
//   probe <file> <width> <height> [--native]
//
// By default VP9 is decoded by libvpx-vp9 (the native vp9 decoder drops the
// alpha plane, FFmpeg Trac #8344). --native keeps FFmpeg's own pick, to show
// that finding once.
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: probe <file> <width> <height> [--native]\n");
    return 2;
  }
  const int dw = atoi(argv[2]), dh = atoi(argv[3]);
  const int native = argc > 4 && strcmp(argv[4], "--native") == 0;

  AVFormatContext* fmt = NULL;
  if (avformat_open_input(&fmt, argv[1], NULL, NULL) < 0) return 3;
  if (avformat_find_stream_info(fmt, NULL) < 0) return 3;
  int vi = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
  if (vi < 0) return 4;
  AVStream* st = fmt->streams[vi];

  const AVCodec* codec = avcodec_find_decoder(st->codecpar->codec_id);
  if (!native && st->codecpar->codec_id == AV_CODEC_ID_VP9) {
    // Same forced decoder as chat_video.c: libvpx-vp9 keeps the alpha plane.
    const AVCodec* forced = avcodec_find_decoder_by_name("libvpx-vp9");
    if (forced) codec = forced;
  }
  if (!codec) return 5;
  AVCodecContext* ctx = avcodec_alloc_context3(codec);
  avcodec_parameters_to_context(ctx, st->codecpar);
  if (avcodec_open2(ctx, codec, NULL) < 0) return 5;

  uint8_t* dst = malloc((size_t)dw * dh * 4);
  int dst_stride = dw * 4;
  struct SwsContext* sws = NULL;
  AVPacket* pkt = av_packet_alloc();
  AVFrame* fr = av_frame_alloc();
  long frames = 0;
  int alpha = 0, a_min = -1, a_max = -1, src_fmt = -1;
  uint64_t hash = 1469598103934665603ULL;

  int eof = 0;
  while (!eof) {
    int r = av_read_frame(fmt, pkt);
    if (r < 0) {
      eof = 1;
      avcodec_send_packet(ctx, NULL);
    } else if (pkt->stream_index == vi) {
      avcodec_send_packet(ctx, pkt);
    }
    if (r >= 0) av_packet_unref(pkt);
    while (avcodec_receive_frame(ctx, fr) == 0) {
      sws = sws_getCachedContext(sws, fr->width, fr->height, fr->format, dw, dh,
                                 AV_PIX_FMT_BGRA, SWS_BILINEAR, NULL, NULL, NULL);
      uint8_t* planes[4] = {dst, NULL, NULL, NULL};
      sws_scale(sws, (const uint8_t* const*)fr->data, fr->linesize, 0,
                fr->height, planes, &dst_stride);
      src_fmt = fr->format;
      if (fr->format == AV_PIX_FMT_YUVA420P) alpha = 1;
      if (frames == 0) {
        a_min = 255;
        a_max = 0;
        for (long i = 0; i < (long)dw * dh; i++) {
          int a = dst[i * 4 + 3];
          if (a < a_min) a_min = a;
          if (a > a_max) a_max = a;
        }
      }
      frames++;
      {
        hash = 1469598103934665603ULL;
        for (long i = 0; i < (long)dw * dh * 4; i++)
          hash = (hash ^ dst[i]) * 1099511628211ULL;
      }
    }
  }
  AVRational fps = av_guess_frame_rate(fmt, st, NULL);
  printf("decoder=%s\n", codec->name);
  printf("source_pix_fmt=%s\n", av_get_pix_fmt_name(src_fmt));
  printf("frames=%ld\n", frames);
  printf("fps=%d/%d\n", fps.num, fps.den);
  printf("alpha=%d\n", alpha);
  printf("frame0_alpha_min=%d\nframe0_alpha_max=%d\n", a_min, a_max);
  printf("last_frame_fnv1a=%016llx\n", (unsigned long long)hash);
  printf("license=%s\n", avcodec_license());
  return 0;
}
