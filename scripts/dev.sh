#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT="${PORT:-8080}"

# Stop any process listening on [PORT] (macOS/Linux).
stop_port_listeners() {
  local port="$1"
  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi

  local pids
  pids="$(lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -z "$pids" ]]; then
    return 0
  fi

  echo "    Killing listener(s) on port $port: $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 0.5
  # shellcheck disable=SC2086
  if kill -0 $pids 2>/dev/null; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

lan_ip() {
  # macOS: Wi‑Fi (en0) then Ethernet (en1). Linux fallback via hostname -I.
  ipconfig getifaddr en0 2>/dev/null ||
    ipconfig getifaddr en1 2>/dev/null ||
    hostname -I 2>/dev/null | awk '{print $1}' ||
    true
}

write_android_device_config() {
  local ip="$1"
  local port="$2"
  local file="config/development.android.device.json"
  cat >"$file" <<EOF
{
  "DEMO_BACKEND_URL": "http://${ip}:${port}"
}
EOF
  echo "    Wrote $file → http://${ip}:${port}"
}

stop_backend_servers() {
  local port="$1"
  echo "==> Stopping any existing backend on port $port..."

  stop_port_listeners "$port"

  if pgrep -f "dart.*bin/server.dart" >/dev/null 2>&1; then
    echo "    Killing stray bin/server.dart process(es)..."
    pkill -f "dart.*bin/server.dart" 2>/dev/null || true
    sleep 0.5
  fi

  if command -v lsof >/dev/null 2>&1 &&
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "ERROR: port $port is still in use:" >&2
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
    exit 1
  fi

  echo "    Port $port is free."
}

wait_for_backend() {
  local port="$1"
  local pid="$2"
  local url="http://127.0.0.1:$port/health"
  local attempt=0
  local max_attempts=30

  if ! command -v curl >/dev/null 2>&1; then
    echo "    curl not found — waiting 3s for backend startup..."
    sleep 3
    return 0
  fi

  echo "    Waiting for backend at $url ..."
  while (( attempt < max_attempts )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: backend process exited before becoming healthy" >&2
      return 1
    fi
    if curl -sf "$url" >/dev/null 2>&1; then
      echo "    Backend healthy at http://127.0.0.1:$port"
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done

  echo "ERROR: backend did not respond on $url after ${max_attempts} attempts" >&2
  return 1
}

stop_backend_servers "$PORT"

echo "==> Seeding backend if needed..."
(
  cd backend
  dart pub get
  dart run bin/seed.dart
)

echo "==> Starting backend on port $PORT..."
(
  cd backend
  PORT="$PORT" dart run bin/server.dart
) &
BACKEND_PID=$!

cleanup() {
  kill "$BACKEND_PID" 2>/dev/null || true
  stop_port_listeners "$PORT"
}
trap cleanup EXIT INT TERM

wait_for_backend "$PORT" "$BACKEND_PID"

LAN_IP="$(lan_ip)"
if [[ -n "$LAN_IP" ]]; then
  write_android_device_config "$LAN_IP" "$PORT"
else
  echo "    WARNING: could not detect LAN IP for Android USB device config." >&2
  echo "    Create config/development.android.device.json manually with your Mac's IP." >&2
fi

echo "==> Backend running. Press Ctrl+C to stop."
echo "    Health (this machine): http://127.0.0.1:$PORT/health"
if [[ -n "$LAN_IP" ]]; then
  echo "    Health (phone on same Wi‑Fi): http://${LAN_IP}:$PORT/health"
fi
echo "    Launch from VS Code:"
echo "      • main.dart                    — desktop / iOS simulator"
echo "      • main.dart (Android emulator)  — 10.0.2.2"
echo "      • main.dart (Android device)    — USB / physical (LAN IP)"
wait "$BACKEND_PID"
