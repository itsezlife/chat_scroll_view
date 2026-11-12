#!/usr/bin/env bash
# One arm of an A/B: a clean profile build, then replays of one tape.
#
#   RUNS=2 LAB_ON="snap plain" tool/scroll_lab/ab.sh <label> <tape> [dart-defines...]
#
# Alternate the arms yourself (A B A B) so drift lands on both. Each run prints
# its battery temperature; a run more than 2 °C over the arm's first is marked
# hot, as the perf suite's cooldown judges, and its numbers swing more than
# most changes do. The app starts at the chat on the default source, which
# holds the heavy bodies; pass --dart-define=CHAT_SOURCE=... to change it.
source "$(dirname "$0")/lab.sh"

label=${1:?label}
tape=${2:?tape name}
shift 2
log="$EXAMPLE_DIR/perf/lab/$label.run.log"
mkdir -p "$(dirname "$log")"

pkill -f "flutter_tools.snapshot run --profile" || true
sleep 1
(cd "$EXAMPLE_DIR" && flutter run --profile -d "$DEVICE" \
  --dart-define=SCROLL_LAB=true --dart-define=START_AT=chat \
  --dart-define=DISK_CACHE=false \
  --dart-define-from-file=../config/development.json "$@" >"$log" 2>&1 &)
until grep -qE "Flutter run key commands|Error:|FAILURE|Lost connection" "$log"; do sleep 2; done
if ! grep -q "Flutter run key commands" "$log"; then
  grep -E "^e: |Error|FAILURE" "$log" | head -5 >&2
  exit 1
fi
sleep 5
for key in ${LAB_ON:-}; do lab_set "$key" --ez value true; sleep 1; done

first=$(battery_temp)
for i in $(seq 1 "${RUNS:-2}"); do
  temp=$(battery_temp)
  hot=$(awk -v t="$temp" -v f="$first" 'BEGIN { if (t - f > 2) print " HOT" }')
  echo "$label#$i battery $temp °C$hot"
  "$LAB_DIR/replay.sh" "$tape" "$label-$i" | sed "s/^/  /"
done
