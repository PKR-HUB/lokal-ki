#!/usr/bin/env bash
# P2: NVIDIA-Treiber (Production Branch 595, offene Kernel-Module, headless). Idempotent.
# Abweichung von der PRD: nvidia-headless-595-open statt nvidia-driver-595-open
# (gleicher Treiber, ohne Xorg/GTK-Desktop-Abhängigkeiten).
# linux-modules-nvidia-595-open-generic liefert vorgebaute Module passend zum Kernel-Metapaket.
set -euo pipefail
PKGS=(nvidia-headless-595-open nvidia-utils-595 linux-modules-nvidia-595-open-generic)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${PKGS[@]}"
dpkg-query -W -f='${Package} ${Version}\n' "${PKGS[@]}"
if [ -e /var/run/reboot-required ]; then echo "NEUSTART ERFORDERLICH"; fi
