#!/usr/bin/env bash
# P4: Caddyfile installieren und Caddy neu laden. Idempotent.
set -euo pipefail
SRC="$(dirname "$(readlink -f "$0")")/../etc/caddy/Caddyfile"
DST=/etc/caddy/Caddyfile
CSS_SRC="$(dirname "$(readlink -f "$0")")/../etc/caddy/owui/custom.css"
CSS_DST=/etc/caddy/owui/custom.css
# Stylesheet für Open WebUI (wird ohne Neuladen sofort ausgeliefert)
if ! sudo cmp -s "$CSS_SRC" "$CSS_DST"; then
  sudo install -D -m 644 "$CSS_SRC" "$CSS_DST"
  echo "caddy: owui/custom.css installiert"
fi
# GPU-Übersicht unter /netdata/gpu/ (P7)
GPU_SRC="$(dirname "$(readlink -f "$0")")/../etc/caddy/netdata-gpu/index.html"
GPU_DST=/etc/caddy/netdata-gpu/index.html
if ! sudo cmp -s "$GPU_SRC" "$GPU_DST"; then
  sudo install -D -m 644 "$GPU_SRC" "$GPU_DST"
  echo "caddy: netdata-gpu/index.html installiert"
fi
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
