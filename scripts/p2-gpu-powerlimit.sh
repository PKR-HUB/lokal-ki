#!/usr/bin/env bash
# P2: systemd-Dienst für das GPU-Leistungslimit (PRD 8.5 / N-OPS-04). Idempotent.
set -euo pipefail
SRC="$(dirname "$(readlink -f "$0")")/../etc/systemd/system/gpu-powerlimit.service"
DST=/etc/systemd/system/gpu-powerlimit.service
if ! sudo cmp -s "$SRC" "$DST"; then
  sudo install -m 644 "$SRC" "$DST"
  sudo systemctl daemon-reload
  echo "gpu-powerlimit: Unit installiert"
fi
sudo systemctl enable gpu-powerlimit.service
