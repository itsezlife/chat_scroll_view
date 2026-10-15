#!/usr/bin/env bash
# One launch of the panel catalog acceptance test on a real device (profile).
#
#   tool/run_panel_perf.sh <device-id> <label> [extra flutter drive args...]
#
# Exits non-zero when an asserted scenario fails. For the three-launch rule use
# `dart run tool/panel_perf.dart <device-id> <label>`, which calls this once per
# fresh launch.
#
# Precondition (it decides whether the numbers mean anything): the reference
# device is cool, on a charger, screen on, display at its top refresh rate.
#
# TARGET picks the test entry point (default: the bare-panel suite; the chat
# suite is integration_test/panel_over_chat_test.dart). Each target keeps its
# own built APK.
#
# Builds the APK once per target (Android) and reuses it on later runs; pass
# REBUILD=1 to force a rebuild after code changes. Extra args pass through to
# `flutter drive`, e.g. `--no-enable-impeller` (no rebuild needed) for a Skia
# A/B.
#
# Reports land in perf/runs/<label>/ (git-ignored); the kept comparison set is
# perf/baseline/ (see `dart run tool/panel_perf.dart --help`).
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:?device id (see: flutter devices)}"
label="${2:?label, e.g. s25-launch1}"
shift 2

target="${TARGET:-integration_test/all_tests.dart}"
driver=test_driver/integration_test.dart
defines="${DEFINES:-}"
export PERF_LABEL="$label"
export PERF_OUT="${PERF_OUT:-$PWD/perf}"
mkdir -p "$PERF_OUT/runs/$label"

platform="$(flutter devices --machine | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d['id']=='$device': print(d['targetPlatform'])")"

args=(--profile -d "$device" --driver="$driver" --target="$target" $defines)

if [[ "$platform" == android-* ]]; then
  built=build/app/outputs/flutter-apk/app-profile.apk
  # The build output has one fixed name, so a second target would otherwise
  # reuse the first target's binary.
  apk="build/panel_perf/$(basename "$target" .dart).apk"
  if [[ "${REBUILD:-0}" == 1 || ! -f "$apk" ]]; then
    flutter build apk --profile --target-platform android-arm64 \
      --target="$target" $defines
    [[ -f "$built" ]] || { echo "build produced no $built" >&2; exit 1; }
    mkdir -p "$(dirname "$apk")"
    cp "$built" "$apk"
  fi
  args+=(--use-application-binary="$apk")
fi

status=0
flutter drive "${args[@]}" "$@" || status=$?
echo "reports: $PERF_OUT/runs/$label/"
exit "$status"
