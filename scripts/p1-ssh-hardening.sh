#!/usr/bin/env bash
# P1: SSH-Härtung (nur Schlüssel, kein Root-Login). Idempotent.
# Bricht ab, wenn der aufrufende Benutzer keinen hinterlegten Schlüssel hat.
set -euo pipefail
SRC="$(dirname "$(readlink -f "$0")")/../etc/ssh/sshd_config.d/10-ki-hardening.conf"
DST=/etc/ssh/sshd_config.d/10-ki-hardening.conf
AK="${HOME}/.ssh/authorized_keys"
if ! grep -qE '^(ssh-|ecdsa-|sk-)' "$AK" 2>/dev/null; then
  echo "ABBRUCH: kein Schlüssel in $AK – Passwort-Login bleibt aktiv." >&2
  exit 1
fi
if ! sudo cmp -s "$SRC" "$DST"; then
  sudo install -m 644 "$SRC" "$DST"
  sudo sshd -t
  sudo systemctl reload ssh
  echo "ssh: Härtung installiert"
else
  echo "ssh: bereits aktuell"
fi
sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin) '
