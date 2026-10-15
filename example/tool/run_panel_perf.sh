#!/usr/bin/env bash
# Panel catalog fling perf on a real device (profile mode).
#
#   tool/run_panel_perf.sh <device-id> <label> [extra flutter drive args...]
#
# Builds the APK once (Android) and reuses it on later runs; pass REBUILD=1 to
# force a rebuild after code changes. Extra args pass through to `flutter
# drive`, e.g. `--no-enable-impeller` (no rebuild needed) for a Skia A/B.
# A cold run without warm-up needs a rebuild:
#   DEFINES="--dart-define=PANEL_PERF_SKIP_WARM=true" REBUILD=1 \
#     tool/run_panel_perf.sh <device-id> s25-nowarm
#
# Reports land in .scratch/panel-catalog-glyph-perf/traces/<label>-*.json.
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:?device id (see: flutter devices)}"
label="${2:?label, e.g. s25-impeller}"
shift 2

target="${TARGET:-integration_test/all_tests.dart}"
driver=test_driver/integration_test.dart
defines="${DEFINES:-}"
export PERF_LABEL="$label"
export PERF_OUT="${PERF_OUT:-$PWD/../.scratch/panel-catalog-glyph-perf/traces}"
mkdir -p "$PERF_OUT"

platform="$(flutter devices --machine | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d['id']=='$device': print(d['targetPlatform'])")"

args=(--profile -d "$device" --driver="$driver" --target="$target" $defines)

if [[ "$platform" == android-* ]]; then
  apk=build/app/outputs/flutter-apk/app-profile.apk
  if [[ "${REBUILD:-0}" == 1 || ! -f "$apk" ]]; then
    flutter build apk --profile --target-platform android-arm64 \
      --target="$target" $defines
  fi
  [[ -f "$apk" ]] || { echo "build produced no $apk" >&2; exit 1; }
  args+=(--use-application-binary="$apk")
fi

flutter drive "${args[@]}" "$@"
echo "reports: $PERF_OUT/$label-*.json"
