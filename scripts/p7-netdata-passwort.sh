#!/usr/bin/env bash
# P7: Passwort für Netdata (https://192.168.10.129/netdata/) setzen oder ändern.
# Benutzername: admin. Fragt das Passwort ab, speichert nur den bcrypt-Hash.
# Aufruf am Server: sudo scripts/p7-netdata-passwort.sh
set -euo pipefail
DST=/etc/caddy/netdata-auth.caddy
[ "$(id -u)" -eq 0 ] || { echo "Bitte mit sudo aufrufen." >&2; exit 1; }
read -rsp "Neues Netdata-Passwort für admin: " PW1; echo
read -rsp "Passwort wiederholen: " PW2; echo
[ "$PW1" = "$PW2" ] || { echo "Passwörter stimmen nicht überein." >&2; exit 1; }
[ "${#PW1}" -ge 10 ] || { echo "Bitte mindestens 10 Zeichen." >&2; exit 1; }
HASH=$(printf '%s\n' "$PW1" | caddy hash-password)
umask 022
printf 'basicauth {\n\tadmin %s\n}\n' "$HASH" > "$DST.neu"
install -m 644 "$DST.neu" "$DST" && rm -f "$DST.neu"
systemctl reload caddy
echo "netdata: Passwort gesetzt (Benutzer admin)"
