#!/usr/bin/env bash
# P4: Caddyfile installieren und Caddy neu laden. Idempotent.
set -euo pipefail
SRC="$(dirname "$(readlink -f "$0")")/../etc/caddy/Caddyfile"
DST=/etc/caddy/Caddyfile
caddy validate --adapter caddyfile --config "$SRC" >/dev/null
if ! sudo cmp -s "$SRC" "$DST"; then
  [ -e "$DST.orig" ] || sudo cp -a "$DST" "$DST.orig"
  sudo install -m 644 "$SRC" "$DST"
  sudo systemctl reload-or-restart caddy
  echo "caddy: Caddyfile installiert"
else
  echo "caddy: bereits aktuell"
fi
sudo systemctl enable caddy >/dev/null
