# video_native

Native video decoding for chat clips: FFmpeg (LGPL, shared libraries) with
libvpx for VP9 alpha, behind a flat C ABI of our own
([ADR 042](../../docs/adr/042-native-media-decoding.md)). A leaf of the
workspace: it depends on no workspace package.

It holds the C wrapper (`native/include/chat_video.h`, `native/src/chat_video.c`),
the build recipe and proof probe, the build hook, and the Dart side: the
`VideoBinding` interface, `NativeVideoBinding`, and `FakeVideoBinding` with a
contract suite in `testing.dart`.

## The wrapper

`chat_video.h` is the only product API; no FFmpeg type crosses it.

| Call | Does |
| --- | --- |
| `chat_video_abi_version` | The load probe, returns 1. |
| `chat_video_open(bytes, len, w, h, &handle)` | Copies the bytes (AVIO over memory, no path API), takes the first video stream, forces `libvpx-vp9` for VP9, opens the decoder for frames of `w` by `h`. |
| `chat_video_info` | Source size, duration (ms or -1), frame rate, `has_alpha`. |
| `chat_video_next(handle, dst, stride, &pts_ms)` | Decodes the next frame, scales it with swscale to the target size, writes premultiplied BGRA. Returns `0`, or `CHAT_VIDEO_END_OF_STREAM` (1). |
| `chat_video_rewind` | Seeks to the start, flushes the decoder, resets the per-pass budgets. |
| `chat_video_free` | Releases the handle. |

Statuses are the enum in the header (`0` ok, `1` end of stream, `-1`..`-8`
failures); `ChatVideoStatus` in Dart repeats the numbers and a test compares
them with the header. A handle is used by one thread at a time; handles are
independent. `has_alpha` is the stream's declaration (WebM `alpha_mode` or an
alpha pixel format); a GIF is reported without it although its frames may be
transparent. Every frame is premultiplied whenever the decoded format has
alpha. Frames are stretched to the target size, not letterboxed.

Hardening, all in the header as `CHAT_VIDEO_MAX_*`: input 10 MiB (refused
before it is read), source 3840 per side and 3840x2160 pixels, target 2048 per
side, 20000 packets and 10000 frames per pass (a rewind starts a new pass), 10
consecutive undecodable packets tolerated. FFmpeg may open nothing but the
memory buffer (`protocol_whitelist` is empty). Every FFmpeg return is checked
and every failure path frees what it made (`leaks --atExit` over open, decode,
rewind and free of the fixtures and damaged copies reports none).

## Delivery

`hook/build.dart` supports macOS arm64 and Android arm64-v8a. On macOS it
compiles the wrapper with the system `cc` against the recipe's prefix and
bundles it plus the four FFmpeg dylibs as code assets (the Flutter tool then rewrites their install names
together; the dylibs therefore need header padding, which the recipe now
links in). On Android it compiles with the NDK clang (the NDK is found the way
`lottie_native` finds it: `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`, then the
highest `<sdk>/ndk/<version>`; the clang for the app's NDK API level) and
bundles `libchat_video.so` plus `libavcodec.so`, `libavformat.so`,
`libavutil.so`, `libswscale.so`; Android x86_64 and armv7 emit nothing and
warn. The prefix is `native/.build/<target>/prefix`, or the directory
`CHAT_VIDEO_FFMPEG_DIR` names (an environment change needs `flutter clean`).
With no prefix, or on another target, no asset is emitted and a warning names
the recipe command; `NativeVideoBinding.probe()` then reports `missingLibrary`
and the tests that need the library skip. Prebuilt delivery is a later ticket.

## Build (Android arm64-v8a)

```shell
TARGET=android-arm64 packages/video_native/native/recipe/build.sh         # libvpx, ffmpeg
TARGET=android-arm64 packages/video_native/native/recipe/build.sh verify  # ELF checks
```

Cross-compiled on a Mac with the NDK (no nasm: arm64 uses NEON, so no
`--disable-asm`). Same pinned sources and flags as macOS plus `--enable-cross-compile
--arch=aarch64 --target-os=android --enable-neon`, `--enable-jni` and mediacodec off,
`-Wl,-z,max-page-size=16384`; libvpx `--target=arm64-android-gcc
--disable-runtime-cpu-detect`. Output in `native/.build/android-arm64/`. The
probe cannot run on the host, so `verify` reads the ELF headers: aarch64, every
`PT_LOAD` aligned 0x4000, no text relocations, `NEEDED` only the FFmpeg
libraries and libc/libm/libdl/liblog, and no GPL flag in `configure-line.txt`.

| Library (arm64-v8a, API 24) | Size |
| --- | --- |
| libavcodec.so (includes libvpx) | 1,785,608 B |
| libavformat.so | 436,520 B |
| libavutil.so | 558,696 B |
| libswscale.so | 675,048 B |
| libchat_video.so (debug APK) | 13,832 B |

## Tests

`flutter test test/unit_test.dart`. The native tests run against the three
fixtures below; the contract suite runs over the fake and the native binding.

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
--extra-ldflags="-L<P>/lib -mmacosx-version-min=11.0 -Wl,-headerpad_max_install_names"
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
