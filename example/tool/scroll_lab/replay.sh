#!/usr/bin/env bash
# Replays a recorded tape under a system trace.
#
#   tool/scroll_lab/replay.sh <tape> <session> [jump-id]
#
# The tape is a name the app already holds (recorded by watch.sh on this
# install); a tape from another session is pushed first. With a jump id the
# list jumps there before the replay. Prints the app's replay summary; analyse
# with `seen.py perf/lab/<session>/trace.pftrace perf/lab/<tape>/tape.json`.
source "$(dirname "$0")/lab.sh"

tape=${1:?tape name}
dir=$(session_dir "${2:?session name}")
files="/sdcard/Android/data/$PKG/files"

if [[ -f "$EXAMPLE_DIR/perf/lab/$tape/tape.json" ]]; then
  D push "$EXAMPLE_DIR/perf/lab/$tape/tape.json" "$files/$tape.json" >/dev/null
fi
echo "battery $(battery_temp) °C"
D logcat -c
trace_start "$dir"
if [[ -n "${3:-}" ]]; then
  lab_set jump --es name "$3"
  wait_log "jump $3" 10
  sleep 3
fi
lab_set replay --es name "$tape"
wait_log "tape replay start $tape" 10
wait_log "tape replay done $tape" 600
sleep 2
trace_stop "$dir"
lab_log "$dir"
grep -E 'summary|tape replay done' "$dir/lab.txt"
