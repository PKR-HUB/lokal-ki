#!/usr/bin/env bash
# P4: Docker (Ubuntu-Pakete) und Caddy installieren. Idempotent.
set -euo pipefail
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q docker.io docker-compose-v2 caddy
sudo systemctl enable --now docker
dpkg-query -W -f='${Package} ${Version}\n' docker.io docker-compose-v2 caddy
