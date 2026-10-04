# Anweisung: Modell-Profile in Open WebUI neu ordnen

Auftrag des Admins vom 2026-10-04 an den Agenten auf dem KI-Server. Es gelten `CLAUDE.md` und die Arbeitsweise aus SETUP-LOG P5 (Sicherung der `webui.db` vor dem Eingriff, Open WebUIs eigene Modell-Klasse, danach Neustart des Containers).

## Ziel

Die Nutzer sollen zwischen vier Profilen wählen, je nach Aufgabe. Der System-Prompt gehört fest zum Profil. Nutzer können ihn weder sehen noch ändern und auch keine Parameter verstellen. Wer eigene Vorgaben braucht, nimmt „Q3.8 None“ und schreibt seine Anweisung als erste Nachricht in den Chat. Das Coding-Profil bleibt dem Admin vorbehalten.

## Soll-Zustand

| Reihenfolge | Name | ID | System-Prompt | Sichtbar für | Websuche |
|---|---|---|---|---|---|
| 1 | Q3.8 Büro | `qwen38-buero` | Inhalt von `Büro.md` | alle Nutzer | vorausgewählt |
| 2 | Q3.8 Backoffice | `qwen38-backoffice` | Inhalt von `Backoffice.md` | alle Nutzer | vorausgewählt |
| 3 | Q3.8 Recherche | `qwen38-recherche` | Inhalt von `Recherche.md` | alle Nutzer | vorausgewählt |
| 4 | Q3.8 None | `qwen38` (bestehendes Profil) | keiner | alle Nutzer | vorausgewählt |
| 5 | qwen38-code | `qwen38-code` | keiner | nur Admin | aus |

- **Websuche** ist in allen vier Q3.8-Profilen in neuen Chats vorausgewählt (`defaultFeatureIds: ["web_search"]`, wie bisher bei `qwen38`). Dass das Modell nicht sofort lossucht, regeln die System-Prompts.
- **Q3.8 None** entsteht aus dem bestehenden Profil `qwen38` („Qwen3.8“): umbenennen und System-Prompt entfernen, sonst nichts ändern. Die ID bleibt, damit vorhandene Chats und das Standardmodell weiter funktionieren. `qwen38` bleibt Standardmodell für alle.
- **Die drei neuen Profile** übernehmen alle Einstellungen von `qwen38`: Basis `qwen3.8-27b`, `chat_template_kwargs {"reasoning_effort":"medium"}`, Sampling-Werte, Function Calling native, Capabilities (Vision, Upload, Code-Interpreter, eingebaute Werkzeuge, Websuche an, Bild aus). Unterschiede sind nur Name, ID, Beschreibung und System-Prompt.
- **qwen38-code** und das versteckte Basismodell bleiben unverändert.
- **Beschreibungen** in der Modellauswahl:
  - Q3.8 Büro: „Förmliche E-Mails und Briefe, z. B. an Versicherungen, IHK, Berufsschule, Handwerker.“
  - Q3.8 Backoffice: „Kundenanfragen prüfen, Kalkulation vorbereiten, Angebote und Kunden-E-Mails entwerfen.“
  - Q3.8 Recherche: „Ausarbeitungen und Schulungen: erst klären, dann mit Quellen recherchieren.“
  - Q3.8 None: „Ohne Vorgaben. Eigene Anweisung als erste Nachricht schreiben.“

## System-Prompts

Die Prompts liegen nach `git pull` als `Büro.md`, `Backoffice.md` und `Recherche.md` im Repo (`/srv/ki`). Fehlt eine der Dateien, brich ab und melde das.

- Der vollständige Dateiinhalt ist der System-Prompt, einschließlich der Überschrift in der ersten Zeile.
- Ändere am Inhalt nichts. Der Admin hat die Texte abgenommen. Fällt dir ein Fehler auf, melde ihn im Abschlussbericht.
- Die Prompts nennen das Werkzeug `fetch_url`. Prüfe, ob das Werkzeug in der installierten Version so heißt, und melde eine Abweichung.

## Nutzerrechte

