# ADMIN.md – Betrieb des KI-Servers

Kurzanleitung für den Admin. Technik, Updates und Aufräumen stehen in `Wartung.md`, der genaue Einrichtungsstand mit allen Tests in `SETUP-LOG.md`.

**Adresse für alle:** `https://192.168.10.129` (nur im Büronetz)
**SSH für den Admin:** `ssh msb@192.168.10.129`, Repo unter `/srv/ki`

## 1. Konten

Die Selbstregistrierung ist aus. Konten legt nur der Admin an.

### Konto anlegen

1. Als Admin anmelden, links unten auf den eigenen Namen → **Admin-Bereich** → **Benutzer** → **+**.
2. Ausfüllen:
   - **Rolle:** `user` (nicht `admin`, nicht `pending`)
   - **Name:** Anzeigename, z. B. „Anna Müller“
   - **E-Mail:** dient nur als Anmeldename, es wird nie eine Mail verschickt. Schema: `vorname@localhost`, klein, ohne Umlaute (`anna@localhost`). Bei doppelten Vornamen `vorname.nachname@localhost`.
   - **Passwort:** Startpasswort
3. Anmeldename und Startpasswort persönlich weitergeben. Der Mitarbeiter ändert das Passwort selbst unter Einstellungen → Konto.

Viele Konten auf einmal: im selben Dialog CSV-Import mit den Spalten Name, E-Mail, Passwort, Rolle.

### Passwort vergessen

Admin-Bereich → Benutzer → Konto bearbeiten → neues Passwort setzen und weitergeben.

### Konto löschen

Admin-Bereich → Benutzer → Konto löschen. Die Chats des Kontos werden dabei mit gelöscht.

### Was normale Nutzer dürfen

| Erlaubt | Gesperrt |
|---|---|
| Chatten mit den vier Q3.8-Profilen | eigener System-Prompt, Parameter, Chat-Steuerung |
| Dateien und Bilder hochladen | Chat-Import |
| Websuche, Code-Interpreter | Erinnerungen (Memory) |
| Ordner, Notizen, Chats teilen im Büro | API-Schlüssel, Bildgenerierung, Sprache |

Der Admin sieht keine fremden Chats (`ENABLE_ADMIN_CHAT_ACCESS=false`).

Die Oberfläche ist für alle auf Deutsch voreingestellt (`DEFAULT_LOCALE` in `docker-compose.yml`). Jeder kann unter Einstellungen → Allgemein → Sprache selbst umstellen, das gilt dann nur in seinem Browser.

## 2. Modell-Profile, System-Prompts, Vorschläge

| Profil | Zweck | Prompt-Datei |
|---|---|---|
| Q3.8 Büro | förmliche E-Mails und Briefe | `Büro.md` |
| Q3.8 Backoffice | Kundenanfragen, Kalkulation, Angebote | `Backoffice.md` |
| Q3.8 Recherche | Ausarbeitungen, Schulungen mit Quellen | `Recherche.md` |
| Q3.8 None | ohne Vorgaben, Standardmodell | – |
| qwen38-code | Coding-Agenten, nur Admin | – |

Die Vorschläge unter dem Eingabefeld stehen in `Vorschläge.json`.

**Prompt oder Vorschläge ändern:**

1. Datei im Repo bearbeiten (am PC), committen und pushen.
2. Auf dem Server:
   ```bash
   cd /srv/ki && git pull
   scripts/p5-profile.sh
   ```
   Das Skript ändert nur, was abweicht. Dann legt es eine Sicherung an, startet Open WebUI neu (ca. 15 s Unterbrechung) und wartet, bis es wieder läuft. Ist nichts zu ändern, meldet es „nichts geändert“.
3. Im Browser die Seite neu laden. Bestehende Chats behalten ihr Profil, neue Chats nutzen den neuen Prompt.

Profile nicht in der Oberfläche bearbeiten: Der nächste Lauf von `p5-profile.sh` überschreibt Änderungen an den vier Q3.8-Profilen.

## 3. Automatische Löschung (90 Tage)

Täglich um 05:30 (Berliner Zeit) löscht `chat-retention.timer`:

- Chats, die seit mehr als 90 Tagen nicht geändert wurden, samt Nachrichten und Bewertungen
- hochgeladene Dateien, die nirgends mehr verwendet werden (Datenbank, Platte, Suchindex)
- Sicherungen `webui.db.bak-*`, die älter als 90 Tage sind

Wissensdatenbanken bleiben. Wer einen Text länger braucht, muss ihn selbst sichern (kopieren, exportieren) oder in einer Wissensdatenbank ablegen. Das den Mitarbeitern sagen.

```bash
sudo scripts/p6-loeschung.sh --probelauf            # zählt, was gelöscht würde
systemctl list-timers chat-retention.timer          # nächster Lauf
sudo journalctl -u chat-retention.service -n 20     # letzte Läufe (nur Anzahlen)
```

## 4. Zustand prüfen

```bash
systemctl status llama-server caddy gpu-powerlimit chat-retention.timer --no-pager
curl -fsS http://127.0.0.1:8080/health     # Modell
curl -fsS http://127.0.0.1:3000/health     # Open WebUI
sudo docker compose -f /srv/ki/docker-compose.yml ps
nvidia-smi                                 # ca. 24,6 GB belegt, Limit 500 W
systemctl --failed
```

