#!/usr/bin/env bash
# P4: /srv/ki/.env anlegen (nur wenn noch nicht vorhanden). Idempotent.
# Erzeugt WEBUI_SECRET_KEY zufällig; BRAVE_SEARCH_API_KEY trägt der Admin selbst ein.
# Inhalt wird nicht ausgegeben (PRD 9.3 Regel 7).
set -euo pipefail
ENV=/srv/ki/.env
if [ -e "$ENV" ]; then
  echo ".env existiert bereits – unverändert"
else
  umask 077
  {
    echo "WEBUI_SECRET_KEY=$(openssl rand -hex 32)"
    echo "BRAVE_SEARCH_API_KEY="
  } > "$ENV"
  echo ".env angelegt"
fi
chmod 600 "$ENV"
stat -c '%n %a %U:%G %s Byte' "$ENV"
