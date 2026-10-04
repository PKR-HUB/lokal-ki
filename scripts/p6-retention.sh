#!/usr/bin/env bash
# P6: systemd-Timer für die Löschung nach 90 Tagen installieren (PRD 8.11). Idempotent.
set -euo pipefail
SRC="$(dirname "$(readlink -f "$0")")/../etc/systemd/system"
NEU=0
for u in chat-retention.service chat-retention.timer; do
  if ! sudo cmp -s "$SRC/$u" "/etc/systemd/system/$u"; then
    sudo install -m 644 "$SRC/$u" "/etc/systemd/system/$u"
    NEU=1
    echo "$u: Unit installiert"
  fi
done
[ "$NEU" = 1 ] && sudo systemctl daemon-reload
sudo systemctl enable --now chat-retention.timer
systemctl list-timers chat-retention.timer --no-pager