Normale Nutzer dürfen keinen eigenen System-Prompt setzen und keine Modell-Parameter verstellen. Bisher ist „eigener System-Prompt/Parameter“ in `config.user.permissions` an (SETUP-LOG P5).

- Ermittle an der installierten Version (v0.11.4), welche Berechtigungen das steuern, und schalte sie für normale Nutzer aus. Übernimm die Schlüsselnamen nicht aus dem Gedächtnis.
- Prüfe alle Wege, auf denen ein Nutzer einen System-Prompt oder Parameter setzen kann: Chat-Steuerung, persönliche Einstellungen, Ordner oder Projekte, eigene Modelle im Arbeitsbereich. Schließe jeden Weg, für den es eine Berechtigung gibt. Melde Wege, die sich nicht schließen lassen.
- Prüfe am Code, ob ein bereits gespeicherter persönlicher System-Prompt nach dem Sperren noch angewendet wird. Lies dafür keine Nutzerinhalte aus der Datenbank.
- Die übrigen Rechte bleiben wie in P5: Datei-Upload, Websuche und Code-Interpreter an; API-Schlüssel, Bild und Sprache aus.

## Umsetzung

- Schreibe ein idempotentes Skript `scripts/p5-profile.sh` im Stil der vorhandenen Skripte. Es setzt die Profile aus den drei Prompt-Dateien auf den Soll-Zustand. Der Admin wird die Prompts noch öfter ändern, dann soll `git pull` und ein erneuter Lauf genügen.
- Das Skript legt vor einer Änderung die Sicherung `data/webui.db.bak-p5-profile` im Volume an, startet danach den Container neu und wartet auf `/health`. Ist nichts zu ändern, macht es nichts, auch keine Sicherung und keinen Neustart.
- Die Nutzerrechte kannst du einmalig von Hand setzen wie in P5 (eigene Sicherung `data/webui.db.bak-p5-perms2`).

## Tests

1. Nach dem Neustart sind genau fünf Profile aktiv, in der Reihenfolge der Tabelle. Das Basismodell ist versteckt.
2. Zugriff: die vier Q3.8-Profile für alle Nutzer lesbar, `qwen38-code` nur für den Admin.
3. Je Profil ein kurzer Testchat mit synthetischer Frage („Wofür sind Sie da?“) bei eingeschalteter Websuche: Büro, Backoffice und Recherche antworten in ihrer Rolle und starten dabei keine Websuche. Q3.8 None antwortet ohne Rolle, und im Aufruf an den llama-server steht kein System-Prompt.
4. Die Berechtigungen stehen nach dem Neustart auf den neuen Werten.
5. Zweiter Lauf von `scripts/p5-profile.sh` ändert nichts.

Was du nicht selbst prüfen kannst, weil dafür ein normales Nutzerkonto im Browser nötig ist, führst du im Bericht als offenen Test für den Admin auf: Ein Nutzer sieht nur vier Profile, kein Feld für den System-Prompt und keine Parameter-Regler.

## Dokumentation

- SETUP-LOG P5 ergänzen: Schritte, Sicherungen, Testergebnisse.
- Abweichungen als `P5-An` mit Begründung festhalten: fünf Profile statt zwei (PRD F-UI-05, 8.9), eigener System-Prompt und Parameter für Nutzer gesperrt. Die Websuche bleibt in allen vier Q3.8-Profilen vorausgewählt (P5-A4 gilt weiter). Der allgemeine System-Prompt aus PRD 8.9 entfällt. Seine Websuche-Regeln stehen in den drei neuen Prompts, bei Q3.8 None gibt es sie nicht mehr.
- `CLAUDE.md` anpassen: Liste der Profile und der neue Befehl `scripts/p5-profile.sh`.
- Committen und nach `PKR-HUB/lokal-ki` pushen.

## Grenzen

- Keine Chats, keine hochgeladenen Dateien und keine Nutzereinstellungen mit Inhalt lesen.
- `.env` nicht lesen. Keine Ports öffnen. Kein Neustart des Servers, nur des Containers.

## Abschlussbericht

Kurz und in dieser Reihenfolge: was angelegt und geändert wurde, Ergebnis der fünf Tests, Abweichungen und Auffälligkeiten (auch an den Prompts), offene Tests für den Admin.
