# PRD: Lokaler KI-Server für das Büro

| | |
|---|---|
| **Dokument** | Product Requirements Document (PRD) |
| **Version** | 1.2 |
| **Stand** | 03.10.2026 |
| **Status** | Zur Umsetzung freigegeben |
| **Geltungsbereich** | Ein KI-Server im internen Büronetz für Büroarbeit, allgemeine KI-Unterstützung und Coding |
| **Betriebsdauer** | Befristet, voraussichtlich einige Monate. Danach wird die Hardware für ein anderes Projekt genutzt. |
| **Umsetzung** | Mit Claude Code direkt auf dem Ubuntu-Server (siehe Abschnitt 9) |

---

## 1. Zusammenfassung

Das Büro erhält einen lokalen KI-Server. Mitarbeitende nutzen ihn über den Browser mit eigenen Konten, ähnlich wie ChatGPT, aber auf eigener Hardware. Texte, Dokumente und Chats verlassen das Haus nicht. Für aktuelle Informationen gibt es eine optionale Websuche über die Brave Search API. Dabei entscheidet das Modell selbst, wann es sucht und welche Seiten es liest (Native/Agentic-Modus).

Der Betrieb ist befristet. Es wird bewusst **nichts dauerhaft gespeichert**: Es gibt keine Backups, Chats werden nach 90 Tagen automatisch gelöscht, und bei der Abschaltung werden alle Büro-Daten entfernt.

**Kernentscheidungen:**

| Bereich | Entscheidung |
|---|---|
| Betriebssystem | Ubuntu 26.04 LTS Server |
| GPU-Treiber | `nvidia-driver-595-open` (Open-Kernel-Variante, Pflicht für RTX 50) |
| Inferenz-Engine | llama.cpp (`llama-server`), CUDA-Build |
| Modell | Qwen3.8-27B, Unsloth **UD-Q4_K_XL** (GGUF, 17,6 GB), mit Vision-Modul (mmproj) und MTP |
| Denkstufe | **`medium`** für alle Aufgaben |
| Oberfläche | Open WebUI (Docker), max. 25 Benutzerkonten |
| Websuche | Brave Search API, Function Calling **Native / Agentic** |
| Coding-Agent | Pi über die Open-WebUI-API mit persönlichem Schlüssel, eigenes Profil `qwen38-code` |
| Zugriff | Nur internes LAN über feste IP, HTTPS über Caddy |
| Datenhaltung | Keine Backups, Chats nach 90 Tagen löschen |

---

## 2. Ausgangslage und Ziele

### 2.1 Ausgangslage

- Kleines Büro, LANCOM-Router, Glasfaser, 10G-LAN, **feste IP-Adressen** im Netzwerk.
- Internetanschluss 500 Mbit/s.
- **Max. 25 Benutzerkonten.** Typische Nutzung: 1–2 Personen generieren gleichzeitig, meist nacheinander.
- Arbeitssprache überwiegend Deutsch.
- Kein Betriebsrat.
- Kein Fernzugriff gewünscht.

### 2.2 Ziele

| ID | Ziel |
|---|---|
| Z1 | Mitarbeitende können Texte erstellen und überarbeiten (E-Mails, Briefe, Zusammenfassungen, Protokolle). |
| Z2 | Allgemeiner KI-Assistent für Fragen, Analysen sowie Bilder und Scans (Rechnungen, Fotos, PDFs). |
| Z3 | Coding-Unterstützung im Browser, in der IDE (Continue, Cline, Aider) und mit dem Coding-Agenten **Pi** über eine OpenAI-kompatible API. |
| Z4 | Websuche für aktuelle Informationen, mit Quellenangabe. |
| Z5 | Datenschutz: Inferenz, Chats und Dokumente bleiben lokal. Nach außen gehen nur Suchbegriffe an Brave, wenn die Websuche aktiv ist. |
| Z6 | Datensparsamkeit: keine dauerhafte Speicherung, Chats nach 90 Tagen gelöscht, vollständige Löschung bei Abschaltung. |
| Z7 | Wartungsarm: Dienste starten automatisch, die Konfiguration ist versioniert und der Server damit reproduzierbar. |

### 2.3 Nicht-Ziele

- Kein Zugriff von außen, **auch kein VPN**.
- **Keine Backups.** Bei einem Defekt wird der Server nach dieser PRD neu aufgesetzt; Chats gehen dabei verloren.
- Keine Bilderzeugung (ComfyUI o. Ä.).
- Kein Fine-Tuning und kein Training.
- Kein vLLM/SGLang, solange regelmäßig höchstens 2 Personen gleichzeitig generieren.
- Keine automatische Verarbeitung von E-Mails oder Dateiablagen.
- Keine Integration in Microsoft Office/Outlook.

---

## 3. Nutzer und Rollen

| Rolle | Beschreibung | Rechte |
|---|---|---|
| **Admin** | IT-Verantwortliche/r | Konten, Modelle, Websuche, Einstellungen verwalten |
| **User** | Mitarbeitende (insgesamt max. 25 Konten inkl. Admin) | Eigene Chats, eigene Dokumente, Websuche einschalten, eigene API-Schlüssel |
| **Gruppen** (optional) | z. B. „Büro“, „Entwicklung“ | Gemeinsame Wissensdatenbanken |

Chats sind privat. Admins sehen fremde Chats **nicht** (`ENABLE_ADMIN_CHAT_ACCESS=false`).

---

## 4. Hardware

| Komponente | Modell |
|---|---|
| GPU | ASUS TUF Gaming GeForce RTX 5090, 32 GB GDDR7 |
| CPU | AMD Ryzen 9 7900 (12C/24T, 65 W, mit iGPU) |
| RAM | 64 GB DDR5-5200 (Corsair Vengeance RGB) |
| Mainboard | ASUS TUF Gaming B850-Plus WIFI |
| SSD | Samsung 9100 PRO 2 TB (PCIe 5.0) |
| Netzteil | be quiet! Dark Power 14, 1000 W, ATX 3.1 |