### Auslastung live ansehen (am Server-Monitor oder per SSH)

- `btop`: CPU, Arbeitsspeicher, Netz, Platten, Prozesse und GPU mit Verlaufskurven. Beenden mit `q`, Einstellungen mit `Esc`. Die Tasten `1`–`4` und `5` blenden die Bereiche CPU, Speicher, Netz, Prozesse und GPU ein oder aus.
- `nvtop`: nur die GPU, ausführlicher (Auslastung, Grafikspeicher, Leistung, Temperatur, Takt). Beenden mit `q` oder `F10`.

Im Leerlauf belegt das Modell dauerhaft ca. 24,6 GB Grafikspeicher bei fast 0 % GPU-Last. Während einer Antwort geht die GPU-Last auf nahezu 100 % und die Leistung bis 500 W.

### Verlauf im Browser: Netdata

**https://192.168.10.129/netdata/** (Benutzer `admin`, Passwort setzen/ändern am Server mit `sudo /srv/ki/scripts/p7-netdata-passwort.sh`). Zeigt CPU, Speicher, Platten, Netz, Container und GPU (unter „nvidia_smi“) sekundengenau und rückwirkend über Wochen. Den Hinweis auf die Anmeldung bei Netdata Cloud mit „Skip“ bzw. anonym weiter überspringen, ein Konto ist nicht nötig.

Die Seite ist aus dem ganzen Büronetz erreichbar, daher ein eigenes, starkes Passwort verwenden und nicht weitergeben. Chat-Inhalte zeigt Netdata nicht.

## 5. Neustart

| Was | Befehl | Dauer |
|---|---|---|
| Open WebUI | `sudo docker compose -f /srv/ki/docker-compose.yml restart open-webui` | ca. 15 s |
| Modell (llama-server) | `sudo systemctl restart llama-server` | ca. 10 s bis `/health` ok (Modell aus dem Cache), nach Server-Neustart länger |
| Caddy | `sudo systemctl restart caddy` | sofort |
| ganzer Server | `sudo reboot` | einige Minuten |

Nach einem Server-Neustart starten alle Dienste von selbst (A2), es ist nichts von Hand zu tun. Laufende Antworten brechen ab, also möglichst außerhalb der Arbeitszeit.

**Wenn der Chat nicht antwortet:** zuerst `curl http://127.0.0.1:8080/health`. Fehler → `sudo systemctl restart llama-server`, Log mit `sudo journalctl -u llama-server -n 50`. Läuft das Modell, aber die Seite nicht → Open WebUI neu starten.

## 6. Büro-PCs: Root-Zertifikat

Damit der Browser die Seite ohne Warnung öffnet, braucht jeder PC das Caddy-Root-Zertifikat `client/caddy-root.crt`. Pro Windows-Benutzer, in der Eingabeaufforderung:

```
certutil -user -addstore Root caddy-root.crt
```

Die Windows-Sicherheitsabfrage bestätigen und den Browser neu starten (gilt für Edge und Chrome; Firefox hat einen eigenen Zertifikatsspeicher). Für viele PCs geht das auch per Gruppenrichtlinie. Gültig bis 11.08.2036.

## 7. Pi und IDE-Anbindung

Verschoben (SETUP-LOG P5-A2, P5-A3). Vorbereitet sind das Profil `qwen38-code` und der API-Schlüssel des Admins. Die Anleitung kommt hierher, wenn Pi eingerichtet wird.

## 8. Abschaltung (PRD Abschnitt 10)

Wenn der Server für etwas anderes verwendet wird:

1. Mitarbeiter rechtzeitig informieren, damit sie benötigte Texte selbst sichern.
2. Dienste stoppen:
   ```bash
   sudo docker compose -f /srv/ki/docker-compose.yml down
   sudo systemctl disable --now llama-server caddy chat-retention.timer
   ```
3. Büro-Daten löschen:
   ```bash
   sudo docker volume rm ki_open-webui     # Name prüfen: sudo docker volume ls
   sudo rm /srv/ki/.env
   sudo journalctl --rotate && sudo journalctl --vacuum-time=1s
   ```
   Das Volume enthält alle Chats, Dateien, Wissensdatenbanken, Konten und die Sicherungen `webui.db.bak-*`.
4. Brave: API-Schlüssel widerrufen, Abo und Zahlungsmethode kündigen.
5. Caddy-Root-Zertifikat von den Büro-PCs entfernen:
   `certutil -user -delstore Root DB0A77036000C3AEE98285DE8B7B53D0A03C8202`
6. Bei Neuinstallation: SSD vorher sicher löschen (`nvme format` mit Secure Erase oder `blkdiscard`).
7. Verzeichnis von Verarbeitungstätigkeiten aktualisieren (Verarbeitung beendet, Datum der Löschung).

Modell (`/srv/models`) und llama.cpp (`/opt/llama.cpp`) enthalten keine Büro-Daten und können bleiben.

## 9. Claude Code auf dem Server

Claude Code ist ein Cloud-Dienst: Was es liest, geht an Anthropic. Deshalb gilt (`CLAUDE.md`, PRD 9.2):

- Aufträge nur zu Konfiguration und Wartung, nie mit Büro-Daten (Chats, hochgeladene Dateien, Datenbankinhalte, `.env`).
- Aufträge am besten als Markdown-Datei ins Repo legen und per `git pull` übergeben.
