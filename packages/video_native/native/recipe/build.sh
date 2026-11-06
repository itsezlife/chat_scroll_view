#!/usr/bin/env bash
# Reproducible FFmpeg + libvpx build for the video decoder, macOS arm64.
#
#   native/recipe/build.sh [fetch|libvpx|ffmpeg|probe|check|all]   (default: all)
#
# Everything lands in native/.build/<target>/ (gitignored): downloads in
# dl/, sources in src/, the install prefix in prefix/, the probe in probe.
# Sources are pinned in manifest.env and verified by SHA-256 before use.
#
# x86_64 is not built here: libvpx and FFmpeg need nasm (or yasm) for their
# assembly there, and none is installed. To build x86_64 install nasm, or pass
# --disable-x86asm to FFmpeg and --disable-... asm via --target=generic-gnu to
# libvpx (slower decoding).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(cd "$HERE/.." && pwd)"
# shellcheck source=manifest.env
. "$HERE/manifest.env"

TARGET="${TARGET:-macos-arm64}"
[ "$TARGET" = macos-arm64 ] || { echo "only macos-arm64 is supported" >&2; exit 2; }
[ "$(uname -s)-$(uname -m)" = Darwin-arm64 ] || { echo "run on an arm64 Mac" >&2; exit 2; }

BUILD="$NATIVE/.build/$TARGET"
DL="$BUILD/dl"
SRC="$BUILD/src"
PREFIX="$BUILD/prefix"
JOBS="$(sysctl -n hw.ncpu)"
MIN_MACOS=11.0
export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"

fetch_one() { # url sha256 file
  local url="$1" sha="$2" file="$DL/$3"
  mkdir -p "$DL"
  [ -f "$file" ] || curl -fsSL --proto '=https' -o "$file" "$url"
  local got
  got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  if [ "$got" != "$sha" ]; then
    rm -f "$file"
    echo "SHA-256 mismatch for $3: got $got, pinned $sha" >&2
    exit 1
  fi
}

extract() { # archive dir  (always into a fresh, empty directory)
  rm -rf "$2"
  mkdir -p "$2"
  tar -xf "$1" -C "$2" --strip-components=1
}

do_fetch() {
  fetch_one "$FFMPEG_URL" "$FFMPEG_SHA256" "ffmpeg-$FFMPEG_VERSION.tar.xz"
  fetch_one "$LIBVPX_URL" "$LIBVPX_SHA256" "libvpx-$LIBVPX_VERSION.tar.gz"
}

do_libvpx() {
  do_fetch
  extract "$DL/libvpx-$LIBVPX_VERSION.tar.gz" "$SRC/libvpx"
  mkdir -p "$SRC/libvpx-build" "$PREFIX"
  ( cd "$SRC/libvpx-build"
    # Decoder only (VP8 + VP9), static and PIC: it is linked into libavcodec.
    "$SRC/libvpx/configure" \
      --target=arm64-darwin20-gcc \
      --prefix="$PREFIX" \
      --enable-pic --enable-static --disable-shared \
      --enable-vp8-decoder --enable-vp9-decoder \
      --disable-vp8-encoder --disable-vp9-encoder \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests \
      --disable-install-bins --disable-install-docs \
      --enable-multithread
    make -j"$JOBS"
    make install )
}

# Mirrors Telegram's component list (research/07), minus audio, hevc, dav1d.
FFMPEG_FLAGS=(
  --prefix="$PREFIX"
  --arch=arm64 --target-os=darwin
  --enable-shared --disable-static --enable-pic --enable-small
  --disable-everything --disable-programs --disable-doc --disable-debug
  --disable-network --disable-autodetect
  --disable-avdevice --disable-avfilter --disable-swresample
  --enable-avcodec --enable-avformat --enable-avutil --enable-swscale
  --enable-libvpx
  --enable-protocol=file
  --enable-demuxer=mov --enable-demuxer=matroska --enable-demuxer=gif
  --enable-decoder=h264 --enable-decoder=gif
  --enable-decoder=libvpx_vp9 --enable-decoder=vp9
  --enable-parser=h264 --enable-parser=vp9 --enable-parser=gif
  --enable-bsf=vp9_superframe_split
  --install-name-dir=@rpath
  --extra-cflags="-I$PREFIX/include -mmacosx-version-min=$MIN_MACOS"
  # Header padding: the Flutter tool rewrites the install names of bundled
  # dylibs to longer paths, which install_name_tool refuses without room.
  --extra-ldflags="-L$PREFIX/lib -mmacosx-version-min=$MIN_MACOS -Wl,-headerpad_max_install_names"
)

do_ffmpeg() {
  do_fetch
  extract "$DL/ffmpeg-$FFMPEG_VERSION.tar.xz" "$SRC/ffmpeg"
  mkdir -p "$SRC/ffmpeg-build"
  ( cd "$SRC/ffmpeg-build"
    "$SRC/ffmpeg/configure" "${FFMPEG_FLAGS[@]}"
    make -j"$JOBS"
    make install )
  printf '%s\n' "configure ${FFMPEG_FLAGS[*]}" > "$BUILD/configure-line.txt"
  # Stripped copies are what we size and report.
  rm -rf "$BUILD/stripped"; mkdir -p "$BUILD/stripped"
  for f in "$PREFIX"/lib/lib{avcodec,avformat,avutil,swscale}.*.*.*.dylib; do
    cp "$f" "$BUILD/stripped/"
    strip -x "$BUILD/stripped/$(basename "$f")"
  done
}

do_probe() {
  clang -O1 -Wall -Wextra -arch arm64 -mmacosx-version-min=$MIN_MACOS \
    -I"$PREFIX/include" "$NATIVE/probe/probe.c" \
    -L"$PREFIX/lib" -lavformat -lavcodec -lswscale -lavutil \
    -Wl,-rpath,"$PREFIX/lib" -o "$BUILD/probe"
}

# Runs the probe over the fixtures and compares against expected.txt's claims.
do_check() {
  local fx="$NATIVE/probe/fixtures" p="$BUILD/probe" fail=0 out
  expect() { # label, output, needle...
    local label="$1" output="$2"; shift 2
    for n in "$@"; do
      grep -qx "$n" <<<"$output" || { echo "FAIL $label: missing $n"; fail=1; }
    done
  }
  out="$("$p" "$fx/h264_320x240_30fps_2s.mp4" 320 240)"; echo "$out"
  expect mp4 "$out" frames=60 fps=30/1 alpha=0 decoder=h264
  out="$("$p" "$fx/vp9_alpha_512x512_30fps_1s.webm" 512 512)"; echo "$out"
  expect webm "$out" frames=30 alpha=1 decoder=libvpx-vp9 frame0_alpha_min=0 frame0_alpha_max=255
  out="$("$p" "$fx/vp9_alpha_512x512_30fps_1s.webm" 512 512 --native)"; echo "$out"
  expect webm-native "$out" alpha=0 decoder=vp9
  out="$("$p" "$fx/gif_64x48_10fps_1s.gif" 64 48)"; echo "$out"
  expect gif "$out" frames=10 alpha=0 decoder=gif
  grep -q '^license=LGPL version 2.1 or later$' <<<"$out" || { echo "FAIL license"; fail=1; }
  exit $fail
}

case "${1:-all}" in
  fetch) do_fetch ;;
  libvpx) do_libvpx ;;
  ffmpeg) do_ffmpeg ;;
  probe) do_probe ;;
  check) do_check ;;
  all) do_libvpx; do_ffmpeg; do_probe ;;
  *) echo "unknown stage $1" >&2; exit 2 ;;
esac
