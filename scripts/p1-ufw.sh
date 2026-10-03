#!/usr/bin/env bash
# P1: Firewall (PRD 8.8 / N-SEC-01). Idempotent.
# Abweichung von der PRD: SSH aus dem ganzen Büronetz statt nur von ADMIN_IP.
# Aufruf: p1-ufw.sh <BUERO_SUBNETZ>
set -euo pipefail
BUERO_SUBNETZ="${1:?BUERO_SUBNETZ fehlt}"
sudo ufw default deny incoming
sudo ufw default allow outgoing
# SSH-Regel immer VOR ufw enable
sudo ufw allow from "$BUERO_SUBNETZ" to any port 22 proto tcp comment 'SSH Buero'
sudo ufw allow from "$BUERO_SUBNETZ" to any port 443 proto tcp comment 'HTTPS Buero'
sudo ufw --force enable
sudo ufw status verbose
