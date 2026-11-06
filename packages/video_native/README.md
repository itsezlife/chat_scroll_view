# video_native

Skeleton for native video decoding: FFmpeg (LGPL, shared libraries) with libvpx
for VP9 alpha. Today it holds the reproducible build recipe and a C probe that
proves the build decodes H.264 MP4, VP9 WebM with alpha, and GIF. There is no
Dart API yet.

## Build (macOS arm64)

```shell
packages/video_native/native/recipe/build.sh        # fetch, libvpx, ffmpeg, probe
packages/video_native/native/recipe/build.sh check  # run the probe on the fixtures
```

Output goes to `native/.build/macos-arm64/` (gitignored): `prefix/` (headers and
dylibs), `stripped/` (the dylibs, stripped), `probe`, `configure-line.txt`.
Sources and their SHA-256 are pinned in `native/recipe/manifest.env`:
FFmpeg 9.0.2, libvpx 1.17.0. The tarballs are checked against the pinned hash
before extraction; a mismatch deletes the download and stops the build. The
hashes equal the ones Homebrew's formula API records independently for the same
URLs; neither project publishes a checksum file and FFmpeg's `.asc` signature
could not be checked (no gpg on the build machine).

x86_64 is not built: both projects need nasm for their x86 assembly (or
`--disable-x86asm` for FFmpeg and a generic libvpx target, slower). Possible
later additions: HEVC, dav1d (AV1), audio decoders.

## What is enabled

The set Telegram ships, LGPL only (no `--enable-gpl`, `--enable-nonfree`,
`--enable-version3`), `--disable-everything` plus: demuxers `mov`, `matroska`,
`gif`; decoders `h264`, `gif`, `libvpx_vp9`, `vp9` (native, kept only to show
the alpha finding; production forces `libvpx-vp9`); parsers `h264`, `vp9`,
`gif`; bsf `vp9_superframe_split`; protocol `file`; libswscale. No avfilter,
avdevice, swresample. libvpx is a static, PIC, decoder-only build (VP8 and VP9)
linked into `libavcodec`.

The GIF parser is required: without it the GIF demuxer hands out unsplit
packets and decoding fails with "LZW decode failed" after one frame.

Exact configure line (`<P>` is `native/.build/macos-arm64/prefix`):

```
--prefix=<P> --arch=arm64 --target-os=darwin --enable-shared --disable-static
--enable-pic --enable-small --disable-everything --disable-programs
--disable-doc --disable-debug --disable-network --disable-autodetect
--disable-avdevice --disable-avfilter --disable-swresample --enable-avcodec
--enable-avformat --enable-avutil --enable-swscale --enable-libvpx
--enable-protocol=file --enable-demuxer=mov --enable-demuxer=matroska
--enable-demuxer=gif --enable-decoder=h264 --enable-decoder=gif
--enable-decoder=libvpx_vp9 --enable-decoder=vp9 --enable-parser=h264
--enable-parser=vp9 --enable-parser=gif --enable-bsf=vp9_superframe_split
--install-name-dir=@rpath --extra-cflags="-I<P>/include -mmacosx-version-min=11.0"
--extra-ldflags="-L<P>/lib -mmacosx-version-min=11.0"
```

libvpx: `--target=arm64-darwin20-gcc --enable-pic --enable-static --disable-shared
--enable-vp8-decoder --enable-vp9-decoder --disable-vp8-encoder
--disable-vp9-encoder --disable-examples --disable-tools --disable-docs
--disable-unit-tests --enable-multithread`.

## Produced libraries (stripped with `strip -x`)

| Library | Size |
| --- | --- |
| libavcodec.63.1.102.dylib (includes libvpx) | 1,661,464 B |
| libavformat.63.1.102.dylib | 456,600 B |
| libavutil.61.1.102.dylib | 539,336 B |
| libswscale.10.1.102.dylib | 607,384 B |
| total | 3,264,784 B |

`otool -L`: each library references only the others (`@rpath/libav*.dylib`) and
system libraries (`libSystem`, CoreFoundation, CoreVideo, CoreMedia). The
probe's `avcodec_license()` prints `LGPL version 2.1 or later`.

## Probe and fixtures

`native/probe/probe.c` is a proof, not an API: `probe <file> <w> <h> [--native]`
decodes every frame, scales to BGRA with swscale and prints frames, fps,
source pixel format, whether any frame was `yuva420p`, alpha min / max of frame
0, and an FNV-1a checksum of the last frame. VP9 is decoded by `libvpx-vp9`
unless `--native` is given. Expected values were written first in
`native/probe/expected.txt`; `build.sh check` asserts them.

Fixtures in `native/probe/fixtures/` are synthetic, generated with Homebrew
FFmpeg 9.0.2:

```shell
ffmpeg -f lavfi -i testsrc2=size=320x240:rate=30:duration=2 -c:v libx264 \
  -pix_fmt yuv420p -an -movflags +faststart h264_320x240_30fps_2s.mp4
ffmpeg -f lavfi -i "color=c=black@0.0:s=512x512:r=30:d=1,format=yuva420p,\
geq=lum='if(lt(hypot(X-(100+T*300)\,Y-256)\,60)\,200\,16)':cb=128:cr=128:\
a='if(lt(hypot(X-(100+T*300)\,Y-256)\,60)\,255\,0)'" -c:v libvpx-vp9 \
  -pix_fmt yuva420p -auto-alt-ref 0 -b:v 0 -crf 40 vp9_alpha_512x512_30fps_1s.webm
ffmpeg -f lavfi -i testsrc2=size=64x48:rate=10:duration=1 \
  -vf "split[a][b];[a]palettegen[p];[b][p]paletteuse" gif_64x48_10fps_1s.gif
```

(The WebM is a 60 px disc moving across a transparent background.)

Results:

| File | decoder | source format | frames | fps | alpha | frame 0 alpha min / max | last-frame FNV-1a |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mp4 (320x240) | h264 | yuv420p | 60 | 30/1 | no | 255 / 255 | b8709218e91978ae |
| webm (512x512) | libvpx-vp9 | yuva420p | 30 | 30/1 | yes | 0 / 255 | ecf38bde19115b21 |
| webm, `--native` | vp9 | yuv420p | 30 | 30/1 | no | 255 / 255 | 6fad7cfbfd5c6668 |
| gif (64x48) | gif | bgra | 10 | 10/1 | no | 255 / 255 | 453d10780f66e20b |

The WebM row with `--native` is the negative proof: the same file through the
same build, but with FFmpeg's own `vp9` decoder, yields opaque `yuv420p` (the
container still carries `alpha_mode: 1`). This is the finding of FFmpeg Trac
#8344, and why the decoder is forced to `libvpx-vp9` (as tdesktop does in
`ffmpeg_utility.cpp`).