### 4.1 BIOS-Anforderungen (manuell, vor der Installation)

- [ ] Aktuelles BIOS installiert
- [ ] EXPO-Profil aktiv (DDR5-5200)
- [ ] Above 4G Decoding und Resizable BAR aktiv
- [ ] Bildschirmausgabe (falls benötigt) über die iGPU des Ryzen, damit der VRAM der 5090 vollständig frei bleibt

---

## 5. Systemarchitektur

```
 Büro-PCs (Browser, IDE)
          │  HTTPS (443) an feste Server-IP, nur LAN
          ▼
 ┌──────────────────────────────────────────────────────┐
 │ KI-Server (Ubuntu 26.04, feste IP)                   │
 │                                                      │
 │  Caddy :443 ──► Open WebUI 127.0.0.1:3000 (Docker)   │
 │                     │            │                   │
 │                     │            └──► Brave Search API (Internet)
 │                     ▼                                │
 │            llama-server 127.0.0.1:8080 (systemd)     │
 │            Qwen3.8-27B UD-Q4_K_XL + mmproj + MTP     │
 │                     │                                │
 │                 RTX 5090 (32 GB)                     │
 └──────────────────────────────────────────────────────┘
```

- llama-server und Open WebUI sind **nur auf 127.0.0.1** erreichbar.
- Von außen (LAN) ist **ausschließlich Caddy auf Port 443** erreichbar, dazu SSH für den Admin.
- Open WebUI läuft im Host-Netzwerk (`network_mode: host`). Dadurch gelten die ufw-Regeln uneingeschränkt; es gibt keine Docker-Portfreigaben, die die Firewall umgehen.

### 5.1 Parameter (vor der Umsetzung ausfüllen)

| Parameter | Wert | Hinweis |
|---|---|---|
| `SERVER_IP` | `<z. B. 192.168.10.20>` | Feste IP des KI-Servers |
| `GATEWAY_IP` | `<LANCOM-IP>` | |
| `DNS_SERVER` | `<meist LANCOM-IP>` | |
| `BUERO_SUBNETZ` | `<z. B. 192.168.10.0/24>` | Nur dieses Netz darf auf 443 zugreifen |
| `ADMIN_IP` | `<IP des Admin-PCs>` | Nur diese IP darf per SSH zugreifen |
| `HOSTNAME` (optional) | `<z. B. ki.buero.lan>` | Nur falls im LANCOM ein DNS-Eintrag angelegt wird; sonst wird die IP verwendet |
| `BRAVE_SEARCH_API_KEY` | trägt der Admin selbst in `.env` ein | Nicht an Claude Code weitergeben |

---

## 6. Funktionale Anforderungen

Priorität: **M** = Muss, **S** = Soll, **K** = Kann.

### 6.1 Inferenz (llama.cpp)

| ID | Anforderung | Prio |
|---|---|---|
| F-INF-01 | Qwen3.8-27B UD-Q4_K_XL läuft vollständig auf der GPU (`-ngl 99`). | M |
| F-INF-02 | Bilder und Scans werden verarbeitet (mmproj geladen). | M |
| F-INF-03 | MTP (Multi-Token Prediction) ist aktiv, um die Generierung zu beschleunigen. | M |
| F-INF-04 | 2 parallele Slots (`-np 2`). Weitere Anfragen warten in der Warteschlange und gehen nicht verloren. | M |
| F-INF-05 | Kontext gesamt 131.072 Tokens (je nach llama.cpp-Version ca. 64K pro Slot), KV-Cache in q8_0. | M |
| F-INF-06 | Tool Calling über das Jinja-Chat-Template (`--jinja`), Voraussetzung für Native/Agentic. | M |
| F-INF-07 | Denkstufe `reasoning_effort=medium` als Server-Standard (nicht `xhigh`, wegen übermäßigem Denken). | M |
| F-INF-08 | OpenAI-kompatible API unter `127.0.0.1:8080/v1`. | M |
| F-INF-09 | Start automatisch beim Booten (systemd), Neustart bei Absturz. | M |
| F-INF-10 | Prometheus-Metriken aktiv (`--metrics`). | S |

### 6.2 Oberfläche und Konten (Open WebUI)

| ID | Anforderung | Prio |
|---|---|---|
| F-UI-01 | Jede Person hat ein eigenes Konto mit eigenen Chats und Einstellungen (max. 25 Konten). | M |
| F-UI-02 | Selbstregistrierung ist deaktiviert. Konten legt der Admin an. | M |
| F-UI-03 | Admins können fremde Chats nicht einsehen. | M |
| F-UI-04 | Dokument-Upload (PDF, Word usw.) mit Fragen dazu (RAG). | M |
| F-UI-05 | Zwei Modell-Profile mit Denkstufe `medium`: **„Qwen3.8“** (Browser-Chat: Büro, Analyse, Code) und **`qwen38-code`** (Coding-Agenten wie Pi, ohne System-Prompt und ohne Websuche), siehe 8.9. | M |
| F-UI-06 | Gespeicherte Prompt-Vorlagen für typische Bürotexte (z. B. Kundenantwort, Mahnung, Protokoll). | S |
| F-UI-07 | Gruppen und gemeinsame Wissensdatenbanken (z. B. Vorlagen, Richtlinien). | K |
| F-UI-08 | Persönliche API-Schlüssel für Pi und IDE-Tools: API-Schlüssel global aktiviert; normale Nutzer brauchen die Berechtigung „API Keys“ (über die Standardrechte oder eine Gruppe, z. B. „Entwicklung“). | M |
| F-UI-09 | Hintergrundaufgaben, die unnötig einen Slot belegen, sind reduziert: Autovervollständigung aus, Titel/Tags optional aus. | M |
| F-UI-10 | Chats werden **90 Tage nach der letzten Aktivität automatisch gelöscht**, inklusive der darin hochgeladenen Dateien (siehe 8.11). | M |

