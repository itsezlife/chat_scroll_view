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

# trace_start <dir>: a background system trace (trace.pbtx, at most 5.5 min,
# written to the file as it runs, so none of it is overwritten).
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

# logcat_start <dir>: streams the app's log to <dir>/logcat.txt with the
# device's monotonic seconds, so nothing is lost to the logcat ring in a long
# session. lab_log reads it once logcat_stop has run.
logcat_start() {
  D logcat -v monotonic -s flutter >"$1/logcat.txt" 2>/dev/null &
  echo $! >"$1/logcat.hostpid"
}

# logcat_stop <dir>: ends the stream logcat_start began.
logcat_stop() {
  [[ -f "$1/logcat.hostpid" ]] || return 0
  kill "$(cat "$1/logcat.hostpid")" 2>/dev/null || true
  rm -f "$1/logcat.hostpid"
}

# lab_log <dir>: the app's LAB lines, to <dir>/lab.txt: from the stream when
# logcat_start ran, else what the logcat ring still holds.
lab_log() {
  if [[ -s "$1/logcat.txt" ]]; then
    grep LAB "$1/logcat.txt" | sed 's/.*LAB/LAB/' >"$1/lab.txt" || true
  else
    D logcat -d -s flutter | grep LAB | sed 's/.*LAB/LAB/' >"$1/lab.txt" || true
  fi
}

# record_start <dir>: one screen recording of at most 170 s, so it never
# restarts within a session (screenrecord stops at 180 s, and a restart
# stalled the compositor for about 50 ms in a recorded session).
record_start() {
  D shell rm -f /sdcard/lab-record.mp4
  D shell screenrecord --time-limit 170 /sdcard/lab-record.mp4 &
  echo $! >"$1/record.hostpid"
  date +%s >"$1/record.started"
}

# record_stop <dir>: ends the recording if it still runs and pulls it to
# <dir>/screen.mp4.
record_stop() {
  [[ -f "$1/record.hostpid" ]] || return 0
  D shell pkill -INT screenrecord 2>/dev/null || true
  sleep 2
  kill "$(cat "$1/record.hostpid")" 2>/dev/null || true
  rm -f "$1/record.hostpid"
  D pull /sdcard/lab-record.mp4 "$1/screen.mp4" >/dev/null || true
  D shell rm -f /sdcard/lab-record.mp4
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
