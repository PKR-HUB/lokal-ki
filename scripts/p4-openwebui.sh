#!/usr/bin/env bash
# P4: Open WebUI per Docker Compose starten und auf Bereitschaft warten. Idempotent.
set -euo pipefail
cd /srv/ki
[ -e .env ] || { echo "ABBRUCH: /srv/ki/.env fehlt (scripts/p4-env.sh)" >&2; exit 1; }
sudo docker compose up -d
for i in $(seq 1 60); do
  curl -fsS http://127.0.0.1:3000/health 2>/dev/null && { echo; exit 0; }
  sleep 5
done
echo "Open WebUI nicht bereit nach 5 min" >&2; exit 1
