#!/usr/bin/env bash
# One launch of the chat performance suite on one device (profile).
#
#   tool/run_chat_perf.sh <device-id> <label> [extra flutter drive args...]
#
# Environment:
#   SCENARIO  comma-separated globs over scenario ids (default: all)
#   BACKEND   impeller (default) or skia; skia adds --no-enable-impeller
#   SEMANTICS off (default, the shipping mode), on or pair (off and on in the
#             same launch, with the on/off ratio)
#   HISTORY   messages in the seeded history (default: the suite's 20000)
#
# The built APK is cached by a fingerprint of the suite's sources, the
# workspace `lib/` and the dart-define set, so a source change never runs a
# stale binary. Reports land in perf/runs/<label>/ (git-ignored). Use
# `dart run tool/chat_perf.dart quick` for the table.
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:?device id (see: flutter devices)}"
label="${2:?label, e.g. quick-1}"
shift 2

backend="${BACKEND:-impeller}"
defines=(--dart-define="CHAT_PERF_BACKEND=$backend")
[[ -n "${SCENARIO:-}" ]] && defines+=(--dart-define="CHAT_PERF_SCENARIO=$SCENARIO")
[[ -n "${SEMANTICS:-}" ]] && defines+=(--dart-define="CHAT_PERF_SEMANTICS=$SEMANTICS")
[[ -n "${HISTORY:-}" ]] && defines+=(--dart-define="CHAT_PERF_HISTORY=$HISTORY")

target=integration_test/chat_perf/chat_perf_test.dart
driver=test_driver/integration_test.dart
export PERF_LABEL="$label"
export PERF_OUT="${PERF_OUT:-$PWD/perf}"
mkdir -p "$PERF_OUT/runs/$label"

args=(--profile -d "$device" --driver="$driver" --target="$target" "${defines[@]}")
# The timeline tracer (pair mode) connects to the VM service itself.
[[ "${SEMANTICS:-}" == pair ]] && args+=(--no-dds)
[[ "$backend" == skia ]] && args+=(--no-enable-impeller)

platform="$(flutter devices --machine | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d['id']=='$device': print(d['targetPlatform'])")"

if [[ "$platform" == android-* ]]; then
  fingerprint="$( (printf '%s\n' "${defines[@]}"; \
    find integration_test/chat_perf integration_test/panel_perf ../lib ../packages/*/lib pubspec.yaml ../pubspec.lock \
      -type f -print0 | sort -z | xargs -0 shasum) | shasum | cut -c1-16)"
  apk="build/chat_perf/$fingerprint.apk"
  if [[ ! -f "$apk" ]]; then
    flutter build apk --profile --target-platform android-arm64 \
      --target="$target" "${defines[@]}"
    mkdir -p "$(dirname "$apk")"
    cp build/app/outputs/flutter-apk/app-profile.apk "$apk"
  fi
  args+=(--use-application-binary="$apk")
fi

status=0
flutter drive "${args[@]}" "$@" || status=$?
echo "reports: $PERF_OUT/runs/$label/"
exit "$status"
