#!/usr/bin/env bash
# P3: llama-server als systemd-Dienst installieren und starten. Idempotent.
set -euo pipefail
SRC="$(dirname "$(readlink -f "$0")")/../etc/systemd/system/llama-server.service"
DST=/etc/systemd/system/llama-server.service
id llm >/dev/null 2>&1 || sudo useradd -r -s /usr/sbin/nologin llm
if ! sudo cmp -s "$SRC" "$DST"; then
  sudo install -m 644 "$SRC" "$DST"
  sudo systemctl daemon-reload
  sudo systemctl restart llama-server 2>/dev/null || true
  echo "llama-server: Unit installiert"
fi
sudo systemctl enable --now llama-server
for i in $(seq 1 60); do
  curl -fsS http://127.0.0.1:8080/health 2>/dev/null && { echo; exit 0; }
  sleep 5
done
echo "llama-server nicht bereit nach 5 min" >&2; exit 1