### 6.3 Websuche (Brave, Native/Agentic)

| ID | Anforderung | Prio |
|---|---|---|
| F-WEB-01 | Websuche über die Brave Search API (`WEB_SEARCH_ENGINE=brave`). | M |
| F-WEB-02 | Function Calling ist global auf **Native** gesetzt. Das Modell ruft `search_web` und `fetch_url` selbst auf und kann mehrfach suchen. | M |
| F-WEB-03 | Die Websuche ist **nicht** standardmäßig aktiv. Nutzer schalten sie pro Chat bewusst ein (Integrations-Button). | M |
| F-WEB-04 | Max. 5 Treffer pro Suche, 1 gleichzeitige Anfrage an Brave (vermeidet 429-Fehler). | M |
| F-WEB-05 | Abgerufene Seiten werden auf 20.000 Zeichen begrenzt (`WEB_FETCH_MAX_CONTENT_LENGTH`). | M |
| F-WEB-06 | Antworten mit Webbezug nennen die gelesenen Quellen (Zitate aus `fetch_url`). | M |
| F-WEB-07 | Scheitert die Suche, sagt das Modell das ausdrücklich, statt Fakten zu erfinden (System-Prompt). | M |
| F-WEB-08 | Ausgabenlimit im Brave-Dashboard gesetzt. | M |
| F-WEB-09 | SearXNG als Ausweichlösung (per Admin-Dropdown umschaltbar). | K |

**Voraussetzungen, damit Native-Websuche funktioniert (alle müssen erfüllt sein):**

1. Websuche global aktiv (Admin → Einstellungen → Websuche)
2. Capability „Web Search“ am Modell aktiv
3. Websuche im Chat eingeschaltet (oder als Default-Feature, hier bewusst **nicht**)
4. Nutzer hat die Berechtigung
5. Function Calling = `Native`

### 6.4 Coding

| ID | Anforderung | Prio |
|---|---|---|
| F-COD-01 | Coding-Tools (Pi, Continue, Cline, Aider) verbinden sich über `https://<SERVER_IP>/api` mit persönlichem API-Schlüssel aus Open WebUI. | M |
| F-COD-02 | Coding-Tools nutzen das Profil `qwen38-code` (Denkstufe `medium`, Thinking-Parameter, kein System-Prompt, keine eingebauten Open-WebUI-Werkzeuge). | M |
| F-COD-03 | Pi ist über `~/.pi/agent/models.json` angebunden, inklusive Bildeingabe (8.12). | M |
| F-COD-04 | Werkzeugaufrufe (Tool Calls) von Pi werden über Open WebUI an das Modell durchgereicht und funktionieren (Abnahme A15). | M |
| F-COD-05 | Pi kann alternativ direkt auf dem Server per SSH genutzt werden (`http://127.0.0.1:8080/v1`, ohne Open WebUI). | K |
| F-COD-06 | Tab-Autovervollständigung (FIM) mit separatem Kleinmodell. | K (Version 2) |

---

## 7. Nicht-funktionale Anforderungen

### 7.1 Leistung

Die Zielwerte basieren auf Community-Messungen mit RTX 5090 und UD-Q4_K_XL und müssen bei der Abnahme gemessen werden.

| ID | Anforderung | Zielwert |
|---|---|---|
| N-PERF-01 | Generierung, 1 Anfrage, mit MTP | ≥ 100 Token/s (Community: ca. 120–180) |
| N-PERF-02 | Generierung, 2 parallele Anfragen | ≥ 50 Token/s je Anfrage |
| N-PERF-03 | Zeit bis zum Beginn der sichtbaren Antwort (inkl. Denkphase `medium`), kurze Frage | < 20 s (Schätzung) |
| N-PERF-04 | E-Mail mit ca. 500 Wörtern, inkl. Denkphase | < 30 s gesamt (Schätzung) |
| N-PERF-05 | Antwort mit Websuche (Suche, 1–2 Seiten lesen, antworten) | < 60 s |
| N-PERF-06 | VRAM-Belegung im Betrieb | ≤ 29 GB (Reserve für Lastspitzen) |

### 7.2 Betrieb

| ID | Anforderung |
|---|---|
| N-OPS-01 | Alle Dienste starten nach einem Neustart automatisch (systemd, Docker `restart: always`). |
| N-OPS-02 | **Keine Backups.** Konfigurationsdateien (ohne Secrets) liegen in einem lokalen git-Repository unter `/srv/ki`, damit der Server reproduzierbar ist. |
| N-OPS-03 | Versionen werden fixiert (Open-WebUI-Image-Tag, llama.cpp-Commit). Updates nur nach Test. |
| N-OPS-04 | GPU-Leistungslimit 400 W (kaum Tempoverlust, weniger Wärme und Lärm), per systemd beim Boot gesetzt. |
| N-OPS-05 | Überwachung: `nvtop`/`nvidia-smi`, llama-server `/health` und `/metrics`. |
| N-OPS-06 | Logs werden begrenzt: Docker-Logs max. 3 × 10 MB, journald max. 30 Tage. |

### 7.3 Sicherheit

