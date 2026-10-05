# Wartung.md – Technik, Updates und Aufräumen

Für den Admin. Bedienung (Konten, Prompts, Neustart, Abschaltung) steht in `ADMIN.md`, die Einrichtung mit allen Versionen und Tests in `SETUP-LOG.md`.

Grundregel (PRD N-OPS-03): **Was läuft, wird nicht nebenbei aktualisiert.** Sicherheitsupdates des Systems kommen automatisch. Open WebUI, llama.cpp, CUDA und das Modell sind fest eingestellt und werden nur bewusst, mit Test und mit Eintrag im SETUP-LOG geändert.

## 1. Technik im Überblick

```
Büro-PC (Browser) ──HTTPS :443──► Caddy ──► Open WebUI (Docker) ──► llama-server ──► RTX 5090
                                  tls internal   127.0.0.1:3000        127.0.0.1:8080
```

| Baustein | Version (Stand 2026-10-04) | Herkunft | Update-Weg |
|---|---|---|---|
| Ubuntu | 26.04, Kernel 7.0.0-38 | Ubuntu | automatisch (Sicherheit), Rest monatlich von Hand |
| NVIDIA-Treiber | 595.91.07, `nvidia-headless-595-open` | Ubuntu | mit `apt upgrade`, danach Neustart |
| CUDA-Toolkit | 13.3.1, `apt-mark hold` | NVIDIA-Repo (Priorität 100) | nur für einen neuen llama.cpp-Build |
| llama.cpp | Tag `b11378`, statisch, `sm_120a` | GitHub, selbst gebaut in `/opt/llama.cpp` | Abschnitt 4 |
| Modell | Qwen3.8-27B UD-Q4_K_XL + mmproj, 18 GB | Hugging Face (unsloth) in `/srv/models` | Abschnitt 5 |
| Docker | 29.1.3, Compose 2.40.3 | Ubuntu | mit `apt upgrade` |
| Open WebUI | v0.11.4, per Tag und Digest fixiert | ghcr.io | Abschnitt 3 |
| Caddy | 2.6.2 | Ubuntu | mit `apt upgrade` |
| Netdata | 2.12.0 | Netdata-Repo (`etc/apt/sources.list.d/netdata.sources`) | mit `apt upgrade` (nicht automatisch) |
| Firewall, SSH | ufw (22 und 443 aus 192.168.10.0/24), nur Schlüssel-Login | Ubuntu | – |

Dienste und Timer:

| Name | Aufgabe |
|---|---|
| `llama-server.service` | Modell (User `llm`, 2 Slots, 64k Kontext je Chat) |
| `docker` + Container `open-webui` | Oberfläche, Neustart-Regel `always` |
| `caddy.service` | HTTPS |
| `gpu-powerlimit.service` | GPU-Limit 500 W beim Start |
| `chat-retention.timer` | Löschung nach 90 Tagen, täglich 05:30 |
| `netdata.service` | Monitoring, 127.0.0.1:19999, über Caddy unter `/netdata/` mit Passwort |
| `unattended-upgrades` | automatische Sicherheitsupdates |

Wo was liegt:

| Pfad | Inhalt | Büro-Daten? |
|---|---|---|
| `/srv/ki` | dieses Repo: Konfiguration, Skripte, Doku (GitHub `PKR-HUB/lokal-ki`) | nein (nur `.env` ist geheim) |
| `/srv/models` | Modelldateien | nein |
| `/opt/llama.cpp` | Quellcode und Build | nein |
| Docker-Volume `ki_open-webui` | Datenbank, Uploads, Vektor-DB, Sicherungen `webui.db.bak-*` | **ja** |
| `/etc/caddy`, `/etc/systemd/system` | installierte Kopien aus `etc/` im Repo | nein |

Dateien unter `etc/` im Repo spiegeln `/etc/`. Geändert wird immer im Repo, dann installiert das zugehörige `scripts/pN-*.sh` (mehrfach ausführbar).

## 2. System (Ubuntu-Pakete)

### Was automatisch passiert

