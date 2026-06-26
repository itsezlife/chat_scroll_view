#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v supabase >/dev/null 2>&1; then
  echo "ERROR: supabase CLI not found. Install: https://supabase.com/docs/guides/cli" >&2
  exit 1
fi

echo "==> Starting Supabase (Docker)..."
supabase start

echo "==> Applying migrations and seed..."
supabase db reset

write_config() {
  local file="$1"
  local url="$2"
  local key="$3"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF
{
  "SUPABASE_URL": "$url",
  "SUPABASE_PUBLISHABLE_KEY": "$key",
  "DEMO_CHAT_ID": "1"
}
EOF
  echo "    Wrote $file"
}

STATUS_ENV="$(supabase status -o env 2>/dev/null || true)"
API_URL="$(echo "$STATUS_ENV" | sed -n 's/^API_URL="\(.*\)"$/\1/p')"
PUBLISHABLE_KEY="$(echo "$STATUS_ENV" | sed -n 's/^PUBLISHABLE_KEY="\(.*\)"$/\1/p')"
ANON_KEY="$(echo "$STATUS_ENV" | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')"
KEY="${PUBLISHABLE_KEY:-$ANON_KEY}"

API_URL="${API_URL:-http://127.0.0.1:54321}"
if [[ -z "$KEY" ]]; then
  echo "WARNING: could not parse publishable/anon key from supabase status." >&2
  echo "         Run: supabase status -o env" >&2
  KEY="REPLACE_ME"
fi

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
LAN_IP="${LAN_IP:-127.0.0.1}"

echo "==> Writing Flutter dart-define configs..."
write_config "config/development.supabase.json" "$API_URL" "$KEY"
write_config "config/development.supabase.android.json" "http://10.0.2.2:54321" "$KEY"
write_config "config/development.supabase.android.device.json" "http://${LAN_IP}:54321" "$KEY"

echo ""
echo "==> Supabase demo stack ready."
echo "    load_chat: ${API_URL}/functions/v1/load_chat"
echo "    Launch Flutter:"
echo "      macOS / iOS Simulator:  flutter run --dart-define-from-file=config/development.supabase.json"
echo "      Android emulator:       flutter run --dart-define-from-file=config/development.supabase.android.json"
echo "      Android USB device:     flutter run --dart-define-from-file=config/development.supabase.android.device.json"
echo ""
echo "    Ensure Supabase is running (supabase start). Phone and Mac must be on the same Wi‑Fi for USB device."