| ID | Anforderung |
|---|---|
| N-SEC-01 | ufw: `default deny incoming`; erlaubt sind nur 443/tcp aus `BUERO_SUBNETZ` und 22/tcp von `ADMIN_IP`. |
| N-SEC-02 | llama-server und Open WebUI lauschen nur auf `127.0.0.1`. |
| N-SEC-03 | HTTPS über Caddy (`tls internal`) auf der festen Server-IP (optional zusätzlich Hostname). Das Caddy-Root-Zertifikat wird auf die Büro-PCs verteilt. |
| N-SEC-04 | Keine Portfreigaben am LANCOM-Router, kein VPN. |
| N-SEC-05 | Secrets (Brave-Key, `WEBUI_SECRET_KEY`) liegen in `/srv/ki/.env` mit Rechten 600, nicht im git. |
| N-SEC-06 | SSH nur mit Schlüssel, Passwort-Login aus. Automatische Sicherheitsupdates aktiv (`unattended-upgrades`). |

### 7.4 Datenschutz und Recht

| ID | Anforderung |
|---|---|
| N-DSG-01 | Eintrag im Verzeichnis von Verarbeitungstätigkeiten (lokale KI, Brave als externer Dienst, Löschfrist 90 Tage, befristeter Betrieb). |
| N-DSG-02 | Chats werden 90 Tage nach der letzten Aktivität automatisch gelöscht (F-UI-10). |
| N-DSG-03 | Mitarbeiter-Leitlinie zur Websuche: In Chats mit Kunden- oder Personendaten die Websuche aus lassen; keine Namen, Aktenzeichen oder internen Projektnamen in Suchfragen. |
| N-DSG-04 | KI-Kompetenz nach Art. 4 KI-VO: kurze Einweisung (ca. 1 Stunde) mit Teilnehmerliste dokumentieren. |
| N-DSG-05 | Bei Abschaltung werden alle Büro-Daten vollständig gelöscht (Abschnitt 10). |
| N-DSG-06 | Brave-Bedingungen sind bekannt und akzeptiert: US-Anbieter, Suchanfragen werden bis zu 90 Tage gespeichert, der DPA umfasst Suchanfragen nicht. |
| N-DSG-07 | Modell-Lizenz: Qwen3.8-27B steht unter Apache 2.0, gewerbliche Nutzung ist erlaubt. |
| N-DSG-08 | Claude Code (Cloud-Dienst) wird nur für Einrichtung und Wartung genutzt und liest keine Büro-Daten (Abschnitt 9.2). |

---

## 8. Technische Spezifikation

### 8.1 Treiber

```bash
sudo apt update && sudo apt upgrade -y
sudo ubuntu-drivers list
sudo apt install nvidia-driver-595-open
sudo reboot
nvidia-smi          # RTX 5090 mit 32 GB muss erscheinen
```

### 8.2 llama.cpp bauen

```bash
sudo apt install -y build-essential cmake git libcurl4-openssl-dev nvidia-cuda-toolkit
git clone https://github.com/ggml-org/llama.cpp /opt/llama.cpp
cmake -S /opt/llama.cpp -B /opt/llama.cpp/build -DGGML_CUDA=ON -DBUILD_SHARED_LIBS=OFF
cmake --build /opt/llama.cpp/build --config Release -j --target llama-server
```

> Den getesteten Commit dokumentieren und fixieren. Prüfen, ob die CUDA-Toolkit-Version aus den Ubuntu-Quellen Blackwell (sm_120) unterstützt; sonst das CUDA-Toolkit aus dem NVIDIA-Repository verwenden.

### 8.3 Modell herunterladen

```bash
pip install -U "huggingface_hub[cli]"
hf download unsloth/Qwen3.8-27B-GGUF \
  --include "*UD-Q4_K_XL*" "mmproj*" \
  --local-dir /srv/models/qwen3.8-27b
```

> Dateinamen des mmproj im Repo prüfen (z. B. `mmproj-F16.gguf`).

### 8.4 llama-server als systemd-Dienst

`/etc/systemd/system/llama-server.service`:

```ini
[Unit]
Description=llama.cpp server (Qwen3.8-27B UD-Q4_K_XL)
After=network-online.target
Wants=network-online.target

[Service]
User=llm
Group=llm
ExecStart=/opt/llama.cpp/build/bin/llama-server \
  -m /srv/models/qwen3.8-27b/Qwen3.8-27B-UD-Q4_K_XL.gguf \
  --mmproj /srv/models/qwen3.8-27b/mmproj-F16.gguf \
  --alias qwen3.8-27b \
  -ngl 99 -fa on \
  -c 131072 -np 2 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --jinja \
  --chat-template-kwargs '{"reasoning_effort":"medium"}' \
  --spec-type draft-mtp --spec-draft-n-max 3 \
  --metrics \
  --host 127.0.0.1 --port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo useradd -r -s /usr/sbin/nologin llm
sudo chown -R llm:llm /srv/models
sudo systemctl daemon-reload
sudo systemctl enable --now llama-server
curl -s http://127.0.0.1:8080/health
```

> Die MTP-Flags (`--spec-type`, `--spec-draft-n-max`) haben sich zwischen llama.cpp-Versionen geändert. Vor dem Rollout mit `llama-server --help` gegen den fixierten Build prüfen.

### 8.5 Leistungslimit der GPU

`/etc/systemd/system/gpu-powerlimit.service`:

```ini
[Unit]
Description=Set RTX 5090 power limit
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl 400

[Install]
WantedBy=multi-user.target
```

### 8.6 Open WebUI (Docker Compose)

`/srv/ki/docker-compose.yml`:

