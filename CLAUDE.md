# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Worum es geht

Kein Software-Projekt, sondern die **Konfiguration eines lokalen KI-Servers** (Ubuntu 26.04, RTX 5090, IP 192.168.10.129) für ein Büro. Es gibt keinen Build, keine Tests und keinen Linter. Das Repo enthält Systemkonfiguration, idempotente Installationsskripte und die Dokumentation.

- `PRD.md`: Anforderungen. Maßgeblich sind §9.3 (Arbeitsregeln), §9.4 (Phasen P1–P7) und §11 (Abnahmetests A1–A15).
- `SETUP-LOG.md`: der tatsächliche Stand je Phase, mit Versionen, Testergebnissen und **Abweichungen von der PRD** (z. B. P1-A1, P5-A1). Wo das Log der PRD widerspricht, gilt das Log. Beispiele: Leistungslimit 500 W statt 400 W, SSH aus dem ganzen Büronetz, `nvidia-headless-595-open`, API-Schlüssel nur für den Admin, Pi verschoben.
- Sprache aller Dokumente, Kommentare und Commit-Messages: Deutsch.

## Architektur

```
LAN :443 → Caddy (tls internal, etc/caddy/Caddyfile)
         → Open WebUI 127.0.0.1:3000 (Docker, network_mode: host, docker-compose.yml)
         → llama-server 127.0.0.1:8080 (systemd, User llm, etc/systemd/system/llama-server.service)
           Qwen3.8-27B UD-Q4_K_XL + mmproj (Vision) + MTP, 2 Slots, 128k Kontext
          /netdata/ → GPU-Übersicht /netdata/gpu/ (etc/caddy/netdata-gpu), volle Oberfläche /netdata/v3/ → Netdata 127.0.0.1:19999 (basicauth, Hash in /etc/caddy/netdata-auth.caddy)
```

- Nur 22 und 443 sind aus 192.168.10.0/24 offen (ufw). Open WebUI läuft im Host-Netz, damit Docker die Firewall nicht umgeht. 3000, 8080 und 19999 (Netdata) dürfen nie nach außen gebunden werden.
- Dateien unter `etc/` spiegeln die Pfade unter `/etc/`. Das jeweilige `scripts/pN-*.sh` installiert sie per `cmp`/`install`, lädt den Dienst neu und ist mehrfach ausführbar.
- Modell unter `/srv/models/qwen3.8-27b`, llama.cpp unter `/opt/llama.cpp` (Tag fixiert in `scripts/p3-build-llama.sh`, CUDA 13.3, `sm_120a`). Das Open-WebUI-Image ist per Tag und Digest fixiert.
- Die Open-WebUI-Konfiguration (Modell-Profile Q3.8 Büro `qwen38-buero`, Q3.8 Backoffice `qwen38-backoffice`, Q3.8 Recherche `qwen38-recherche`, Q3.8 None `qwen38` = Standardmodell, `qwen38-code` nur Admin; Nutzerrechte, Brave-Key, Standardmodell) liegt in der **Datenbank im Docker-Volume `open-webui`**, nicht im Repo. Änderungen daran sind in SETUP-LOG P5 beschrieben. Die System-Prompts der Profile liegen als `Büro.md`, `Backoffice.md`, `Recherche.md` im Repo, die Vorschläge unter dem Chat in `Vorschläge.json`, und werden mit `scripts/p5-profile.sh` übernommen. Vor jedem Eingriff in `webui.db` wird eine Sicherung `data/webui.db.bak-<anlass>` im Volume angelegt, danach wird der Container neu gestartet.

## Häufige Befehle

```bash
# Konfiguration nach Änderung in etc/ ausrollen (idempotent)
scripts/p3-llama-service.sh      # llama-server-Unit installieren, Neustart, warten auf /health
scripts/p4-caddy.sh              # Caddyfile, owui/custom.css (Knöpfe auch für Admins aus) und GPU-Übersicht installieren
scripts/p4-openwebui.sh          # docker compose up -d, warten auf /health
scripts/p5-profile.sh            # Modell-Profile aus Büro.md/Backoffice.md/Recherche.md/Vorschläge.json setzen (nur bei Abweichung: Sicherung, Neustart)
scripts/p5-kopieren.sh           # "Formatierten Text kopieren" für alle Nutzer einschalten (Vorgabe ui.default_interface_settings)
scripts/p5-knoepfe.sh            # Knöpfe Bewerten, Vorlesen, Fortsetzen und "Für Outlook kopieren" ausblenden
scripts/p6-retention.sh          # Timer chat-retention (täglich) installieren
scripts/p7-netdata.sh            # Netdata (Monitoring, 127.0.0.1:19999) installieren/konfigurieren
sudo scripts/p7-netdata-passwort.sh   # Passwort für https://192.168.10.129/netdata/ setzen
sudo scripts/p6-loeschung.sh --probelauf   # zählen, was nach 90 Tagen gelöscht würde (ohne --probelauf: löschen)

# Zustand prüfen
systemctl status llama-server caddy gpu-powerlimit chat-retention.timer
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:3000/health
sudo docker compose -f /srv/ki/docker-compose.yml ps
nvidia-smi

# Leistungs-Abnahmetests A3/A4/A14 (synthetische Prompts, Ergebnis als JSON)
scripts/p3-bench.py a3|a4|a14|all
```

Flags von `llama-server` und Optionen von Open WebUI vor Änderungen gegen die installierte Version prüfen (`--help`, Doku), nicht aus dem Gedächtnis übernehmen.

## Arbeitsregeln (PRD §9.3, §9.2)

- `.env` **nicht lesen und nicht ausgeben** (enthält `WEBUI_SECRET_KEY`). Keine Secrets ins git (`.gitignore` deckt `.env`, `*.env`, `client/*-personal*.json`, `.owui-admin-key` ab).
- **Keine Büro-Daten lesen**: keine Chat-Inhalte, keine hochgeladenen Dateien, keine Chat-Inhalte aus Logs. Gezielte Konfigurationsänderungen in der Open-WebUI-DB nur wie in P5 beschrieben.
- Vor Neustarts des Servers und vor allem, was die SSH-Verbindung unterbrechen könnte (ufw, sshd, Netplan), den Admin fragen.
- Keine weiteren Ports öffnen. Keine Änderungen am LANCOM-Router.
- Außerhalb von `/srv/ki`, `/srv/models`, `/opt/llama.cpp`, `/etc/systemd/system`, `/etc/caddy`, `/etc/netplan` nichts löschen oder überschreiben, ohne zu fragen.
- Neue Skripte idempotent unter `scripts/` mit dem Präfix der Phase (`p5-…`), im gleichen Stil: `set -euo pipefail`, Quelle relativ zum Skript, deutsche Meldungen.
- Jeden Schritt in `SETUP-LOG.md` dokumentieren (was, Versionen, Tests, Abweichungen mit Begründung als `Pn-An`). Nach jeder Phase die Konfiguration committen. Pushen nach `PKR-HUB/lokal-ki` (Remote über SSH-Alias `github-ki`) ist freigegeben.
