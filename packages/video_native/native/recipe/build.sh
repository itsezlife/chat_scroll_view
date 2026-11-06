#!/usr/bin/env bash
# Reproducible FFmpeg + libvpx build for the video decoder.
#
#   [TARGET=macos-arm64|android-arm64] native/recipe/build.sh \
#       [fetch|libvpx|ffmpeg|probe|check|verify|all]   (default: all)
#
# macos-arm64 (the default) builds natively on an arm64 Mac. android-arm64
# cross-compiles on a Mac with the Android NDK (ANDROID_NDK_HOME, else the
# highest <sdk>/ndk/<version> under ANDROID_HOME or ~/Library/Android/sdk;
# ANDROID_API picks the API level, default 24). The Android build has no probe:
# the host cannot run it; `verify` checks the ELF files instead.
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
BUILD="$NATIVE/.build/$TARGET"
DL="$BUILD/dl"
SRC="$BUILD/src"
PREFIX="$BUILD/prefix"
JOBS="$(sysctl -n hw.ncpu)"
MIN_MACOS=11.0
ANDROID_API="${ANDROID_API:-24}"
# Android 15+ devices may use 16 KiB pages: every .so must be aligned for them.
ANDROID_LDFLAGS="-Wl,-z,max-page-size=16384"

case "$TARGET" in
  macos-arm64)
    [ "$(uname -s)-$(uname -m)" = Darwin-arm64 ] || { echo "run on an arm64 Mac" >&2; exit 2; }
    export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
    LIBVPX_TARGET=arm64-darwin20-gcc
    LIBVPX_EXTRA=()
    ;;
  android-arm64)
    [ "$(uname -s)" = Darwin ] || { echo "the Android build is set up for a Mac host" >&2; exit 2; }
    NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
    if [ -z "$NDK" ]; then
      SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
      NDK="$(ls -d "$SDK"/ndk/[0-9]* 2>/dev/null | sort -V | tail -n1 || true)"
    fi
    TOOLS="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    [ -x "$TOOLS/aarch64-linux-android$ANDROID_API-clang" ] || {
      echo "no Android NDK clang for API $ANDROID_API under '${NDK:-<none>}'; set ANDROID_NDK_HOME" >&2
      exit 2
    }
    LIBVPX_TARGET=arm64-android-gcc
    # NEON is part of arm64, so no runtime detection (which on Android would
    # need the NDK's cpu-features source).
    LIBVPX_EXTRA=(--disable-runtime-cpu-detect)
    # libvpx's configure reads the toolchain from these variables.
    export CC="$TOOLS/aarch64-linux-android$ANDROID_API-clang"
    export CXX="$TOOLS/aarch64-linux-android$ANDROID_API-clang++"
    export AR="$TOOLS/llvm-ar" AS="$CC" LD="$CC" NM="$TOOLS/llvm-nm"
    export RANLIB="$TOOLS/llvm-ranlib" STRIP="$TOOLS/llvm-strip"
    ;;
  *) echo "unsupported TARGET $TARGET (macos-arm64, android-arm64)" >&2; exit 2 ;;
esac

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
      --target="$LIBVPX_TARGET" \
      --prefix="$PREFIX" \
      --enable-pic --enable-static --disable-shared \
      --enable-vp8-decoder --enable-vp9-decoder \
      --disable-vp8-encoder --disable-vp9-encoder \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests \
      --disable-install-bins --disable-install-docs \
      --enable-multithread \
      "${LIBVPX_EXTRA[@]}"
    make -j"$JOBS"
    make install )
}