```yaml
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:v0.11.4   # Version fixieren
    container_name: open-webui
    network_mode: host
    restart: always
    volumes:
      - open-webui:/app/backend/data
    env_file: .env
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    environment:
      HOST: "127.0.0.1"
      PORT: "3000"
      WEBUI_URL: "https://<SERVER_IP>"      # bzw. https://<HOSTNAME>
      # Modell-Anbindung
      ENABLE_OLLAMA_API: "false"
      OPENAI_API_BASE_URL: "http://127.0.0.1:8080/v1"
      OPENAI_API_KEY: "none"
      # Privatsphäre
      ENABLE_ADMIN_CHAT_ACCESS: "false"
      # Native / Agentic Function Calling als Standard
      DEFAULT_MODEL_PARAMS: '{"function_calling":"native"}'
      # Websuche: Brave
      ENABLE_WEB_SEARCH: "true"
      WEB_SEARCH_ENGINE: "brave"
      WEB_SEARCH_RESULT_COUNT: "5"
      WEB_SEARCH_CONCURRENT_REQUESTS: "1"
      WEB_LOADER_CONCURRENT_REQUESTS: "2"
      WEB_FETCH_MAX_CONTENT_LENGTH: "20000"
      # Hintergrundlast reduzieren
      ENABLE_AUTOCOMPLETE_GENERATION: "false"

volumes:
  open-webui:
```

`/srv/ki/.env` (Rechte 600, nicht im git; der Admin trägt den Brave-Key selbst ein):

```bash
WEBUI_SECRET_KEY=<openssl rand -hex 32>
BRAVE_SEARCH_API_KEY=<Brave-Key>
```

> **Wichtig:** Viele Open-WebUI-Einstellungen werden nach dem ersten Start in der Datenbank gespeichert. Sobald sie einmal im Admin-Panel gespeichert wurden, hat der Datenbankwert Vorrang vor der Umgebungsvariable. Spätere Änderungen deshalb im Admin-Panel vornehmen.

**Ersteinrichtung:** Nach dem ersten Start legt der Admin sein Konto an (der erste Nutzer wird Admin). Danach im Admin-Panel die Registrierung deaktivieren und die übrigen Konten anlegen.

### 8.7 Caddy (HTTPS im LAN)

```bash
sudo apt install -y caddy
```

`/etc/caddy/Caddyfile`:

```
https://<SERVER_IP> {
    tls internal
    reverse_proxy 127.0.0.1:3000
}
```

- Optional: Im LANCOM einen lokalen DNS-Eintrag `<HOSTNAME>` → `<SERVER_IP>` anlegen und den Hostnamen zusätzlich als Site-Adresse in Caddy eintragen.
- Caddy-Root-Zertifikat (`/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`) auf den Büro-PCs als vertrauenswürdige Stammzertifizierungsstelle installieren (ggf. per Gruppenrichtlinie).

### 8.8 Netzwerk und Firewall

Feste IP per Netplan (Werte aus 5.1), z. B. `/etc/netplan/01-ki.yaml`:

```yaml
network:
  version: 2
  ethernets:
    <INTERFACE>:
      addresses: [<SERVER_IP>/24]
      routes:
        - to: default
          via: <GATEWAY_IP>
      nameservers:
        addresses: [<DNS_SERVER>]
```

Firewall (**die SSH-Regel muss vor `ufw enable` gesetzt sein**, sonst sperrt man sich aus):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from <ADMIN_IP> to any port 22 proto tcp
sudo ufw allow from <BUERO_SUBNETZ> to any port 443 proto tcp
sudo ufw enable
```

### 8.9 Modell-Profile in Open WebUI

Entscheidung: Denkstufe **`medium`** für alle Aufgaben. Damit gelten die offiziellen Sampling-Werte für den Thinking-Modus. Im Admin-Panel unter Modelle werden auf Basis von `qwen3.8-27b` zwei Profile angelegt:

| Einstellung | Qwen3.8 (Browser-Chat) | qwen38-code (Coding-Agenten) |
|---|---|---|
| Modell-ID | z. B. `qwen38` | **`qwen38-code`** (wird in Pi eingetragen) |
| Zweck | Büro, Analyse, Coding im Chat | Pi, Cline, Aider, Continue |
| Sichtbar für | alle Nutzer | Nutzer mit API-Berechtigung (bzw. Gruppe „Entwicklung“) |
| `chat_template_kwargs` (Custom Parameter) | `{"reasoning_effort":"medium"}` | `{"reasoning_effort":"medium"}` |
| temperature / top_p / top_k / min_p | 1.0 / 0.95 / 20 / 0 | 1.0 / 0.95 / 20 / 0 |
| presence_penalty / repetition_penalty | 0 / 1.0 | 0 / 1.0 |
| System-Prompt | ja (siehe unten) | **keiner** (Agenten bringen eigene mit) |
| Function Calling | Native | Native |
| Capability Web Search | an | **aus** |
| Eingebaute Werkzeuge (Memory, Code Interpreter, Wissensdatenbanken) | nach Bedarf | **aus**, damit nur die Werkzeuge des Agenten beim Modell ankommen |
| Capability Vision | an | an |

**System-Prompt (nur Profil „Qwen3.8“):**

```
Du bist der KI-Assistent des Büros. Antworte auf Deutsch, sachlich und in der Sie-Form,
sofern nicht anders gewünscht.

Websuche:
- Nutze die Websuche nur, wenn aktuelle oder externe Informationen nötig sind.
- Lies für wichtige Fakten mindestens eine Quelle mit fetch_url und nenne die URL.
- Wenn die Suche keine oder unpassende Ergebnisse liefert, sage das ausdrücklich.
  Erfinde keine aktuellen Fakten, Daten, Preise oder Fristen.
- Übernimm keine Personen-, Kunden- oder Firmennamen aus dem Chat in Suchanfragen,
  es sei denn, der Nutzer verlangt es ausdrücklich.
