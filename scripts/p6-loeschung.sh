#!/usr/bin/env bash
# P6: Chats nach 90 Tagen ohne Aktivität löschen, dazu hochgeladene Dateien, die nirgends mehr
# verwendet werden (PRD 8.11, F-UI-10). Ebenso Bewertungen (feedback), weil sie eine Kopie des Chats
# enthalten. Läuft täglich über chat-retention.timer.
# Wissensdatenbanken und ihre Dateien bleiben. Ins Journal gehen nur Anzahlen, keine Inhalte.
# Aufruf: p6-loeschung.sh [--probelauf]   (Probelauf: nur zählen, nichts löschen)
# Umgebung: TAGE (Standard 90)
set -euo pipefail
TAGE="${TAGE:-90}"
PROBELAUF=0
[ "${1:-}" = "--probelauf" ] && PROBELAUF=1

read -r -d '' PY <<'EOF' || true
# Löscht über Open WebUIs eigene Modell-Klassen, wie DELETE /api/v1/chats/{id} und /api/v1/files/{id}.
import asyncio, os, sqlite3, time
from open_webui.models.chats import Chats
from open_webui.models.files import Files
from open_webui.models.feedbacks import Feedbacks
from open_webui.storage.provider import Storage
from open_webui.retrieval.vector.async_client import ASYNC_VECTOR_DB_CLIENT

DB = "/app/backend/data/webui.db"
TAGE = int(os.environ["TAGE"])
PROBE = os.environ["PROBELAUF"] == "1"
GRENZE = int(time.time()) - TAGE * 86400

def text_spalten(con):
    """Alle Text-/JSON-Spalten außer file und chat_file: dort kann eine Datei-ID verwendet werden."""
    out = []
    for (t,) in con.execute("select name from sqlite_master where type='table'"):
        if t in ("file", "chat_file", "alembic_version") or t.startswith("sqlite_"):
            continue
        for _, col, typ, *_ in con.execute(f'pragma table_info("{t}")'):
            if typ.upper() in ("TEXT", "JSON", "VARCHAR", "") or "CHAR" in typ.upper():
                out.append((t, col))
    return out

async def main():
    con = sqlite3.connect(DB)
    # 1) Chats: letzte Änderung älter als die Frist. Interne Kind-Chats gehen mit ihrem Eltern-Chat.
    alt = con.execute("select id, user_id, json_extract(meta, '$.internal'), "
                      "json_extract(meta, '$.parent_chat_id'), meta from chat where updated_at < ?", (GRENZE,)).fetchall()
    alle = {r[0] for r in con.execute("select id from chat")}
    alt_ids = {r[0] for r in alt}
    chats = kinder = 0
    for cid, uid, internal, parent, _ in alt:
        if internal and parent in alle and parent not in alt_ids:
            continue  # Eltern-Chat noch aktiv
        if internal and parent in alt_ids:
            continue  # wird mit dem Eltern-Chat gelöscht
        chats += 1
        if PROBE:
            continue
        chat = await Chats.get_chat_by_id(cid)
        if not chat:
            continue
        await Chats.delete_orphan_tags_for_user(chat.meta.get("tags", []), uid, threshold=1)
        for kid in await Chats.get_internal_chat_ids_by_parent_id(cid, uid):
            await Chats.delete_chat_by_id_and_user_id(kid, uid)
            kinder += 1
        if not await Chats.delete_chat_by_id(cid):
            raise SystemExit(f"FEHLER: Chat {cid} nicht gelöscht")

    # Verknüpfungen zu nicht mehr vorhandenen Chats entfernen (SQLite-Kaskaden sind aus)
    # und zu gelöschten Wissensdatenbanken (bleiben in v0.11.4 beim Löschen einer Wissensdatenbank stehen)
    verwaist = 0
    for sql in ("from chat_file where chat_id not in (select id from chat)",
                "from knowledge_file where knowledge_id not in (select id from knowledge)"):
        verwaist += con.execute("select count(*) " + sql).fetchone()[0]
        if not PROBE:
            con.execute("delete " + sql)
    con.commit()

    # 2) Bewertungen: enthalten eine Kopie des Chats (snapshot), werden beim Löschen des Chats nicht entfernt
    bewertungen = 0
    for (fbid,) in con.execute("select id from feedback where updated_at < ?", (GRENZE,)).fetchall():
        bewertungen += 1
        if not PROBE and not await Feedbacks.delete_feedback_by_id(id=fbid):
            raise SystemExit(f"FEHLER: Bewertung {fbid} nicht gelöscht")

    # 3) Dateien: älter als die Frist und nirgends mehr verwendet (kein Chat, keine Wissensdatenbank,
    #    kein Ordner, keine Notiz, kein Modell). Geprüft wird nur, ob die ID vorkommt, nicht der Inhalt.
    spalten = text_spalten(con)
    dateien = 0
    for fid, path in con.execute("select id, path from file where created_at < ?", (GRENZE,)).fetchall():
        if con.execute("select 1 from chat_file where file_id = ? and chat_id in (select id from chat) limit 1",
                       (fid,)).fetchone():
            continue
        if any(con.execute(f'select 1 from "{t}" where "{c}" like ? limit 1', (f"%{fid}%",)).fetchone()
               for t, c in spalten):
            continue
        dateien += 1
        if PROBE:
            continue
        if not await Files.delete_file_by_id(fid):
            raise SystemExit(f"FEHLER: Datei {fid} nicht gelöscht")
        try:
            if path:
                await asyncio.to_thread(Storage.delete_file, path)
        except Exception as e:
            print(f"Hinweis: Speicher für Datei {fid}: {type(e).__name__}")

    # 4) Vektor-Sammlungen file-<id> ohne Datei entfernen. Open WebUI v0.11.4 ruft beim Löschen einer
    #    Datei delete() ohne IDs auf, das löscht nichts; Textstücke und Embeddings blieben sonst liegen.
    vorhanden = {r[0] for r in con.execute("select id from file")}
    vektoren = 0
    sync = ASYNC_VECTOR_DB_CLIENT.sync
    for col in sync.client.list_collections():
        name = getattr(col, "name", col)
        if name.startswith("file-") and name[5:] not in vorhanden:
            vektoren += 1
            if not PROBE:
                await ASYNC_VECTOR_DB_CLIENT.delete_collection(name)

    art = "Probelauf, nichts gelöscht" if PROBE else "gelöscht"
    print(f"chat-retention ({TAGE} Tage, {art}): Chats {chats}, Kind-Chats {kinder}, "
          f"Datei-Verknüpfungen {verwaist}, Bewertungen {bewertungen}, Dateien {dateien}, "
          f"Vektor-Sammlungen {vektoren}")

asyncio.run(main())
EOF

OUT=$(docker exec -i -w /app/backend -e TAGE="$TAGE" -e PROBELAUF="$PROBELAUF" open-webui python3 -c "$PY" 2>&1) \
  || { echo "$OUT" | grep -E '^(FEHLER|Traceback|[A-Za-z]*Error)' >&2 || true; echo "ABBRUCH: Löschlauf fehlgeschlagen" >&2; exit 1; }
echo "$OUT" | grep -E '^(chat-retention|Hinweis)'
