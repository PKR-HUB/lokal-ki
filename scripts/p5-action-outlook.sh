#!/usr/bin/env bash
# P5: Action-Funktion "Für Outlook kopieren" (owui/actions/outlook-kopieren.py) in Open WebUI setzen. Idempotent.
# Die Funktion ist aktiv, aber nicht global; am Profil Q3.8 Backoffice hängt sie über
# meta.actionIds, das setzt scripts/p5-profile.sh (wird am Ende aufgerufen).
# Nur bei Abweichung: Sicherung data/webui.db.bak-p5-action-outlook, Neustart, warten auf /health.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=owui/actions/outlook-kopieren.py
[ -s "$SRC" ] || { echo "ABBRUCH: $SRC fehlt oder ist leer" >&2; exit 1; }
python3 -c "import ast, sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$SRC" || { echo "ABBRUCH: $SRC ist kein gültiges Python" >&2; exit 1; }

read -r -d '' PY <<'EOF' || true
import asyncio, sqlite3, sys
from open_webui.models.functions import Functions, FunctionForm, FunctionMeta
from open_webui.models.users import Users
from open_webui.utils.plugin import extract_frontmatter, replace_imports

DB = "/app/backend/data/webui.db"
BAK = "/app/backend/data/webui.db.bak-p5-action-outlook"
FID = "outlook_kopieren"
content = replace_imports(sys.stdin.read())
fm = extract_frontmatter(content)
NAME = fm.get("title", "Für Outlook kopieren")
META = {"description": fm.get("description"), "manifest": fm}

async def main():
    f = await Functions.get_function_by_id(FID)
    soll = dict(name=NAME, type="action", content=content, meta=META, is_active=True, is_global=False)
    if f is not None:
        ist = dict(name=f.name, type=f.type, content=f.content, meta=f.meta.model_dump(),
                   is_active=f.is_active, is_global=bool(f.is_global))
        if ist == soll:
            print("UNVERAENDERT")
            return
    con = sqlite3.connect(DB)
    bak = sqlite3.connect(BAK); con.backup(bak); bak.close(); con.close()
    print(f"Sicherung {BAK}")
    if f is None:
        users = await Users.get_users()
        users = users["users"] if isinstance(users, dict) else users
        admin = next(u for u in users if u.role == "admin")
        r = await Functions.insert_new_function(
            admin.id, "action", FunctionForm(id=FID, name=NAME, content=content, meta=FunctionMeta(**META)))
        if r is None:
            sys.exit("FEHLER beim Anlegen der Funktion")
        print(f"neu: {FID} ({NAME})")
    else:
        print(f"ändern: {FID} ({NAME})")
    r = await Functions.update_function_by_id(
        FID, {"name": NAME, "type": "action", "content": content, "meta": META,
              "is_active": True, "is_global": False})
    if r is None:
        sys.exit("FEHLER beim Speichern der Funktion")
    print("GEAENDERT")

asyncio.run(main())
EOF

OUT=$(sudo docker exec -i -w /app/backend open-webui python3 -c "$PY" < "$SRC" 2>&1) \
  || { echo "$OUT" >&2; echo "ABBRUCH: Funktion nicht gesetzt" >&2; exit 1; }
echo "$OUT" | grep -E '^(Sicherung|neu:|ändern:)' || true
GEAENDERT=0
[ "$(echo "$OUT" | tail -n1)" = "GEAENDERT" ] && GEAENDERT=1

# Am Profil Q3.8 Backoffice einhängen (startet bei Änderung selbst neu)
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
[ "$GEAENDERT" = 1 ] || echo "Funktion bereits im Soll-Zustand."