```

> Falls `medium` bei einfachen Bürotexten im Pilotbetrieb zu langsam wirkt, kann ein zweites Profil mit `{"reasoning_effort":"low"}` ergänzt werden. `xhigh` nur gezielt für sehr schwierige Aufgaben.

### 8.10 Brave Search API (manuell durch den Admin)

1. Konto unter api-dashboard.search.brave.com anlegen (Kreditkarte erforderlich).
2. Plan **Search** wählen: $5 pro 1.000 Anfragen, $5 Gratisguthaben pro Monat (≈ 1.000 Anfragen).
3. **Ausgabenlimit setzen** (Vorschlag: $20/Monat).
4. API-Key selbst in `/srv/ki/.env` eintragen.
5. Attributionsbedingung für das Gratisguthaben prüfen und ggf. erfüllen oder bewusst bezahlen.

**Kostenschätzung:** Bei etwa 1.050 Fragen mit Websuche pro Monat und 1,5–3 Anfragen pro Frage ergeben sich ca. 1.600–3.200 Anfragen, also **ca. $3–11 pro Monat**. Bei 25 Konten kann es mehr werden; das Ausgabenlimit begrenzt das Risiko.

### 8.11 Automatische Löschung nach 90 Tagen

1. **Zuerst prüfen**, ob die fixierte Open-WebUI-Version eine eingebaute Aufbewahrungs- bzw. Auto-Löschfunktion für Chats hat. Falls ja, diese mit 90 Tagen nutzen.
2. **Falls nicht:** Ein täglicher systemd-Timer (`chat-retention.timer`) führt ein Skript aus, das
   - Chats löscht, deren letzte Aktivität älter als 90 Tage ist,
   - hochgeladene Dateien löscht, die zu keinem verbleibenden Chat und keiner Wissensdatenbank mehr gehören,
   - Wissensdatenbanken (bewusst gespeicherte Vorlagen) **nicht** anfasst,
   - die Anzahl gelöschter Einträge (ohne Inhalte) ins Journal schreibt.
3. Umsetzung bevorzugt über die Open-WebUI-API. Direkter Datenbankzugriff nur nach Prüfung des Schemas der fixierten Version, und nur, während der Container gestoppt ist oder die DB das zulässt.
4. Vor der Produktivsetzung mit Testdaten verifizieren (Abnahme A13).

journald begrenzen (`/etc/systemd/journald.conf.d/retention.conf`):

```ini
[Journal]
MaxRetentionSec=30day
SystemMaxUse=1G
```

### 8.12 Anbindung des Coding-Agenten Pi

Pi läuft auf den Arbeitsplatz-Rechnern der Entwickler. Die Rechner richtet Claude Code nicht ein; es legt nur die Vorlage `/srv/ki/client/pi-models.json` an und schreibt eine Kurzanleitung in `ADMIN.md`.

1. **Voraussetzungen in Open WebUI:** API-Schlüssel global aktiviert, Berechtigung „API Keys“ für die betreffenden Nutzer, Profil `qwen38-code` angelegt (8.9).
2. **Persönlicher Schlüssel:** Jede/r Entwickler/in erstellt unter *Einstellungen → Konto* einen eigenen API-Schlüssel.
3. **Pi konfigurieren** in `~/.pi/agent/models.json`:

```json
{
  "providers": {
    "buero-ki": {
      "baseUrl": "https://<SERVER_IP>/api",
      "api": "openai-completions",
      "apiKey": "sk-...persönlicher-Open-WebUI-Schlüssel...",
      "models": [
        { "id": "qwen38-code", "input": ["text", "image"] }
      ]
    }
  }
}
```

4. **Caddy-Zertifikat für Node.js:** Pi läuft unter Node.js, und Node vertraut der Caddy-Zertifizierungsstelle nicht automatisch, auch wenn sie im Betriebssystem installiert ist.
   - Linux/macOS: `export NODE_EXTRA_CA_CERTS=/pfad/zu/caddy-root.crt` (z. B. in `~/.bashrc`)
   - Windows: Benutzer-Umgebungsvariable `NODE_EXTRA_CA_CERTS` auf den Pfad der `root.crt` setzen
5. **Test:** In Pi mit `/model` das Modell `qwen38-code` wählen und Abnahmetest A15 durchführen.

**Hinweise:**
- Die `models.json` enthält den persönlichen Schlüssel. Sie darf nicht geteilt und nicht in ein Git-Repository eingecheckt werden.
- Ein Agent belegt bei längeren Aufgaben einen der zwei Slots oft minutenlang. Andere Anfragen warten dann gegebenenfalls kurz.
- **Alternative auf dem Server selbst (per SSH):** `"baseUrl": "http://127.0.0.1:8080/v1"`, `"apiKey": "none"`, Modell-ID `qwen3.8-27b`. Dann gelten die Profil-Einstellungen aus Open WebUI nicht; die Denkstufe `medium` kommt vom Server-Standard.

---

## 9. Umsetzung mit Claude Code

### 9.1 Vorbereitung (manuell)

1. BIOS-Einstellungen (4.1).
2. Ubuntu 26.04 LTS Server installieren, Benutzer mit sudo-Rechten anlegen, OpenSSH aktivieren.
3. Parameter in 5.1 ausfüllen. Feste IP entweder schon bei der Installation setzen oder durch Claude Code (8.8).
4. Claude Code auf dem Server installieren und anmelden (Anleitung: docs.claude.com).
5. `/srv/ki` anlegen, diese `PRD.md` dorthin kopieren, `git init`.
6. Brave-Konto anlegen (8.10). Den Key trägt der Admin selbst in `.env` ein, sobald Claude Code die Datei angelegt hat.

### 9.2 Datenschutz beim Einsatz von Claude Code

- Claude Code ist ein Cloud-Dienst: Dateien, die es liest, und Ausgaben von Befehlen, die es ausführt, werden an Anthropic übertragen.
- Deshalb die **Einrichtung abschließen, bevor echte Büro-Daten auf dem Server liegen**.
- Später (Wartung, Updates) darf Claude Code **keine Büro-Daten** lesen: nicht das Open-WebUI-Volume, nicht die Datenbank, nicht `.env`, keine Chat-Inhalte in Logs. Das Löschskript (8.11) wird vor dem Echtbetrieb mit Testdaten fertiggestellt.

### 9.3 Arbeitsregeln für Claude Code

1. Phasen in der Reihenfolge von 9.4 umsetzen. Nach jeder Phase die zugehörigen Abnahmetests (Abschnitt 11) ausführen.
2. Jede Phase in `/srv/ki/SETUP-LOG.md` dokumentieren: was gemacht wurde, Versionen (llama.cpp-Commit, Open-WebUI-Tag, Treiberversion), Testergebnisse, Abweichungen von der PRD.
3. Flags und Optionen gegen die installierte Version prüfen (`--help`, aktuelle Doku), statt sie anzunehmen. Abweichungen von dieser PRD dokumentieren und kurz begründen.
4. **Vor Neustarts** (Treiber) Bescheid geben. Nach dem Neustart wird die Sitzung fortgesetzt.
5. **Firewall:** SSH-Regel für `ADMIN_IP` immer vor `ufw enable` setzen.
6. Keine Ports außer 443 (LAN) und 22 (Admin) öffnen. Keine Änderungen am LANCOM-Router.
7. `.env` nicht lesen und nicht ausgeben. Secrets nicht ins git.
8. Nichts außerhalb von `/srv/ki`, `/srv/models`, `/opt/llama.cpp`, `/etc/systemd/system`, `/etc/caddy`, `/etc/netplan` und den genannten Konfigurationsdateien löschen oder überschreiben, ohne zu fragen.
9. Skripte idempotent schreiben (mehrfach ausführbar ohne Schaden) und unter `/srv/ki/scripts` ablegen.
10. Konfigurationsdateien (ohne Secrets) nach jeder Phase ins git committen.

### 9.4 Phasen

| Phase | Inhalt | Fertig, wenn |
|---|---|---|
| P1 Basissystem | Updates, feste IP (falls noch nicht gesetzt), SSH-Härtung, ufw, unattended-upgrades, journald-Begrenzung | A11 (vorläufig) bestanden, SSH funktioniert weiterhin |
| P2 Treiber | `nvidia-driver-595-open`, Neustart, Leistungslimit-Dienst | A1 bestanden |
| P3 Inferenz | CUDA-Toolkit, llama.cpp bauen, Modell laden, systemd-Dienst | `/health` ok, A3, A4, A14 bestanden |
| P4 Oberfläche | Docker, Open WebUI, Caddy | Anmeldeseite per `https://<SERVER_IP>` aus dem LAN erreichbar |
| P5 Konfiguration | Admin-Konto (durch den Admin), Registrierung aus, beide Modell-Profile aus 8.9, System-Prompt, API-Schlüssel-Berechtigung, Pi-Vorlage (8.12), Brave (Key durch den Admin) | A5–A10, A12, A15 bestanden |
| P6 Löschung | Aufbewahrung 90 Tage (8.11) | A13 bestanden |
| P7 Übergabe | Alle Abnahmetests, SETUP-LOG vollständig, kurze Admin-Anleitung (Konten anlegen, Neustart, Pi-Anbindung, Abschaltung) in `/srv/ki/ADMIN.md` | Alle Tests in Abschnitt 11 bestanden |

