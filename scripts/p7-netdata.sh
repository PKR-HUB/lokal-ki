#!/usr/bin/env bash
# P7: Netdata aus dem offiziellen Paketarchiv installieren und konfigurieren. Idempotent.
# Ohne Journal- und Netzwerk-Viewer (keine Log-Inhalte im Dashboard), ohne Cloud-Anmeldung,
# ohne anonyme Statistiken. Danach: scripts/p4-caddy.sh (Freigabe unter /netdata/).
set -euo pipefail
ETC="$(dirname "$(readlink -f "$0")")/../etc"

geaendert=0
inst() { # inst <quelle> <ziel> <modus>
  if ! sudo cmp -s "$1" "$2"; then sudo install -D -m "$3" "$1" "$2"; geaendert=1; fi
}
inst "$ETC/apt/keyrings/netdata.gpg" /etc/apt/keyrings/netdata.gpg 644
inst "$ETC/apt/sources.list.d/netdata.sources" /etc/apt/sources.list.d/netdata.sources 644
[ "$geaendert" -eq 0 ] || sudo apt-get update -q

sudo mkdir -p /etc/netdata
sudo touch /etc/netdata/.opt-out-from-anonymous-statistics
if ! dpkg -s netdata >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    netdata netdata-plugin-systemd-units
fi

geaendert=0
inst "$ETC/netdata/netdata.conf" /etc/netdata/netdata.conf 644
if [ "$geaendert" -eq 1 ]; then
  sudo systemctl restart netdata
  echo "netdata: Konfiguration installiert, neu gestartet"
else
  echo "netdata: bereits aktuell"
fi
sudo systemctl enable netdata >/dev/null

for i in $(seq 1 30); do
  curl -fs -o /dev/null http://127.0.0.1:19999/api/v1/info && break; sleep 1
done
curl -fsS -o /dev/null http://127.0.0.1:19999/api/v1/info
if sudo ss -tlnH | awk '{print $4}' | grep -qE '(^|[^.0-9])(0\.0\.0\.0|\*|\[::\]):19999$'; then
  echo "FEHLER: Netdata lauscht nicht nur lokal" >&2; exit 1
fi
[ -e /etc/caddy/netdata-auth.caddy ] || echo "Hinweis: noch kein Passwort – sudo scripts/p7-netdata-passwort.sh"
echo "netdata: läuft auf 127.0.0.1:19999"