`unattended-upgrades` installiert täglich Pakete aus `resolute` und `resolute-security`, also alle Sicherheitsupdates, auch für Kernel, Docker und Caddy. Pakete aus `resolute-updates` (normale Fehlerbehebungen, oft auch neue NVIDIA-Treiber) kommen **nicht** automatisch. Einen automatischen Neustart gibt es nicht.

### Monatlich von Hand (ca. 15 Minuten, außerhalb der Arbeitszeit)

```bash
sudo apt update
apt list --upgradable                 # ansehen, was kommt (NVIDIA? Kernel? Docker?)
sudo apt upgrade
sudo apt autoremove --purge           # alte Kernel und nicht mehr benötigte Pakete
sudo apt clean                        # heruntergeladene .deb-Dateien löschen
dpkg -l | awk '/^rc/{print $2}' | xargs -r sudo apt purge -y   # Reste entfernter Pakete
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs
```

Wenn `reboot-required` existiert (neuer Kernel, Treiber, libc), neu starten:

```bash
sudo reboot
# danach
nvidia-smi                            # Treiberversion, 500 W
curl -fsS http://127.0.0.1:8080/health && curl -fsS http://127.0.0.1:3000/health
systemctl --failed
```

**NVIDIA-Treiber:** Kernel-Module und Treiber müssen zusammenpassen. Ubuntu baut die Module passend zum Kernel (`linux-modules-nvidia-595-open-generic`). Nach einem Treiber- oder Kernel-Update meldet `nvidia-smi` bis zum Neustart „Driver/library version mismatch“, das ist normal. Kein `.run`-Installer von nvidia.com verwenden. Ein Wechsel auf einen anderen Treiberzweig (z. B. 610) ist ein eigenes Vorhaben mit Test (A1, A3, A4, A14).

**Netdata** kommt aus dem eigenen Repo von Netdata und wird von `unattended-upgrades` nicht erfasst, nur vom monatlichen `apt upgrade`. Nach einem Update prüfen: `sudo ss -tlnp | grep 19999` muss `127.0.0.1` zeigen, die Seite `/netdata/` muss nach Passwort fragen. Einstellungen stehen in `etc/netdata/netdata.conf`, installiert von `scripts/p7-netdata.sh`. Der Netdata-eigene Updater wird nicht verwendet.

**Nicht mit `apt upgrade` verändern:** `cuda-toolkit-13-3` ist gehalten (`apt-mark showhold`). Das NVIDIA-Repo hat Priorität 100, Treiber kommen dadurch weiter von Ubuntu (`etc/apt/preferences.d/nvidia-cuda-repo`).

**Nach einem Ubuntu-Release-Upgrade** (z. B. auf 26.10 oder 28.04): Treiberpakete, CUDA-Repo, Docker und Caddy neu prüfen und die Abnahmetests wiederholen. Für den befristeten Betrieb nicht vorgesehen.

## 3. Open WebUI (Docker)

### Update

Open WebUI ändert oft Einstellungen, Rechte und Datenbank-Schema. Ein Update nur, wenn eine neue Version etwas Nötiges bringt (Sicherheitslücke, benötigte Funktion), und vorher die Release-Notes lesen: <https://github.com/open-webui/open-webui/releases>

1. Neue Version laden und Digest ermitteln:
   ```bash
   sudo docker pull ghcr.io/open-webui/open-webui:vX.Y.Z
   sudo docker inspect --format '{{index .RepoDigests 0}}' ghcr.io/open-webui/open-webui:vX.Y.Z
   ```
2. Datenbank sichern (wird nach 90 Tagen vom Löschjob entfernt):
   ```bash
   sudo docker exec open-webui python3 -c 'import sqlite3;s=sqlite3.connect("/app/backend/data/webui.db");b=sqlite3.connect("/app/backend/data/webui.db.bak-update-vX.Y.Z");s.backup(b);b.close()'
   ```
3. In `docker-compose.yml` die Zeile `image:` auf `vX.Y.Z@sha256:…` ändern, dann:
   ```bash
   scripts/p4-openwebui.sh               # startet mit dem neuen Image, wartet auf /health
   scripts/p5-profile.sh                 # sollte „nichts geändert“ melden
   sudo scripts/p6-loeschung.sh --probelauf
   sudo docker logs --since 5m open-webui 2>&1 | grep -iE "error|exception" | head
   ```