### 9.5 Vorschlag für den Start-Prompt

```
Lies /srv/ki/PRD.md vollständig. Setze danach Phase P1 aus Abschnitt 9.4 um und halte
dich an die Arbeitsregeln in 9.3. Die Parameter aus 5.1 lauten: SERVER_IP=…, GATEWAY_IP=…,
DNS_SERVER=…, BUERO_SUBNETZ=…, ADMIN_IP=…, INTERFACE=… . Frag nach, bevor du etwas tust,
das die SSH-Verbindung unterbrechen könnte. Melde dich nach jeder Phase mit dem Ergebnis
der Tests, bevor du mit der nächsten Phase beginnst.
```

---

## 10. Abschaltung und Rückbau

Wenn der Server für ein anderes Projekt verwendet wird:

1. Nutzer rechtzeitig informieren, damit sie benötigte Texte selbst sichern.
2. Dienste stoppen: `docker compose down`, `systemctl disable --now llama-server caddy chat-retention.timer`.
3. **Büro-Daten löschen:** Docker-Volume `open-webui` entfernen (`docker volume rm`), `/srv/ki/.env` löschen, Journal leeren (`journalctl --rotate && journalctl --vacuum-time=1s`).
4. Brave: API-Key widerrufen, Abo/Zahlungsmethode kündigen.
5. Caddy-Root-Zertifikat von den Büro-PCs entfernen.
6. Wird das System neu installiert: SSD vorher sicher löschen (z. B. NVMe Secure Erase / `nvme format` mit Secure-Erase-Option, oder `blkdiscard`).
7. Verzeichnis von Verarbeitungstätigkeiten aktualisieren (Verarbeitung beendet, Datum der Löschung).

Modelldateien (`/srv/models`) und llama.cpp enthalten keine Büro-Daten und können für das neue Projekt bleiben.

---

## 11. Abnahmekriterien

