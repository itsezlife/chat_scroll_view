#!/usr/bin/env bash
# Records the user's own gestures as a replayable tape.
#
#   tool/scroll_lab/watch.sh start <session>   # then the user scrolls
#   tool/scroll_lab/watch.sh stop <session>
#
# Captures a system trace (at most 5 min), the raw touches (getevent), the
# in-app pointer tape and the LAB log. Stop prints a sanity line; push the
# tape back with `replay.sh <session>`.
source "$(dirname "$0")/lab.sh"

cmd=${1:?start|stop}
name=${2:?session name}
dir=$(session_dir "$name")

case $cmd in
  start)
    D logcat -c
    trace_start "$dir"
    D shell getevent -lt >"$dir/getevent.txt" 2>/dev/null &
    echo $! >"$dir/getevent.hostpid"
    lab_set record --ez value true --es name "$name"
    wait_log "tape record start $name" 10
    date +%s >"$dir/started"
    echo "watching $name: scroll now, then run: $0 stop $name"
    ;;
  stop)
    lab_set record --ez value false --es name "$name"
    wait_log "tape saved $name" 10
    trace_stop "$dir"
    kill "$(cat "$dir/getevent.hostpid")" 2>/dev/null || true
    lab_log "$dir"
    D pull "/sdcard/Android/data/$PKG/files/$name.json" "$dir/tape.json" >/dev/null
    touches=$(grep -c ABS_MT_POSITION_Y "$dir/getevent.txt" || true)
    echo "$name: $(($(date +%s) - $(cat "$dir/started")))s," \
      "touches=$touches, tape=$(wc -c <"$dir/tape.json")B," \
      "trace=$(wc -c <"$dir/trace.pftrace")B"
    grep 'tape saved' "$dir/lab.txt"
    ;;
  *)
    echo "usage: $0 start|stop <session>" >&2
    exit 1
    ;;
esac