4. Im Browser prüfen: Anmeldung, die vier Profile, ein Chat mit Websuche, als normaler Nutzer keine System-Prompt-Felder und keine Parameter.
5. **Die Skripte hängen an Interna von v0.11.4** (Modell-Klassen, Tabellen `chat_file`, `knowledge_file`, `feedback`, Rechte-Schlüssel). Nach einem Update `p5-profile.sh` und einen Probelauf von `p6-loeschung.sh` immer laufen lassen. Bricht eines ab, das Skript an die neue Version anpassen, bevor der nächste nächtliche Löschlauf kommt (oder bis dahin zurückrollen).
6. Committen, SETUP-LOG ergänzen, altes Image entfernen (Abschnitt 6).

**Zurückrollen:** Das neue Schema lässt sich nicht zurückmigrieren. Deshalb altes Image wieder in `docker-compose.yml` eintragen, Container stoppen, Sicherung zurückspielen (die DB läuft im WAL-Modus, `-wal` und `-shm` müssen mit weg), starten:

```bash
sudo docker compose -f /srv/ki/docker-compose.yml stop open-webui
sudo docker run --rm --entrypoint sh -v ki_open-webui:/d ghcr.io/open-webui/open-webui:v0.11.4 \
  -c 'cp /d/webui.db.bak-update-vX.Y.Z /d/webui.db && rm -f /d/webui.db-wal /d/webui.db-shm'
scripts/p4-openwebui.sh
```

Dafür das alte Image erst nach erfolgreichem Test mit `docker image prune -a` entfernen.

### Einstellungen

Die Umgebungsvariablen stehen in `docker-compose.yml` (Geheimes in `.env`). Viele Einstellungen liegen aber in der Datenbank und gelten vor der Variablen (Profile, Rechte, Brave-Key, Standardmodell). Wie sie gesetzt sind, steht in SETUP-LOG P5.

## 4. llama.cpp

Update nur bei Bedarf: Fehlerbehebung für Qwen3.8, MTP oder Blackwell, oder spürbar mehr Leistung. Releases: <https://github.com/ggml-org/llama.cpp/releases>

1. Build (dauert, der laufende Dienst bleibt bis zum Neustart auf dem alten Binary):
   ```bash
   LLAMA_TAG=bNNNNN scripts/p3-build-llama.sh     # als msb, ohne sudo
   ```
2. Flags gegen die neue Version prüfen, sie ändern sich gelegentlich:
   ```bash
   /opt/llama.cpp/build/bin/llama-server --help | grep -E "spec-type|spec-draft|chat-template-kwargs|cache-type|-fa"
   ```
3. Neu starten und messen:
   ```bash
   scripts/p3-llama-service.sh           # Neustart, wartet auf /health
   scripts/p3-bench.py all               # A3, A4, A14 – Werte mit SETUP-LOG P3 vergleichen
   ```
4. Im Browser je ein Chat mit Bild und mit Websuche (Werkzeugaufrufe).
5. Neuen Tag in `scripts/p3-build-llama.sh` eintragen, SETUP-LOG ergänzen, committen.

**Zurückrollen:** `LLAMA_TAG=b11378 scripts/p3-build-llama.sh`, dann `scripts/p3-llama-service.sh`.

Braucht eine neue llama.cpp-Version ein neueres CUDA: `sudo apt-mark unhold cuda-toolkit-13-3`, neues Toolkit installieren, Pfade in `p3-build-llama.sh` anpassen, wieder halten. Ein neues CUDA-Toolkit kann einen neueren Treiber voraussetzen.

## 5. Modell

Neue Modellversion oder andere Quantisierung: `scripts/p3-download-model.sh` anpassen (Dateinamen), laden (prüft SHA256), Pfade in `etc/systemd/system/llama-server.service` ändern, `scripts/p3-llama-service.sh`, dann A3/A4/A14 messen und VRAM prüfen (Grenze 29 GB). Den Alias `qwen3.8-27b` beibehalten, sonst müssen die Open-WebUI-Profile angepasst werden. Alte Modelldateien danach löschen.

