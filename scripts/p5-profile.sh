#!/usr/bin/env bash
# P5: Modell-Profile in Open WebUI auf den Soll-Zustand setzen (Anweisung-Profile.md). Idempotent.
# System-Prompts aus Büro.md, Backoffice.md, Recherche.md, Vorschläge unter dem Chat aus Vorschläge.json
# (alles in der Repo-Wurzel). Nach Änderung:
# git pull und erneut ausführen. Nur bei Abweichung: Sicherung data/webui.db.bak-p5-profile,
# Änderung über Open WebUIs Modell-Klasse, Neustart des Containers, warten auf /health.
set -euo pipefail
cd "$(dirname "$0")/.."

for f in Büro.md Backoffice.md Recherche.md Vorschläge.json; do
  [ -s "$f" ] || { echo "ABBRUCH: $f fehlt oder ist leer" >&2; exit 1; }
done

PROMPTS=$(python3 -c '
import json, sys
d = {k: open(f, encoding="utf-8").read() for k, f in
     (("buero", "Büro.md"), ("backoffice", "Backoffice.md"), ("recherche", "Recherche.md"))}
d["vorschlaege"] = json.load(open("Vorschläge.json", encoding="utf-8"))
print(json.dumps(d))') || { echo "ABBRUCH: Vorschläge.json ist kein gültiges JSON" >&2; exit 1; }

read -r -d '' PY <<'EOF' || true
import asyncio, json, sqlite3, sys, time
from open_webui.models.models import Models, ModelForm
from open_webui.models.users import Users

DB = "/app/backend/data/webui.db"
BAK = "/app/backend/data/webui.db.bak-p5-profile"
prompts = json.loads(sys.stdin.read())
VORSCHLAEGE = prompts["vorschlaege"]

# Einstellungen wie Profil qwen38 (SETUP-LOG P5)
PARAMS = {"temperature": 1.0, "top_p": 0.95, "top_k": 20, "min_p": 0.0,
          "presence_penalty": 0.0, "repeat_penalty": 1.0, "function_calling": "native",
          "custom_params": {"chat_template_kwargs": json.dumps({"reasoning_effort": "medium"})}}
META = {"profile_image_url": None, "background_image_url": None, "i18n": None, "knowledge": None,
        "capabilities": {"vision": True, "file_upload": True, "web_search": True, "image_generation": False,
                         "code_interpreter": True, "citations": True, "status_updates": True,
                         "usage": True, "builtin_tools": True},
        "defaultFeatureIds": ["web_search"]}
ALLE = [("user", "*", "read")]

SOLL = [
    ("qwen38-buero", "Q3.8 Büro", prompts["buero"],
     "Förmliche E-Mails und Briefe, z. B. an Versicherungen, IHK, Berufsschule, Handwerker."),
    ("qwen38-backoffice", "Q3.8 Backoffice", prompts["backoffice"],
     "Kundenanfragen prüfen, Kalkulation vorbereiten, Angebote und Kunden-E-Mails entwerfen."),
    ("qwen38-recherche", "Q3.8 Recherche", prompts["recherche"],
     "Ausarbeitungen und Schulungen: erst klären, dann mit Quellen recherchieren."),
    ("qwen38", "Q3.8 None", None,
     "Ohne Vorgaben. Eigene Anweisung als erste Nachricht schreiben."),
]
ORDER = ["qwen38-buero", "qwen38-backoffice", "qwen38-recherche", "qwen38", "qwen38-code"]
DEFAULT = "qwen38"

def soll_form(mid, name, system, desc):
    params = dict(PARAMS)
    if system is not None:
        params["system"] = system
    meta = {**META, "description": desc, "suggestion_prompts": VORSCHLAEGE.get(mid)}
    return dict(id=mid, base_model_id="qwen3.8-27b", name=name, params=params, meta=meta,
                is_active=True)

def ist_form(x):
    return dict(id=x.id, base_model_id=x.base_model_id, name=x.name, params=x.params.model_dump(),
                meta=x.meta.model_dump(), is_active=x.is_active)

def grants(x):
    return sorted((g.principal_type, g.principal_id, g.permission) for g in x.access_grants)

async def main():
    con = sqlite3.connect(DB)
    cfg = {k: json.loads(v) for k, v in con.execute(
        "select key, value from config where key in "
        "('ui.model_order_list', 'ui.default_models', 'ui.prompt_suggestions')")}
    aenderungen = []
    for mid, name, system, desc in SOLL:
        x = await Models.get_model_by_id(mid)
        if x is None:
            aenderungen.append(("neu", mid, soll_form(mid, name, system, desc)))
        elif ist_form(x) != soll_form(mid, name, system, desc) or grants(x) != ALLE:
            aenderungen.append(("ändern", mid, soll_form(mid, name, system, desc)))
    order_neu = cfg.get("ui.model_order_list") != ORDER
    default_neu = cfg.get("ui.default_models") != DEFAULT
    vorschlag_neu = cfg.get("ui.prompt_suggestions") != VORSCHLAEGE["allgemein"]

    if not aenderungen and not order_neu and not default_neu and not vorschlag_neu:
        print("UNVERAENDERT")
        return

    bak = sqlite3.connect(BAK); con.backup(bak); bak.close()
    print(f"Sicherung {BAK}")
    users = await Users.get_users()
    users = users["users"] if isinstance(users, dict) else users
    admin = next(u for u in users if u.role == "admin")
    acl = [{"principal_type": t, "principal_id": p, "permission": r} for t, p, r in ALLE]
    for art, mid, form in aenderungen:
        f = ModelForm(**form, access_grants=acl)
        r = await Models.insert_new_model(f, admin.id) if art == "neu" else await Models.update_model_by_id(mid, f)
        if r is None:
            sys.exit(f"FEHLER beim Speichern von {mid}")
        print(f"{art}: {mid} ({form['name']})")
    now = int(time.time())
    for key, val, neu in (("ui.model_order_list", ORDER, order_neu), ("ui.default_models", DEFAULT, default_neu),
                          ("ui.prompt_suggestions", VORSCHLAEGE["allgemein"], vorschlag_neu)):
        if neu:
            con.execute("update config set value = ?, updated_at = ? where key = ?", (json.dumps(val), now, key))
            print(f"{key} = {json.dumps(val, ensure_ascii=False)[:120]}")
    con.commit()
    print("GEAENDERT")

asyncio.run(main())
EOF

OUT=$(printf '%s' "$PROMPTS" | sudo docker exec -i -w /app/backend open-webui python3 -c "$PY" 2>&1) \
  || { echo "$OUT" >&2; echo "ABBRUCH: Profile nicht gesetzt" >&2; exit 1; }
echo "$OUT" | grep -E '^(Sicherung|neu:|ändern:|ui\.)' || true

if [ "$(echo "$OUT" | tail -n1)" = "UNVERAENDERT" ]; then
  echo "Profile bereits im Soll-Zustand, nichts geändert."
  exit 0
fi

echo "Starte Open WebUI neu …"
sudo docker compose restart open-webui >/dev/null
for i in $(seq 1 60); do
  curl -fsS http://127.0.0.1:3000/health 2>/dev/null && { echo; exit 0; }
  sleep 5
done
echo "Open WebUI nicht bereit nach 5 min" >&2; exit 1
