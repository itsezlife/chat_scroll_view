#!/usr/bin/env bash
# One launch of the chat performance suite on one device (profile).
#
#   tool/run_chat_perf.sh <device-id> <label>
#
# Environment: SCENARIO (comma-separated globs), BACKEND (impeller|skia),
# HISTORY (messages in the seeded history). A thin wrapper: the gates, the
# per-device lock, the fingerprinted build and the retry live in
# tool/chat_perf.dart. The label is host-side only, never a dart-define.
set -euo pipefail
cd "$(dirname "$0")/.."

args=(quick --device "${1:?device id (see: adb devices)}" --label "${2:?label}")
[[ -n "${SCENARIO:-}" ]] && args+=(--scenario "$SCENARIO")
[[ -n "${BACKEND:-}" ]] && args+=(--backend "$BACKEND")
[[ -n "${HISTORY:-}" ]] && args+=(--history "$HISTORY")
exec dart run tool/chat_perf.dart "${args[@]}"
