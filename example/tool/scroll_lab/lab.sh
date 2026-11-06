#!/usr/bin/env bash
# Shared by the scroll lab scripts; sourced, never run.
#
# DEVICE picks the adb device (the only attached one by default). Sessions land
# in perf/lab/<session>/ (gitignored). The app must be a profile build with
# --dart-define=SCROLL_LAB=true, or the lab's broadcasts reach nothing.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(cd "$LAB_DIR/../.." && pwd)"
PKG=com.example.chat_scroll_view_example
DEVICE="${DEVICE:-$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')}"
[[ -n "$DEVICE" ]] || { echo "no adb device attached" >&2; exit 1; }
DEVICE_TRACE=/data/misc/perfetto-traces/lab.pftrace

D() { adb -s "$DEVICE" "$@"; }

# session_dir <name>: creates and prints perf/lab/<name>.
session_dir() {
  local dir="$EXAMPLE_DIR/perf/lab/${1:?session name}"
  mkdir -p "$dir"
  echo "$dir"
}

# lab_set <key> [extra am broadcast args...]: one lab switch or command.
lab_set() {
  local key=$1
  shift
  D shell am broadcast -a lab.SET --es key "$key" "$@" >/dev/null
}

# trace_start <dir>: a background system trace (trace.pbtx, at most 5 min).
trace_start() {
  D shell perfetto --background --txt -c - -o "$DEVICE_TRACE" \
    <"$LAB_DIR/trace.pbtx" | tr -d '\r' >"$1/perfetto.pid"
  sleep 2
}

# trace_stop <dir>: stops the trace and pulls it to <dir>/trace.pftrace.
trace_stop() {
  D shell kill "$(cat "$1/perfetto.pid")"
  sleep 3
  D pull "$DEVICE_TRACE" "$1/trace.pftrace" >/dev/null
  D shell rm -f "$DEVICE_TRACE"
}

# lab_log <dir>: the app's LAB lines so far, to <dir>/lab.txt.
lab_log() {
  D logcat -d -s flutter | grep LAB | sed 's/.*LAB/LAB/' >"$1/lab.txt" || true
}

# wait_log <pattern> <seconds>: waits for a LAB line; fails when it never
# comes, so a run that did not start reads as an error, not as no data.
wait_log() {
  local pattern=$1 left=$2
  until D logcat -d -s flutter | grep -q "$pattern"; do
    ((left -= 2)) || true
    if ((left <= 0)); then
      echo "no '$pattern' from the app: is it a SCROLL_LAB=true profile build?" >&2
      return 1
    fi
    sleep 2
  done
}

# battery_temp: the battery temperature in °C, the device's heat as the
# perf suite's cooldown reads it.
battery_temp() {
  D shell dumpsys battery | awk '/temperature/ { printf "%.1f\n", $2 / 10; exit }'
}
