#!/usr/bin/env bash
# P4: Caddy aus dem offiziellen Repo (dl.cloudsmith.io, stable) statt aus Ubuntu. Idempotent.
# Anleitung: https://caddyserver.com/docs/install#debian-ubuntu-raspbian
set -euo pipefail
key=/usr/share/keyrings/caddy-stable-archive-keyring.gpg
list=/etc/apt/sources.list.d/caddy-stable.list

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q debian-keyring debian-archive-keyring apt-transport-https curl gpg
if [ ! -f "$key" ]; then
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o "$key"
	echo "Schlüssel $key angelegt"
fi
if [ ! -f "$list" ]; then
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee "$list" >/dev/null
	echo "Paketquelle $list angelegt"
fi
sudo chmod o+r "$key" "$list"
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q -o Dpkg::Options::=--force-confold caddy

sudo -u caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl restart caddy
systemctl is-active caddy
caddy version