Nicht ändern ohne Rechnung: Kontext `-c 131072 -np 2` (64k je Chat). Mehr Kontext braucht VRAM (Rechnung in SETUP-LOG P5, „Kontext geprüft“).

## 6. Docker aufräumen

Nach jedem Open-WebUI-Update, sonst vierteljährlich:

```bash
sudo docker system df                           # Überblick
sudo docker image ls                            # alte open-webui-Images?
sudo docker image prune -a                      # löscht Images, die kein Container nutzt (das alte Open WebUI)
sudo docker builder prune                       # Build-Cache (normalerweise leer)
```

**Niemals:**

- `docker volume prune` oder `docker system prune --volumes` – das Volume `ki_open-webui` enthält alle Konten, Chats und Wissensdatenbanken. Ist der Container gerade gestoppt, wäre es weg.
- `docker compose down -v` – löscht ebenfalls das Volume.

Container-Logs sind auf 3 × 10 MB begrenzt (`docker-compose.yml`), das Journal auf 30 Tage und 1 GB (`etc/systemd/journald.conf.d/retention.conf`).

## 7. Regelmäßige Kontrolle

| Wann | Was | Befehl |
|---|---|---|
| wöchentlich (2 Min.) | Dienste und Fehler | `systemctl --failed`, `curl …8080/health`, `curl …3000/health` |
| wöchentlich | Löschjob gelaufen | `sudo journalctl -u chat-retention.service --since -7d` |
| monatlich | Systemupdates | Abschnitt 2 |
| monatlich | Platz | `df -h /`, `sudo docker system df`, `journalctl --disk-usage` |
| monatlich | GPU | `nvidia-smi` (Temperatur, 500 W, ca. 24,6 GB belegt) |
| vierteljährlich | Docker aufräumen | Abschnitt 6 |
| vierteljährlich | Versionen prüfen | Release-Notes Open WebUI, llama.cpp; Update nur bei Bedarf |
| bei Bedarf | Brave-Abo und Kontingent | Brave-Dashboard |

Stand 2026-10-04: 49 GB von 1,8 TB belegt (Modell 18 GB, Open-WebUI-Image 6,5 GB, Volume 1,1 GB).

## 8. Fehlersuche

| Problem | Prüfen | Lösung |
|---|---|---|
| Seite lädt nicht | `systemctl status caddy`, `curl …3000/health` | Caddy bzw. Open WebUI neu starten |
| Chat antwortet nicht | `curl …8080/health`, `sudo journalctl -u llama-server -n 50` | `sudo systemctl restart llama-server` |
| `nvidia-smi`: version mismatch | Treiber-Update ohne Neustart | `sudo reboot` |
| „context exceeded“ / Abbruch bei langen Chats | Chat über 64k Tokens | neuen Chat beginnen |
| Websuche liefert nichts | Brave-Kontingent, Key im Admin-Bereich | Key prüfen; DNS/Internet des Servers |
| Open WebUI startet langsam | Log auf Netzwerkfehler | `HF_HUB_OFFLINE=1` ist gesetzt; DNS prüfen |
| Löschjob fehlgeschlagen | `systemctl status chat-retention.service` | Fehlermeldung; nach Open-WebUI-Update Skript anpassen |

Beim Lesen von Logs mit Claude Code: Logs von Open WebUI können Chat-Inhalte enthalten. Nur gezielt nach Fehlern filtern (wie oben), keine ganzen Logs übergeben.

## 9. Mit Claude Code warten

- Auftrag als Markdown-Datei ins Repo legen, pushen, auf dem Server `git pull` und Claude Code darauf verweisen.
- Claude Code arbeitet nach `CLAUDE.md`: keine Büro-Daten, keine `.env`, Sicherung vor Eingriffen in die Datenbank, Neustart des Servers nur nach Rückfrage, jeder Schritt im SETUP-LOG.