# Mirrors Telegram's component list (research/07), minus audio, hevc, dav1d.
FFMPEG_COMMON=(
  --prefix="$PREFIX"
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
)
case "$TARGET" in
  macos-arm64)
    FFMPEG_FLAGS=("${FFMPEG_COMMON[@]}"
      --arch=arm64 --target-os=darwin
      --install-name-dir=@rpath
      --extra-cflags="-I$PREFIX/include -mmacosx-version-min=$MIN_MACOS"
      # Header padding: the Flutter tool rewrites the install names of bundled
      # dylibs to longer paths, which install_name_tool refuses without room.
      --extra-ldflags="-L$PREFIX/lib -mmacosx-version-min=$MIN_MACOS -Wl,-headerpad_max_install_names")
    ;;
  android-arm64)
    # --enable-jni and --enable-mediacodec stay off (autodetect is off and
    # neither is named): decoding is software, and JNI would tie the library to
    # a JavaVM. The Android target builds unversioned libavcodec.so files with
    # the same string as the soname, which is what the loader matches.
    FFMPEG_FLAGS=("${FFMPEG_COMMON[@]}"
      --enable-cross-compile --arch=aarch64 --target-os=android --enable-neon
      --cc="$CC" --cxx="$CXX" --ar="$AR" --nm="$NM" --ranlib="$RANLIB" --strip="$STRIP"
      --extra-cflags="-I$PREFIX/include"
      --extra-ldflags="-L$PREFIX/lib $ANDROID_LDFLAGS")
    # ffmpeg finds libvpx through pkg-config: point it at ours, not the host's.
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
    ;;
esac

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
  local pattern='lib{avcodec,avformat,avutil,swscale}.*.*.*.dylib'
  [ "$TARGET" = android-arm64 ] && pattern='lib{avcodec,avformat,avutil,swscale}.so'
  for f in $(eval echo "$PREFIX/lib/$pattern"); do
    cp "$f" "$BUILD/stripped/"
    if [ "$TARGET" = android-arm64 ]; then
      "$STRIP" --strip-unneeded "$BUILD/stripped/$(basename "$f")"
    else
      strip -x "$BUILD/stripped/$(basename "$f")"
    fi
  done
}

do_probe() {
  [ "$TARGET" = macos-arm64 ] || { echo "the probe runs on the host: macos-arm64 only" >&2; exit 2; }
  clang -O1 -Wall -Wextra -arch arm64 -mmacosx-version-min=$MIN_MACOS \
    -I"$PREFIX/include" "$NATIVE/probe/probe.c" \
    -L"$PREFIX/lib" -lavformat -lavcodec -lswscale -lavutil \
    -Wl,-rpath,"$PREFIX/lib" -o "$BUILD/probe"
}

# Runs the probe over the fixtures and compares against expected.txt's claims.
do_check() {
  [ "$TARGET" = macos-arm64 ] || { echo "check runs the probe: macos-arm64 only; use verify" >&2; exit 2; }
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

# Android: what the host can say about the ELF files without running them.
do_verify() {
  [ "$TARGET" = android-arm64 ] || { echo "verify is for android-arm64" >&2; exit 2; }
  local readelf="$TOOLS/llvm-readelf" fail=0 f
  for f in "$PREFIX"/lib/lib{avcodec,avformat,avutil,swscale}.so; do
    echo "== $(basename "$f") ($(wc -c <"$f") bytes, $(wc -c <"$BUILD/stripped/$(basename "$f")") stripped)"
    "$readelf" -h "$f" | grep -E 'Class|Machine'
    "$readelf" -lW "$f" | awk '$1=="LOAD"{print "LOAD align " $NF}'
    "$readelf" -dW "$f" | grep -E 'NEEDED|SONAME|TEXTREL' || true
    "$readelf" -lW "$f" | awk '$1=="LOAD" && $NF!="0x4000"{bad=1} END{exit bad}' \
      || { echo "FAIL: a LOAD segment is not aligned to 0x4000"; fail=1; }
    ! "$readelf" -dW "$f" | grep -q TEXTREL || { echo "FAIL: text relocations"; fail=1; }
  done
  grep -q -- '--enable-gpl\|--enable-nonfree\|--enable-version3' "$BUILD/configure-line.txt" \
    && { echo "FAIL: GPL/nonfree flag in the configure line"; fail=1; }
  exit $fail
}

case "${1:-all}" in
  verify) do_verify ;;
  fetch) do_fetch ;;
  libvpx) do_libvpx ;;
  ffmpeg) do_ffmpeg ;;
  probe) do_probe ;;
  check) do_check ;;
  all)
    do_libvpx; do_ffmpeg
    [ "$TARGET" = macos-arm64 ] && do_probe
    exit 0 ;;
  *) echo "unknown stage $1" >&2; exit 2 ;;
esac
