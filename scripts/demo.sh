#!/usr/bin/env bash
# Run the whole demo on this laptop: Firebase emulators, backend, seed data and dashboard.
# A phone on the same Wi-Fi (or this laptop on the phone's hotspot) reaches it by the laptop's IP.
# Usage: scripts/demo.sh          Stop: Ctrl+C (stops everything)
set -euo pipefail
cd "$(dirname "$0")/.."

IP=${IP:-$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')}
[ -n "$IP" ] || { echo "No network IP found. Join Wi-Fi or a hotspot, or run IP=x.x.x.x $0"; exit 1; }
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"  # the emulators need Java

trap 'kill 0' EXIT
(cd firebase && firebase emulators:start --project demo-gosafe >/tmp/gosafe-emulators.log 2>&1) &
echo "Starting emulators (log: /tmp/gosafe-emulators.log)..."
until curl -s -o /dev/null 127.0.0.1:8080 && curl -s -o /dev/null 127.0.0.1:9199; do sleep 1; done

cd backend
set -a; . ./.env.example; [ -f .env ] && . ./.env; set +a  # .env: your own secrets, e.g. R2 keys
# Upload and playback links point here, so they must use the IP the phone can reach.
export FIREBASE_STORAGE_EMULATOR_HOST="$IP:9199"
uv run python -m scripts.seed >/dev/null
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 >/tmp/gosafe-backend.log 2>&1 &
cd ../dashboard
NEXT_PUBLIC_USE_EMULATORS=true NEXT_PUBLIC_FIREBASE_API_KEY=demo-key NEXT_PUBLIC_FIREBASE_PROJECT_ID=demo-gosafe \
  NEXT_PUBLIC_API_URL=http://localhost:8000 npm run dev >/tmp/gosafe-dashboard.log 2>&1 &

cat <<EOF

GoSafe is running on this laptop ($IP).
  Dashboard:  http://localhost:3000   (agent login: agent1@gosafe.test, password = SEED_PASSWORD in backend/.env.example)
  Backend:    http://$IP:8000/health
  Phone app:  cd mobile && flutter run --dart-define=EMULATOR_HOST=$IP --dart-define=API_URL=http://$IP:8000
Logs in /tmp/gosafe-*.log. Ctrl+C stops everything (emulator data is wiped).
EOF
wait
