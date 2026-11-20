#!/usr/bin/env bash
# One picker run from a fresh process: start the app, open the first chat,
# replay <tape> once to warm the picker, then replay it under a trace.
#
#   tool/scroll_lab/picker_run.sh <tape> <session> [lab switch=value ...]
source "$(dirname "$0")/lab.sh"
tape=${1:?tape}; session=${2:?session}; shift 2
D shell am force-stop "$PKG"
D shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5
D shell input tap 439 351   # the first chat in the list
sleep 4
for kv in "$@"; do lab_set "${kv%%=*}" --ez value "${kv#*=}"; sleep 1; done
tool/scroll_lab/replay.sh "$tape" "$session-warm" >/dev/null 2>&1 || { echo "warm-up failed" >&2; exit 1; }
sleep 2
echo "battery $(battery_temp) °C"
tool/scroll_lab/replay.sh "$tape" "$session" | tail -1