| # | Test | Erwartung |
|---|---|---|
| A1 | `nvidia-smi` nach Neustart | RTX 5090 erkannt, Leistungslimit 400 W gesetzt |
| A2 | Server-Neustart | llama-server, Open WebUI und Caddy laufen ohne manuellen Eingriff |
| A3 | Leistung 1 Anfrage (500-Wörter-E-Mail, Denkstufe `medium`) | ≥ 100 Token/s, < 30 s gesamt inkl. Denkphase |
| A4 | Leistung 2 parallele Anfragen | beide laufen, je ≥ 50 Token/s; eine dritte wartet und wird danach beantwortet |
| A5 | Bild/Scan hochladen (Rechnung) | Inhalt wird korrekt ausgelesen |
| A6 | PDF mit ca. 20 Seiten | Zusammenfassung ohne Fehler, Kontext reicht |
| A7 | Websuche: „Was hat der Bundestag diese Woche beschlossen?“ | Modell ruft `search_web` und `fetch_url` auf, Antwort nennt Quellen-URLs |
| A8 | Websuche mit absichtlich ungültigem Brave-Key | Modell meldet, dass die Suche fehlgeschlagen ist, erfindet keine Fakten |
| A9 | Zwei Nutzer | Nutzer A sieht keine Chats von Nutzer B; Admin sieht keine fremden Chats |
| A10 | Registrierung ohne Admin | nicht möglich |
| A11 | Port-Scan aus dem LAN | nur 443 offen (22 nur vom Admin-PC); 3000 und 8080 nicht erreichbar |
| A12 | IDE-Anbindung (Continue o. Ä.) mit persönlichem API-Schlüssel | Chat-Anfrage aus der IDE funktioniert |
| A13 | Löschung: Test-Chat mit Aktivität älter als 90 Tage (künstlich gesetzt) und aktueller Test-Chat | Alter Chat samt Datei gelöscht, aktueller Chat und Wissensdatenbanken bleiben |
| A14 | VRAM unter Last (2 Slots, langer Kontext) | ≤ 29 GB |
| A15 | Pi auf einem Arbeitsplatz-Rechner mit `models.json` (8.12) und persönlichem Schlüssel: in einem Testprojekt „Lies README.md und fasse sie zusammen“ | Pi ruft sein Lese-Werkzeug auf, das Modell antwortet auf Basis der Datei; kein Zertifikatsfehler; kein Office-System-Prompt in der Antwort erkennbar |

---

## 12. Risiken und Gegenmaßnahmen

| Risiko | Auswirkung | Gegenmaßnahme |
|---|---|---|
| Qwen3.8 „denkt“ zu lange | Lange Wartezeiten | Denkstufe `medium` statt Standard `xhigh`; bei Bedarf zusätzliches `low`-Profil |
| Mehr als 2 gleichzeitige Anfragen (25 Konten) | Wartezeiten | Warteschlange ist eingeplant; bei regelmäßigem Stau `-np 3` testen (VRAM prüfen) oder Wechsel auf vLLM |
| Coding-Agent belegt einen Slot über längere Zeit | Wartezeiten für andere | Ist eingeplant; bei Stau `-np 3` testen (VRAM prüfen) oder lange Agenten-Aufgaben in Randzeiten |
| Tool Calls von Pi werden über Open WebUI nicht korrekt durchgereicht | Pi kann keine Dateien lesen oder Befehle ausführen | Eingebaute Werkzeuge und System-Prompt im Profil `qwen38-code` aus, Test A15; notfalls Pi per SSH direkt am llama-server |
| Deutsche Sprachqualität (Sprachmischung, erfundene Wörter) | Unsaubere Kundentexte | System-Prompt „nur Deutsch“, ausgehende Texte gegenlesen |
| Bugs in llama.cpp (MTP, sehr langer Kontext, DeltaNet-Kernel) | Abstürze, falsche Ausgaben | Build fixieren, Kontext begrenzen, Updates erst testen; MTP notfalls abschalten |
| Brave: 429-Fehler bei gleichzeitigen Suchen | Suche liefert nichts | `WEB_SEARCH_CONCURRENT_REQUESTS=1`, Fallback SearXNG vorbereiten |
| Brave: Kosten | Unerwartete Abbuchung | Ausgabenlimit im Dashboard, monatliche Kontrolle |
| Personendaten in Suchanfragen | Datenschutzverstoß | Leitlinie, System-Prompt, Websuche nicht als Default |
| Halluzinationen bei fehlgeschlagener Suche | Falsche Fakten | System-Prompt, Quellenpflicht, Test A8 |
| Open-WebUI-Update ändert Einstellungen/Variablen | Funktionen fallen aus | Image-Tag fixieren, Updates nur nach Test |
| Löschskript löscht zu viel oder zu wenig | Datenverlust bzw. Verstoß gegen Löschfrist | Test A13 mit Testdaten, Logging der Anzahl gelöschter Einträge |
| Hardwaredefekt | Ausfall, Chats verloren (keine Backups, bewusst akzeptiert) | Neuinstallation nach PRD und git-Konfiguration |
| Claude Code liest versehentlich Büro-Daten | Daten gehen an einen Cloud-Dienst | Regeln 9.2/9.3, Wartung nur mit klarer Aufgabe ohne Datenzugriff |

---

## 13. Offene Punkte

| # | Frage | Verantwortlich |
|---|---|---|
| O1 | Konkrete Werte für 5.1 (IP, Gateway, DNS, Subnetz, Admin-IP, Netzwerk-Interface) | IT |
| O2 | Gruppen und gemeinsame Wissensdatenbanken gewünscht? | Geschäftsführung |
| O3 | Wer legt das Brave-Konto an und hinterlegt die Zahlungsmethode? | Geschäftsführung |
| O4 | Reicht `medium` im Büroalltag vom Tempo her, oder wird zusätzlich ein `low`-Profil gebraucht? | IT (Pilot) |
| O5 | Später Staan (EU-Suchanbieter) gegen Brave testen? | IT |

---

## 14. Ausblick (nur falls der Betrieb verlängert wird)

- Tab-Autovervollständigung in der IDE mit kleinem FIM-Modell (z. B. Qwen2.5-Coder-1.5B) als zweiter llama-server.
- Bessere Dokumentensuche mit eigenem Embedding- und Reranker-Modell (z. B. Qwen3-Embedding-0.6B + bge-reranker-v2-m3).
- Meeting-Transkription (Whisper / WhisperX) als Batch-Job.
- Automatischer Such-Fallback (Brave → SearXNG) über eine eigene „External“-Engine.
- Wechsel auf vLLM, falls regelmäßig 3+ Personen gleichzeitig generieren.
