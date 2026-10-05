#!/usr/bin/env bash
# P5: "Formatierten Text kopieren" für alle Nutzer einschalten. Idempotent.
# Vorgabe für alle (auch künftige) Konten: Schlüssel copyFormatted in der Konfiguration
# ui.default_interface_settings (Open WebUI v0.11.4, Admin-Bereich → Oberfläche, Standardwerte).
# Konten, die den Schalter selbst ausgeschaltet haben (settings.ui.copyFormatted = false),
# werden auf true gesetzt. Alle anderen Einstellungen bleiben unverändert.
# Nur bei Abweichung: Sicherung data/webui.db.bak-p5-kopieren, Neustart, warten auf /health.
set -euo pipefail
cd "$(dirname "$0")/.."

read -r -d '' PY <<'EOF' || true
import json, sqlite3, time

DB = "/app/backend/data/webui.db"
BAK = "/app/backend/data/webui.db.bak-p5-kopieren"
KEY = "ui.default_interface_settings"

con = sqlite3.connect(DB)
row = con.execute("select value from config where key = ?", (KEY,)).fetchone()
vorgabe = (json.loads(row[0]) if row else None) or {}
vorgabe_neu = vorgabe.get("copyFormatted") is not True

# Nur die Einstellungen lesen, keine Chat-Inhalte
nutzer = []
for uid, s in con.execute("select id, settings from user"):
    settings = (json.loads(s) if s else None) or {}
    ui = settings.get("ui") or {}
    nutzer.append((uid, settings, ui))
aus = [(uid, settings, ui) for uid, settings, ui in nutzer if ui.get("copyFormatted") is False]

if vorgabe_neu or aus:
    bak = sqlite3.connect(BAK); con.backup(bak); bak.close()
    print(f"Sicherung {BAK}")
    now = int(time.time())
    if vorgabe_neu:
        vorgabe["copyFormatted"] = True
        if row:
            con.execute("update config set value = ?, updated_at = ? where key = ?", (json.dumps(vorgabe), now, KEY))
        else:
            con.execute("insert into config (key, value, created_at, updated_at) values (?, ?, ?, ?)",
                        (KEY, json.dumps(vorgabe), now, now))
        print(f"{KEY} = {json.dumps(vorgabe)}")
    for uid, settings, ui in aus:
        ui["copyFormatted"] = True
        settings["ui"] = ui
        con.execute("update user set settings = ? where id = ?", (json.dumps(settings), uid))
    if aus:
        print(f"Konten vom Nutzer ausgeschaltet, jetzt eingeschaltet: {len(aus)}")
    con.commit()

# Wirksamer Wert je Konto: eigener Wert, sonst die Vorgabe
an = sum(1 for _, _, ui in nutzer if (ui.get("copyFormatted") if ui.get("copyFormatted") is not None
                                      else vorgabe.get("copyFormatted")) is True)
print(f"Konten gesamt: {len(nutzer)}, Schalter wirksam an: {an}")
print("GEAENDERT" if vorgabe_neu or aus else "UNVERAENDERT")
EOF

OUT=$(sudo docker exec -i -w /app/backend open-webui python3 -c "$PY" 2>&1) \
  || { echo "$OUT" >&2; echo "ABBRUCH: Einstellung nicht gesetzt" >&2; exit 1; }
echo "$OUT" | grep -E '^(Sicherung|ui\.|Konten)' || true

if [ "$(echo "$OUT" | tail -n1)" = "UNVERAENDERT" ]; then
  echo "Bereits im Soll-Zustand, nichts geändert."
  exit 0
fi

echo "Starte Open WebUI neu …"
sudo docker compose restart open-webui >/dev/null
for i in $(seq 1 60); do
  curl -fsS http://127.0.0.1:3000/health 2>/dev/null && { echo; exit 0; }
  sleep 5
done
echo "Open WebUI nicht bereit nach 5 min" >&2; exit 1
