#!/usr/bin/env bash
# P1: journald-Begrenzung (30 Tage, max. 1 GB) installieren. Idempotent.
set -euo pipefail
SRC="$(dirname "$(readlink -f "$0")")/../etc/systemd/journald.conf.d/retention.conf"
DST=/etc/systemd/journald.conf.d/retention.conf
sudo install -d -m 755 /etc/systemd/journald.conf.d
if ! sudo cmp -s "$SRC" "$DST"; then
  sudo install -m 644 "$SRC" "$DST"
  sudo systemctl restart systemd-journald
  echo "journald: Konfiguration installiert"
else
  echo "journald: bereits aktuell"
fi
