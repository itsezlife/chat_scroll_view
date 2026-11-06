#!/usr/bin/env bash
# Traces one scenario that starts from a fresh process.
#
#   tool/scroll_lab/scenario.sh open <session> <x> <y>   # cold start, tap a chat
#   tool/scroll_lab/scenario.sh jump <session> <id>      # fresh app, jump to <id>
#
# Both force-stop the app first, so caches held in memory are cold; caches on
# disk are as the last run left them. The app is started with systrace on, so
# confirm a slow frame from the LAB log of a run without it before trusting
# its trace duration. Analyse an open with `open_gaps.py <trace>`.
source "$(dirname "$0")/lab.sh"

cmd=${1:?open|jump}
dir=$(session_dir "${2:?session name}")

D shell am force-stop "$PKG"
sleep 1
D logcat -c
case $cmd in
  open)
    trace_start "$dir"
    D shell am start -n "$PKG/.MainActivity" --ez trace-systrace true >/dev/null
    sleep 6
    D shell input tap "${3:?x}" "${4:?y}"
    sleep 4
    ;;
  jump)
    D shell am start -n "$PKG/.MainActivity" --ez trace-systrace true >/dev/null
    sleep 8
    trace_start "$dir"
    lab_set jump --es name "${3:?message id}"
    wait_log "jump $3" 10
    sleep 5
    ;;
  *)
    echo "usage: $0 open <session> <x> <y> | jump <session> <id>" >&2
    exit 1
    ;;
esac
trace_stop "$dir"
lab_log "$dir"
echo "$cmd: trace=$(wc -c <"$dir/trace.pftrace")B, slow frames: $(grep -c 'LAB slow' "$dir/lab.txt" || true)"
