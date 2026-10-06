#!/usr/bin/env bash
# P5: Knöpfe unter der Antwort ausblenden, die im Büro keinen Nutzen haben. Idempotent.
# - Bewerten (Daumen hoch/runter): global aus, auch für Admins (Konfiguration ui.enable_message_rating).
# - Vorlesen und Antwort fortsetzen: Nutzerrechte user.permissions.chat.tts und .continue_response aus.
#   Gruppen, die eines davon erlauben, werden ebenfalls auf false gesetzt (sonst gilt der erlaubende Wert).
#   Konten mit Rolle admin sehen beide Knöpfe weiterhin (Open WebUI v0.11.4, ResponseMessage.svelte).
# - Knopf "Für Outlook kopieren": Action-Funktion outlook_kopieren löschen; den Verweis am Profil
#   Q3.8 Backoffice (meta.actionIds) entfernt scripts/p5-profile.sh (wird am Ende aufgerufen).
# Nur bei Abweichung: Sicherung data/webui.db.bak-p5-knoepfe, Neustart, warten auf /health.
set -euo pipefail
cd "$(dirname "$0")/.."

read -r -d '' PY <<'EOF' || true
import asyncio, json, sqlite3, time
from open_webui.models.functions import Functions

DB = "/app/backend/data/webui.db"
BAK = "/app/backend/data/webui.db.bak-p5-knoepfe"
RECHTE_AUS = ("tts", "continue_response")
FID = "outlook_kopieren"

async def main():
    con = sqlite3.connect(DB)
    cfg = {k: json.loads(v) for k, v in con.execute(
        "select key, value from config where key in ('ui.enable_message_rating', 'user.permissions')")}
    rating_neu = cfg.get("ui.enable_message_rating") is not False
    perm = cfg.get("user.permissions")
    if not isinstance(perm, dict):
        raise SystemExit("FEHLER: user.permissions nicht in der Konfiguration")
    chat = perm.setdefault("chat", {})
    perm_neu = [r for r in RECHTE_AUS if chat.get(r) is not False]
    # Nur die Rechte der Gruppen lesen, keine Mitglieder oder Inhalte
    gruppen = []
    for gid, name, p in con.execute('select id, name, permissions from "group"'):
        p = (json.loads(p) if p else None) or {}
        if any((p.get("chat") or {}).get(r) is True for r in RECHTE_AUS):
            gruppen.append((gid, name, p))
    funktion = await Functions.get_function_by_id(FID)

    if not (rating_neu or perm_neu or gruppen or funktion):
        print("UNVERAENDERT")
        return

    bak = sqlite3.connect(BAK); con.backup(bak); bak.close()
    print(f"Sicherung {BAK}")
    now = int(time.time())
    if rating_neu:
        con.execute("update config set value = ?, updated_at = ? where key = ?",
                    (json.dumps(False), now, "ui.enable_message_rating"))
        print("ui.enable_message_rating = false")
    if perm_neu:
        for r in perm_neu:
            chat[r] = False
        con.execute("update config set value = ?, updated_at = ? where key = ?",
                    (json.dumps(perm), now, "user.permissions"))
        print("user.permissions.chat: " + ", ".join(f"{r} = false" for r in perm_neu))
    for gid, name, p in gruppen:
        for r in RECHTE_AUS:
            if (p.get("chat") or {}).get(r) is True:
                p["chat"][r] = False
        con.execute('update "group" set permissions = ? where id = ?', (json.dumps(p), gid))
        print(f"Gruppe {name}: tts/continue_response = false")
    con.commit()
    con.close()
    if funktion:
        if not await Functions.delete_function_by_id(FID):
            raise SystemExit(f"FEHLER beim Löschen der Funktion {FID}")
        print(f"Funktion {FID} gelöscht")
    print("GEAENDERT")

asyncio.run(main())
EOF

OUT=$(sudo docker exec -i -w /app/backend open-webui python3 -c "$PY" 2>&1) \
  || { echo "$OUT" >&2; echo "ABBRUCH: Knöpfe nicht geändert" >&2; exit 1; }
echo "$OUT" | grep -E '^(Sicherung|ui\.|user\.|Gruppe|Funktion)' || true
GEAENDERT=0
[ "$(echo "$OUT" | tail -n1)" = "GEAENDERT" ] && GEAENDERT=1

# Verweis auf den Outlook-Knopf am Profil entfernen (startet bei Änderung selbst neu)
PROFIL=$(scripts/p5-profile.sh)
echo "$PROFIL"

if [ "$GEAENDERT" = 1 ] && echo "$PROFIL" | grep -q "nichts geändert"; then
  echo "Starte Open WebUI neu …"
  sudo docker compose restart open-webui >/dev/null
  for i in $(seq 1 60); do
    curl -fsS http://127.0.0.1:3000/health 2>/dev/null && { echo; exit 0; }
    sleep 5
  done
  echo "Open WebUI nicht bereit nach 5 min" >&2; exit 1
fi
[ "$GEAENDERT" = 1 ] || echo "Knöpfe bereits im Soll-Zustand."
