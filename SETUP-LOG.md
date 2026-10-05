# SETUP-LOG KI-Server

## Parameter (PRD 5.1)

| Parameter | Wert |
|---|---|
| SERVER_IP | 192.168.10.129 |
| GATEWAY_IP | 192.168.10.7 |
| DNS_SERVER | 192.168.10.9 |
| BUERO_SUBNETZ | 192.168.10.0/24 |
| ADMIN_IP | entfällt (siehe Abweichung P1-A1) |
| INTERFACE | eno1 |

---

## P1 Basissystem – 2026-10-03

**System:** Ubuntu 26.04.1 LTS, Kernel 7.0.0-38-generic, Hostname ki-server

### Durchgeführt

| Schritt | Ergebnis |
|---|---|
| Updates | `apt update && apt upgrade`: 0 Pakete offen, kein Neustart nötig |
| Feste IP | Bereits vorhanden: `/etc/netplan/01-ki-server.yaml` (eno1, 192.168.10.129/24, GW .7, DNS .9), cloud-init-Netzwerk deaktiviert. Unverändert. |
| SSH-Schlüssel | ED25519-Schlüssel des Admins in `~msb/.ssh/authorized_keys` hinterlegt, Anmeldung per Schlüssel im Journal bestätigt |
| SSH-Härtung | `/etc/ssh/sshd_config.d/10-ki-hardening.conf` (Quelle: `etc/ssh/…`, Skript `scripts/p1-ssh-hardening.sh`): PasswordAuthentication no, KbdInteractiveAuthentication no, PermitRootLogin no. Datei hat Vorrang vor `50-cloud-init.conf` (sshd: erster Treffer gilt). |
| ufw | `scripts/p1-ufw.sh 192.168.10.0/24`: deny incoming, allow outgoing, 22/tcp und 443/tcp nur aus 192.168.10.0/24. Beim Boot aktiv. IPv6: keine Freigaben (alles eingehend gesperrt). |
| unattended-upgrades | Version 2.12ubuntu9, aktiv, `20auto-upgrades` mit Update-Package-Lists=1 / Unattended-Upgrade=1, Security-Quelle aktiv |
| journald | `/etc/systemd/journald.conf.d/retention.conf` (Skript `scripts/p1-journald.sh`): MaxRetentionSec=30day, SystemMaxUse=1G |

Alle Skripte zweimal ausgeführt – zweiter Lauf ohne Änderungen (idempotent).

### Tests

| Test | Ergebnis |
|---|---|
| Passwort-Login | abgelehnt: `Permission denied (publickey)` ✅ |
| Schlüssel-Login aus dem LAN (192.168.10.142) | funktioniert ✅ |
| Root-Login | `permitrootlogin no` ✅ |
| Lauschende Ports außerhalb localhost | nur 22/tcp ✅ (443 folgt in P4) |
| A11 (vorläufig), Port-Scan vom Büro-PC 192.168.10.142 | 22: offen, 443: zu (Caddy erst in P4), 3000: zu, 8080: zu ✅ – 443 in P4 erneut prüfen |

### Abweichungen von der PRD

- **P1-A1 – SSH aus dem ganzen Büronetz statt nur von ADMIN_IP** (N-SEC-01, 8.8): Auf Wunsch des Admins entfällt die Beschränkung auf eine einzelne Admin-IP. SSH ist aus 192.168.10.0/24 erlaubt, aber nur mit Schlüssel (Passwort-Login aus). Damit ist A11 so zu lesen: „22 aus dem Büronetz, nur per Schlüssel“.

---

## P2 Treiber – 2026-10-03

### Auswahl

- NVIDIA-Stand am 2026-10-03 (download.nvidia.com, Release-Meldungen): Production Branch (stable) **R595**, neueste Version 595.104.02 (23.09.2026). R610/R615 sind New-Feature-Branches.
- Ubuntu 26.04 (resolute-updates/-security) und das NVIDIA-CUDA-Repo (ubuntu2604) bieten bisher nur **595.91.07**.
- Entscheidung des Admins: Ubuntu-Paket 595.91.07. Automatische Updates (auch auf 595.104.02, sobald verfügbar) kommen über unattended-upgrades, die Kernel-Module laufen mit dem Kernel-Metapaket mit. Kein `.run`-Installer.
- Secure Boot: deaktiviert.

### Durchgeführt

| Schritt | Ergebnis |
|---|---|
| Treiber | `scripts/p2-nvidia-driver.sh`: `nvidia-headless-595-open`, `nvidia-utils-595` 595.91.07-0ubuntu0.26.04.1, `linux-modules-nvidia-595-open-generic` 7.0.0-38.38+1 (vorgebaute offene Kernel-Module) |
| nouveau | durch `/lib/modprobe.d/nvidia-graphics-drivers.conf` gesperrt, nach dem Neustart nicht geladen |
| Neustart | 2026-10-03 14:57 UTC, SSH/ufw/Härtung danach unverändert aktiv |
| Leistungslimit | `/etc/systemd/system/gpu-powerlimit.service` (Quelle `etc/systemd/system/`, Skript `scripts/p2-gpu-powerlimit.sh`), aktiviert |

### Tests

| Test | Ergebnis |
|---|---|
| A1 `nvidia-smi` nach Neustart | NVIDIA GeForce RTX 5090, 32607 MiB, Treiber 595.91.07 (Open Kernel Module), CUDA 13.2, PCIe Gen5 x16 ✅ |
| A1 Leistungslimit | 400 W (Standard 575 W, Bereich 400–600 W), Persistence Mode an, Dienst `active (exited)`, Journal: „set to 400.00 W from 575.00 W“ ✅ |

### Abweichungen von der PRD

- **P2-A1 – `nvidia-headless-595-open` statt `nvidia-driver-595-open`** (1, 8.1): gleicher Treiber und gleiche Kernel-Module mit `nvidia-smi` und CUDA-Bibliotheken, aber 13 statt 142 Pakete, ohne Xorg/GTK. Auf dem Server gibt es keinen Desktop, die Bildschirmausgabe läuft über die iGPU.
- **P2-A2 – Treiberversion 595.91.07 statt der neuesten Stable-Version 595.104.02**: Die neuere Version ist noch nicht als Ubuntu-Paket verfügbar (siehe Auswahl).
- **P2-A3 – `gpu-powerlimit.service`** (8.5): `RemainAfterExit=yes` (Status bleibt sichtbar) und `After=nvidia-persistenced.service` ergänzt.
- Hinweis: 400 W ist das **Minimum**, das der Treiber für diese Karte zulässt. Ein niedrigeres Limit ist nicht möglich.

---

## P3 Inferenz – 2026-10-03

### Durchgeführt

| Schritt | Ergebnis |
|---|---|
| CUDA-Toolkit | `scripts/p3-cuda-toolkit.sh`: `cuda-toolkit-13-3` 13.3.1-1 (nvcc V13.3.73) aus dem NVIDIA-Repo `ubuntu2604`, per `apt-mark hold` fixiert. Ubuntu-Paket `nvidia-cuda-toolkit` ist nur 12.4 (kein sm_120). Pinning `/etc/apt/preferences.d/nvidia-cuda-repo` (Priorität 100): Treiberpakete kommen weiter von Ubuntu. |
| llama.cpp | `scripts/p3-build-llama.sh`: Tag **b11378**, Commit `edd6e2bbdad5930899a93db8fa73c3b61c7b9bcc`, CUDA-Arch `120a`, statisch, Ziele `llama-server` und `llama-bench`. Build vom Admin gestartet (Claude-Code-Sicherheitsprüfung hatte den Aufruf blockiert). |
| Modell | `scripts/p3-download-model.sh`: `Qwen3.8-27B-UD-Q4_K_XL.gguf` (17.559.178.144 Byte) und `mmproj-F16.gguf` (927.607.488 Byte) aus `unsloth/Qwen3.8-27B-GGUF`, SHA256 gegen das HF-Repo geprüft ✅. Download per curl statt `hf`-CLI. 10 Verbindungsabbrüche (`Connection reset by peer`) wurden per Wiederaufnahme überbrückt. |
| MTP | Die MTP-Schichten sind in der Modelldatei enthalten (`blk.64.nextn.*`, `qwen35.nextn_predict_layers`), keine separate `mtp-*.gguf` nötig. Log: „creating MTP draft context against the target model“. |
| Dienst | `etc/systemd/system/llama-server.service`, `scripts/p3-llama-service.sh`. Flags gegen den Quellcode von b11378 geprüft (`--spec-type draft-mtp`, `--spec-draft-n-max`, `--chat-template-kwargs`, `-fa on`, `--cache-type-k/v`, `--metrics`): alle unverändert gültig. Läuft als `llm`, lauscht nur auf 127.0.0.1:8080. |

Server-Hinweise im Log (bewertet, keine Änderung):
- „no API key is set“: unkritisch, da nur 127.0.0.1 und ufw.
- „Qwen-VL … try adding --image-min-tokens 1024“: nur für Grounding-Aufgaben relevant, bei A5 beobachten.
- „chat template supports preserving reasoning, enabled by default“: Hinweis zur Token-Nutzung.

### Tests (synthetische Prompts, `scripts/p3-bench.py`, Rohdaten in `bench/p3-2026-10-03/`)

Leistungslimit 400 W (Betriebseinstellung) und Vergleich 575 W (Treiber-Standard). Eindeutige Test-ID je Anfrage, kein Prompt-Cache.

| Messung | 400 W | 575 W |
|---|---|---|
| A3: 500-Wörter-E-Mail, Generierung (3 Läufe) | 127,7 / 123,5 / 125,3 Token/s | 147,7 / 120,2 / 118,3 Token/s |
| A3: Gesamtzeit inkl. Denkphase | 19,2 / 21,2 / 19,8 s | 18,4 / 11,2 / 12,8 s |
| A3: erste sichtbare Antwort | 13–15 s | 2–14 s |
| A4: 2 parallel, je | 109,0 / 98,4 Token/s | 121,2 / 123,6 Token/s |
| A4: 3. Anfrage | wartet bis Slot frei (Denkbeginn nach 15,8 s), wird beantwortet | wartet (19,0 s), wird beantwortet |
| Prefill langer Kontext (54k Tokens, 2 Slots) | ca. 1.920 Token/s | ca. 2.460 Token/s |
| Leistungsaufnahme unter Last (Mittel / Spitze) | 378–398 W / 413 W | 489–567 W / 588 W |
| Max. GPU-Temperatur | 66 °C | 77 °C |
| A14: VRAM (2 Slots × 54k Kontext) | 24.676 MiB | 24.678 MiB |

Die Generierungsrate schwankt stark mit der MTP-Annahmequote (0,43–0,65 je Lauf). Bei vergleichbarer Quote (~0,62) liefert 575 W etwa 15–20 % mehr Token/s, beim Prefill etwa 28 % mehr. Die PRD-Annahme „kaum Tempoverlust“ bei 400 W trifft damit nur eingeschränkt zu, die Zielwerte werden aber auch mit 400 W erreicht. Ein früherer Einzellauf bei 400 W mit niedriger Quote (0,43) lag bei 99,6 Token/s, also knapp unter 100.

| Test | Ergebnis |
|---|---|
| `/health` | `{"status":"ok"}` ✅ |
| A3 (≥ 100 Token/s, < 30 s) | ✅ bei 400 W (123–128 Token/s, ≤ 21,2 s); Einzelläufe mit niedriger MTP-Quote können knapp unter 100 Token/s liegen |
| A4 (je ≥ 50 Token/s, 3. wartet) | ✅ |
| A14 (VRAM ≤ 29 GB) | ✅ 24,1 GiB; der KV-Cache wird beim Start komplett reserviert, der Wert ist lastunabhängig |
| N-PERF-03 (sichtbare Antwort < 20 s) | ✅ alle Einzel-/Parallel-Anfragen ≤ 16 s (außer wartende 3. Anfrage) |

Hinweis zu A14: Mit `max_tokens=2048` hat das Modell bei 54k Kontext seine Denkphase teils nicht beendet und keine sichtbare Antwort mehr geliefert. Für die VRAM-Messung unerheblich; in Open WebUI gibt es kein solches Limit.

#### Nachmessung 500 W (2026-10-03, auf Wunsch des Admins)

| Messung | 400 W | 500 W | 575 W |
|---|---|---|---|
| A3 Generierung bei MTP-Quote ~0,62 | 123,5–127,7 Token/s | 142,4 Token/s | 147,7 Token/s |
| A3 Generierung bei MTP-Quote ~0,45 | 99,6–103,3 Token/s (Vorlauf) | 119,9–122,1 Token/s | 118,3–120,2 Token/s |
| A4 2 parallel, je | 98,4–109,0 Token/s | 122,6–124,6 Token/s | 121,2–123,6 Token/s |
| Prefill 54k Tokens | ca. 1.920 Token/s | ca. 2.285 Token/s | ca. 2.460 Token/s |
| Leistung unter Last (Mittel) | ca. 390 W | ca. 485–495 W | ca. 550–565 W |
| Max. GPU-Temperatur | 66 °C | 69 °C | 77 °C |
| VRAM | 24.676 MiB | 24.678 MiB | 24.678 MiB |

500 W erreicht beim Generieren fast das Tempo von 575 W (bei 2 parallelen Anfragen gleichauf) und beim Prefill gut zwei Drittel des Zugewinns, bei ca. 70 W weniger Leistung und 8 °C niedrigerer Spitzentemperatur. A3, A4 und A14 sind auch bei 500 W bestanden.

### Abweichungen von der PRD

- **P3-A1 – CUDA-Toolkit 13.3.1 aus dem NVIDIA-Repo** (8.2): Das Ubuntu-Paket (12.4) unterstützt Blackwell nicht; für Ubuntu 26.04 bietet NVIDIA kein 13.2 an. 13.3 läuft über die CUDA-Minor-Version-Kompatibilität mit Treiber 595 (CUDA 13.2).
- **P3-A2 – Modell-Download per curl statt `hf`-CLI** (8.3): Ubuntu 26.04 blockiert systemweites `pip install` (PEP 668). curl mit Wiederaufnahme und SHA256-Prüfung braucht keine Zusatzsoftware.
- **P3-A3 – `mmproj-F16.gguf`**: wie in der PRD vermutet; im Repo gibt es zusätzlich `mmproj-BF16.gguf`.
- **P3-A4 – llama-server.service**: `After=nvidia-persistenced.service` sowie Härtung (`NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`) ergänzt.
- **P3-A5 – `CMAKE_CUDA_ARCHITECTURES=120a`**: explizit statt automatischer Erkennung gesetzt.
- **P3-A6 – GPU-Leistungslimit 500 W statt 400 W** (N-OPS-04, 8.5): Entscheidung des Admins nach den Messungen 400/500/575 W. `gpu-powerlimit.service` auf `-pl 500` geändert und aktiv (`nvidia-smi`: 500.00 W). 500 W liefert fast das Tempo von 575 W bei ca. 70 W weniger Leistung und 69 °C statt 77 °C Spitzentemperatur. A1 gilt damit mit 500 W.

---

## P4 Oberfläche – 2026-10-03

### Durchgeführt

| Schritt | Ergebnis |
|---|---|
| Pakete | `scripts/p4-packages.sh`: `docker.io` 29.1.3-0ubuntu4.1, `docker-compose-v2` 2.40.3, `caddy` 2.6.2-14 (alle aus Ubuntu) |
| Umgebungsvariablen | Alle Variablen aus PRD 8.6 gegen `backend/open_webui/config.py`, `env.py` und `start.sh` von v0.11.4 geprüft: vorhanden und gleichnamig |
| `.env` | `scripts/p4-env.sh`: `WEBUI_SECRET_KEY` zufällig (openssl rand -hex 32), `BRAVE_SEARCH_API_KEY=` leer für den Admin. Rechte 600, per `.gitignore` ausgeschlossen, von Claude Code nicht gelesen. |
| Open WebUI | `docker-compose.yml`, `scripts/p4-openwebui.sh`: Image `ghcr.io/open-webui/open-webui:v0.11.4@sha256:9591b13f13843c7721c2b8eaf7382846c81b3ffe126526d1888d1fed50c6a33f` (1,65 GB), `network_mode: host`, `restart: always`, Logs 3 × 10 MB, Volume `ki_open-webui`. Lauscht auf 127.0.0.1:3000. |
| Caddy | `etc/caddy/Caddyfile`, `scripts/p4-caddy.sh`: `https://192.168.10.129` mit `tls internal` → 127.0.0.1:3000. Original als `/etc/caddy/Caddyfile.orig` gesichert. |
| Root-Zertifikat | `client/caddy-root.crt` (CN „Caddy Local Authority - 2026 ECC Root“, gültig bis 11.08.2036, SHA256 `43:FC:E6:3A:6D:F8:EF:0E:E5:56:1D:41:41:3B:58:FE:8E:10:4A:A3:48:7B:CE:C1:0D:BE:90:75:E8:48:93:13`). Öffentlich; der private Schlüssel bleibt in `/var/lib/caddy`. |

Beim ersten Start lädt Open WebUI das Standard-Embedding-Modell für RAG von Hugging Face (keine Büro-Daten). Der erste Image-Pull scheiterte an einer DNS-Zeitüberschreitung, der zweite Versuch lief durch (vgl. Verbindungsabbrüche in P3).

### Tests

| Test | Ergebnis |
|---|---|
| Lauschende Ports nach außen | nur 22 (sshd) und 443 (Caddy) ✅; 3000, 8080, 2019 nur auf 127.0.0.1 |
| `https://192.168.10.129` auf dem Server | HTTP 200, Zertifikatsprüfung gegen `caddy-root.crt` ok ✅ |
| `/api/config` | Open WebUI 0.11.4, Anmeldung aktiv ✅ |
| Docker | Restart-Policy `always`, Netzwerk `host`, Log-Rotation 3 × 10 MB ✅ |
| Anmeldeseite aus dem LAN, A11 Port 443 | siehe unten (Test vom Admin-PC) |

### Abweichungen von der PRD

- **P4-A1 – Image zusätzlich per Digest fixiert** (N-OPS-03): Tag plus `@sha256:…`, damit ein neu gebautes Tag nicht unbemerkt ein anderes Image liefert.
- **P4-A2 – `CORS_ALLOW_ORIGIN=https://192.168.10.129`** statt Standard `*` (Open WebUI warnt sonst „NOT RECOMMENDED FOR PRODUCTION“).
- **P4-A3 – Caddy-Globaloptionen** `auto_https disable_redirects` (kein Listener auf Port 80) und `skip_install_trust` (Root-CA nicht in den Trust-Store des Servers).
- **P4-A4 – Caddy 2.6.2 aus Ubuntu** wie in der PRD; das offizielle Caddy-Repo wäre aktueller (2.10.x), für `tls internal` im LAN reicht 2.6.2.

---

## Externe Kopie der Konfiguration – 2026-10-03

- Das lokale Repo liegt auf derselben SSD wie der Server. Für die Neuinstallation nach einem Hardwaredefekt (PRD 12) wird es zusätzlich in ein **privates** GitHub-Repo gespiegelt: `PKR-HUB/lokal-ki` (Entscheidung des Admins).
- Zugriff über einen eigenen Deploy Key `~msb/.ssh/github_ki_deploy` (ED25519, nur dieses Repo, Schreibrecht), SSH-Alias `github-ki` in `~msb/.ssh/config`. Host-Key von github.com gegen den veröffentlichten Fingerprint `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` geprüft.
- Vor dem ersten Push die gesamte History auf Secrets geprüft (`.env`, Schlüssel, API-Keys): keine Treffer. Im Repo liegen nur Konfiguration, Skripte, SETUP-LOG, Messwerte und das öffentliche Caddy-Root-Zertifikat.
- Pushes führt Claude Code nach jeder Phase selbst aus (vom Admin ausdrücklich freigegeben).
- Bei der Abschaltung (PRD 10): Deploy Key in GitHub entfernen; das Repo enthält keine Büro-Daten.

---

## A2 Server-Neustart – 2026-10-03

Neustart durch den Admin, Boot 17:33:45 UTC. Ohne manuellen Eingriff:

| Prüfung | Ergebnis |
|---|---|
| llama-server | active, `/health` ok, Modell geladen (VRAM 24.628 MiB) ✅ |
| Open WebUI | Container `healthy`, `/health` ok ✅ |
| Caddy | active, `https://192.168.10.129` HTTP 200 ✅ |
| gpu-powerlimit | active, 500 W ✅ |
| ufw / SSH-Härtung / unattended-upgrades | aktiv, Passwort-Login aus ✅ |
| Ports nach außen | nur 22 und 443 ✅ |

**A2 bestanden.** Hinweis: Open WebUI meldet `onboarding: true`, das Admin-Konto ist noch nicht angelegt.

---

## P5 Konfiguration – Beginn 2026-10-03

| Schritt | Ergebnis |
|---|---|
| Admin-Konto | durch den Admin angelegt ✅ |
| Registrierung (F-UI-02) | `enable_signup: false`; Test-Registrierung per `POST /api/v1/auths/signup` → HTTP 403 ✅ (**A10 bestanden**) |
| API-Schlüssel (F-UI-08) | global aktiviert, Admin hat einen persönlichen Schlüssel erstellt ✅. Standardrecht `features.api_keys: false`, keine Gruppen → normale Nutzer können keine Schlüssel erstellen (siehe P5-A1) |
| Websuche | Brave, Schlüssel durch den Admin in der Oberfläche eingetragen (in der DB, nicht in `.env`), 5 Ergebnisse ✅ |
| Standardrechte Nutzer | an: Datei-Upload, Websuche, Code-Interpreter, eigener System-Prompt/Parameter. **Aus:** API-Schlüssel, Bildgenerierung (auch global aus, nicht angebunden), Sprache (Diktat `stt`, Vorlesen `tts`, Anruf `call`). Geändert direkt in `config.user.permissions` der Open-WebUI-DB, vorher Sicherung `data/webui.db.bak-p5-perms` im Volume, danach Neustart; Werte nach Neustart bestätigt ✅ |
| Modell-Profile (8.9) | Über Open WebUIs eigene Modell-Klasse angelegt, vorher Sicherung `data/webui.db.bak-p5-models`. **`qwen3.8-27b (Basis)`**: versteckt, Lesezugriff für alle (sonst dürfen Nutzer keine Profile darauf nutzen). **`Qwen3.8`** (ID `qwen38`): für alle, System-Prompt aus 8.9, Websuche, Vision, Upload, Code-Interpreter, eingebaute Werkzeuge an, Bild aus. **`qwen38-code`**: nur Admin, kein System-Prompt, Websuche, Code-Interpreter, Memory und eingebaute Werkzeuge aus. Beide: `chat_template_kwargs {"reasoning_effort":"medium"}`, temperature 1.0, top_p 0.95, top_k 20, min_p 0, presence 0, repeat 1.0, Function Calling native ✅ |
| System-Prompt | Test: Qwen3.8 meldet sich als Büro-Assistent in Sie-Form ✅. Eigener System-Prompt eines Nutzers wird angehängt und befolgt (Test „duzen, mit Moin beginnen“ → befolgt) ✅. Open WebUI setzt den Profil-Prompt vor den Nutzer-Prompt. |
| Arena-Modell | `evaluation.arena.enable` aus (Blindvergleich ist mit einem Modell sinnlos, verwirrt nur in der Auswahl) ✅ |
| Websuche Standard an | Admin-Test zeigte „kein Web-Such-Tool“: Chat lief noch mit dem Basismodell (UI merkte sich die alte Auswahl), dort gibt es weder System-Prompt noch Websuche. Behoben: Profil `Qwen3.8` mit `defaultFeatureIds: ["web_search"]` (Websuche in neuen Chats vorausgewählt), Standardmodell für alle `qwen38`, Reihenfolge Qwen3.8 vor qwen38-code. Sicherung `data/webui.db.bak-p5-websearch` ✅ |
| Hugging Face offline (2026-10-04) | `HF_HUB_OFFLINE=1` in `docker-compose.yml`: Open WebUI fragt beim Start nicht mehr bei Hugging Face nach (bei DNS-Störung zuvor 2+ min Startverzögerung). Embedding-Modelle `all-MiniLM-L6-v2` und `bge-micro-v2` liegen im Volume. Bewusst nicht `OFFLINE_MODE`, weil das auch die pip-Installation für Werkzeuge sperrt. Test: Neustart in 12 s, `/health` ok, Embedding-Modell lädt offline (Dim 384), keine Fehler im Log ✅ |
| Kontext geprüft (2026-10-04) | 64k pro Chat (2 Slots × 65.536, `kv_unified=false`). Rechnung für die Verdopplung auf 128k pro Chat (`-c 262144`): Kontextspeicher ca. 34 KB/Token in q8_0 (16 von 64 Schichten mit Attention), GPU belegt dann ca. 29,2 GB von 32,6 GB, also an der Grenze von A14. Entscheidung des Admins: bleibt bei 64k ✅ |
| Profile je Arbeitsart (2026-10-04) | Nach `Anweisung-Profile.md` des Admins. Neues idempotentes Skript `scripts/p5-profile.sh`: liest `Büro.md`, `Backoffice.md`, `Recherche.md` (vollständiger Inhalt = System-Prompt, unverändert), vergleicht Soll und Ist und ändert nur bei Abweichung (dann Sicherung `data/webui.db.bak-p5-profile`, Änderung über Open WebUIs Modell-Klasse, Container-Neustart). Ergebnis, Reihenfolge in der Auswahl: **Q3.8 Büro** (`qwen38-buero`), **Q3.8 Backoffice** (`qwen38-backoffice`), **Q3.8 Recherche** (`qwen38-recherche`), **Q3.8 None** (`qwen38`, umbenannt, System-Prompt entfernt, bleibt Standardmodell), `qwen38-code` (unverändert, nur Admin). Die drei neuen Profile mit allen Einstellungen von `qwen38` (Basis `qwen3.8-27b`, `reasoning_effort medium`, Sampling wie oben, Function Calling native, gleiche Capabilities, Websuche vorausgewählt), Lesezugriff für alle. Werkzeugname `fetch_url` in v0.11.4 bestätigt (`tools/builtin.py`) ✅ |
| Nutzerrechte gesperrt (2026-10-04) | In `config.user.permissions` aus: `chat.controls`, `chat.system_prompt`, `chat.params`, `chat.import`. Sicherung `data/webui.db.bak-p5-perms2`, danach Neustart, Werte bestätigt ✅. Geprüft am Code v0.11.4: Persönliche Einstellungen (Abschnitt System-Prompt und Parameter) und Chat-Steuerung hängen an `chat.controls` + `chat.system_prompt` bzw. `chat.params`, das Feld System-Prompt im Ordner-Dialog an `chat.system_prompt`. Eigene Modelle im Arbeitsbereich sind seit P5 aus (`workspace.models`). `chat.import` gesperrt, weil das Frontend beim Öffnen eines Chats dessen gespeicherte `params.system` mitschickt (importierter Chat = eigener System-Prompt). Übrige Rechte unverändert (Upload, Websuche, Code-Interpreter an; API-Schlüssel, Bild, Sprache aus). Grenzen siehe P5-A6 |
| Tests Profile (2026-10-04) | 1) Fünf Profile aktiv in Soll-Reihenfolge, Basismodell versteckt ✅ 2) Q3.8-Profile Lesezugriff `*`, `qwen38-code` ohne Freigaben (nur Admin) ✅ 3) Je Profil „Wofür sind Sie da?“ über `/api/chat/completions` mit `session_id` (wie die Oberfläche) und Websuche an, Mitschnitt der Anfragen an llama-server (`tcpdump` auf `lo:8080`, nur die Testanfragen ausgewertet, danach gelöscht): Werkzeuge `search_web` und `fetch_url` angeboten, in keinem Profil aufgerufen; Büro, Backoffice, Recherche antworten in ihrer Rolle, System-Nachricht beginnt mit der Überschrift der Datei; Q3.8 None ohne Rolle, keine System-Nachricht im Aufruf (nur `user`) ✅ 4) Rechte nach Neustart auf neuen Werten ✅ 5) Zweiter Lauf `scripts/p5-profile.sh`: „nichts geändert“, keine Sicherung, kein Neustart ✅ |
| Erinnerungen aus (2026-10-04) | Auf Entscheidung des Admins `features.memories` für Nutzer aus: Erinnerungen werden sonst in jedem Profil an die System-Nachricht angehängt (`utils/memory.py` `add_memory_context`), also dauerhafte eigene Vorgaben an der Sperre vorbei, außerdem persönliche Daten außerhalb der 90-Tage-Löschung. Sicherung `data/webui.db.bak-p5-memories`, Neustart, Wert bestätigt, übrige Rechte unverändert; gespeicherte Erinnerungen: 0 ✅. Für den Admin gilt das Recht nicht (Admins sind ausgenommen) |
| Vorschläge auf Deutsch (2026-10-04) | Die Kacheln unter dem Eingabefeld waren die englischen Standardvorschläge. Neu: `Vorschläge.json` im Repo, je Profil vier passende deutsche Vorschläge (`meta.suggestion_prompts`), dazu eine allgemeine Liste (`ui.prompt_suggestions`) für Profile ohne eigene, z. B. `qwen38-code`. `scripts/p5-profile.sh` übernimmt sie mit (bricht ab, wenn die Datei fehlt oder kein gültiges JSON ist). Lauf: vier Profile und die allgemeine Liste geändert, Sicherung `bak-p5-profile`, Neustart; zweiter Lauf ohne Änderung ✅ |
| A9 Zwei Nutzer (2026-10-04) | Durch den Admin im Browser geprüft: Nutzer sehen keine fremden Chats, der Admin auch nicht (`ENABLE_ADMIN_CHAT_ACCESS=false`) ✅ (**A9 bestanden**) |
| Nutzerrechte im Browser (2026-10-04) | Durch den Admin mit normalem Konto geprüft: nur vier Profile, kein Feld für den System-Prompt, keine Parameter-Regler ✅ |

**Abweichungen P5:**
- **P5-A1 – API-Schlüssel nur für den Admin** (F-UI-08, F-COD-01, A12): Auf Wunsch des Admins bekommt nur er einen API-Schlüssel. Alle anderen nutzen ausschließlich die Weboberfläche. Die Berechtigung „API Keys“ bleibt in den Standardrechten aus, eine Gruppe „Entwicklung“ wird nicht angelegt. A12 (IDE-Anbindung) wird nur mit dem Admin-Schlüssel geprüft.
- **P5-A2 – Pi später** (8.12, A15): Pi selbst wird später eingerichtet. Was Pi auf dem Server braucht, ist jetzt angelegt (Profil `qwen38-code`, Admin-Schlüssel). Die Vorlage `client/pi-models.json` und A15 folgen mit Pi.
- **P5-A3 – A12 verschoben:** IDE-Anbindung wird später geprüft, nicht Voraussetzung für den Abschluss von P5.
- **P5-A4 – Websuche standardmäßig an** (PRD Risiken: „Websuche nicht als Default“): Auf Wunsch des Admins im Profil Qwen3.8 vorausgewählt, Nutzer können sie pro Chat abschalten. Der System-Prompt verbietet weiterhin Personen-/Kundennamen in Suchanfragen.
- **P5-A5 – Fünf Profile statt zwei** (F-UI-05, 8.9): Auf Wunsch des Admins Q3.8 Büro, Q3.8 Backoffice, Q3.8 Recherche, Q3.8 None und `qwen38-code`. Der allgemeine System-Prompt aus 8.9 entfällt; seine Websuche-Regeln stehen in den drei neuen Prompts, bei Q3.8 None gibt es sie nicht mehr. Die Websuche bleibt in allen vier Q3.8-Profilen vorausgewählt (P5-A4 gilt weiter). Die Prompts pflegt der Admin im Repo, übernommen werden sie mit `git pull` und `scripts/p5-profile.sh`.
- **P5-A6 – Eigener System-Prompt und Parameter für Nutzer gesperrt** (bisher in P5 erlaubt): Der System-Prompt gehört fest zum Profil, wer eigene Vorgaben braucht, nimmt Q3.8 None und schreibt sie als erste Nachricht. Grenzen: Open WebUI prüft die Rechte nur in der Oberfläche und beim Speichern der persönlichen Einstellungen, nicht beim Chat-Aufruf und nicht beim Speichern von Ordnern. Wer mit dem Sitzungs-Token die API direkt aufruft, kann weiter eine System-Nachricht mitschicken (ohne Berechtigung nicht zu schließen). Ein vor der Sperre gespeicherter persönlicher System-Prompt würde weiter mitgeschickt; derzeit gibt es außer dem Admin keine Konten, also keinen. Gespeicherte Erinnerungen (`features.memories`) gelangen ebenfalls in den System-Kontext; deshalb auf Entscheidung des Admins ebenfalls aus.
- **P5-A7 – A5, A6, A7, A8 entfallen** (Abschnitt 11): Auf Entscheidung des Admins (2026-10-04) nicht Teil der Abnahme. Bild-Upload (Vision), lange PDFs und Websuche sind eingerichtet und laufen, werden aber nicht formal abgenommen. A8 (ungültiger Brave-Key) konnte Claude nicht selbst testen, weil das Austauschen des gespeicherten Keys durch die Rechteprüfung von Claude Code blockiert wurde.

**Stand 2026-10-04:** P5 abgeschlossen. Websuche-Test entfällt (P5-A7), Nutzerrechte im Browser durch den Admin geprüft. ~~Vorschlag `HF_HUB_OFFLINE=1`~~ umgesetzt am 2026-10-04.

P4-Nachtrag: Port-Test vom Admin-PC durch den Admin erledigt ✅ (P4 abgeschlossen).

P4-Nachtrag Root-Zertifikat (2026-10-04, N-SEC-03): `client/caddy-root.crt` auf dem Admin-PC in den Benutzer-Speicher „Vertrauenswürdige Stammzertifizierungsstellen“ installiert (`certutil -user -addstore Root client\caddy-root.crt`, Windows-Sicherheitsabfrage bestätigt; SHA1 `DB0A77036000C3AEE98285DE8B7B53D0A03C8202`, SHA256 wie in P4). Test: `https://192.168.10.129` über den Windows-Trust-Store HTTP 200 ohne Zertifikatsfehler ✅. Gilt für Edge und Chrome nach Browser-Neustart; Firefox nutzt einen eigenen Speicher. Die übrigen Büro-PCs sind noch offen (gleicher Befehl je Nutzer oder per Gruppenrichtlinie). Entfernen: `certutil -user -delstore Root DB0A77036000C3AEE98285DE8B7B53D0A03C8202`.

Hinweis Netzwerk (18:16–18:20 UTC): Nach dem Neustart kurz kein SSH vom Admin-PC. Server-seitig unauffällig (Link stabil, IP unverändert, keine SSH-Versuche oder ufw-Blocks auf Port 22 im Log), Ursache lag im Büronetz (gleichzeitige Internetstörung, verspätete DNS-Antworten von .9).

## P6 Löschung nach 90 Tagen – 2026-10-04

| Schritt | Ergebnis |
|---|---|
| Eingebaute Funktion (8.11 Punkt 1) | Open WebUI v0.11.4 hat keine Aufbewahrungsfrist für Chats (nur `ENABLE_KNOWLEDGE_FILE_RETENTION` für Wissensdatenbank-Dateien). Daher eigener Job |
| Skript `scripts/p6-loeschung.sh` | Läuft im Container mit Open WebUIs eigenen Modell-Klassen (wie `DELETE /api/v1/chats/{id}` und `/api/v1/files/{id}`). Löscht: 1) Chats mit `updated_at` älter als 90 Tage (letzte Änderung; auch angeheftete und archivierte), samt Nachrichten, Freigaben, verwaisten Tags und internen Kind-Chats; 2) Bewertungen (`feedback`) älter als 90 Tage, weil sie eine Kopie des Chats enthalten und beim Löschen des Chats stehen bleiben; 3) verwaiste Zeilen in `chat_file` und `knowledge_file` (SQLite-Kaskaden sind aus); 4) Dateien älter als 90 Tage, deren ID in keiner anderen Tabelle mehr vorkommt (kein Chat, keine Wissensdatenbank, kein Ordner, keine Notiz, kein Modell) – DB-Eintrag und Datei unter `uploads/`; 5) Vektor-Sammlungen `file-<id>` ohne zugehörige Datei. Wissensdatenbanken bleiben. Ins Journal gehen nur Anzahlen. `--probelauf` zählt nur, `TAGE` änderbar. Keine Sicherung vor dem Löschen (sonst blieben die Daten erhalten) |
| Timer | `chat-retention.service` (oneshot) und `chat-retention.timer` (täglich 03:30 UTC = 05:30 Berlin, `RandomizedDelaySec=10min`, `Persistent=true`) unter `etc/systemd/system/`, installiert mit `scripts/p6-retention.sh`. Handlauf: `Result=success`, Journal-Zeile mit Anzahlen ✅ |
| A13 (Testdaten) | Sicherung `data/webui.db.bak-p6-a13`. Unter dem Admin-Konto über die API angelegt: drei Textdateien (synthetisch), Wissensdatenbank „A13 Test-Wissensdatenbank“ mit einer Datei, Testchat „alt“ mit Datei und Bewertung, Testchat „neu“ mit Datei. Gealtert auf 100 Tage: Chat alt, Datei alt, Bewertung, Wissensdatenbank-Datei. Lauf: Chat alt samt Nachrichten, Bewertung, Verknüpfung, Datei (DB und Platte) gelöscht; Chat neu, seine Datei, Wissensdatenbank samt Datei und Vektoren bleiben; die drei echten Chats unberührt ✅. Danach Chat neu gealtert: in einem Lauf Chat, Nachrichten, Verknüpfung, Datei auf DB und Platte, Vektor-Sammlung gelöscht, Wissensdatenbank bleibt ✅ (**A13 bestanden**). Testdaten danach entfernt (Wissensdatenbank über die API gelöscht, Rest durch den Job), keine Testreste in DB, `uploads/` und Vektor-DB |
| Gefundene Lücken in v0.11.4 | Beim Löschen einer Datei ruft Open WebUI `delete()` auf die Vektor-Sammlung ohne IDs auf, das löscht nichts: Textstücke und Embeddings blieben liegen. Beim Löschen einer Wissensdatenbank bleiben `knowledge_file`-Zeilen und die Dateien stehen. Beides räumt der Job jetzt mit auf |
| Sicherungen (Entscheidung des Admins) | Die Sicherungen `data/webui.db.bak-*` sind Kopien der ganzen DB samt Chats. Der Job löscht als Schritt 6 Sicherungen, die älter als 90 Tage sind (Änderungszeit der Datei). Probelauf mit `TAGE=0`: alle 7 Sicherungen erkannt (und 3 Chats), nichts gelöscht; mit 90 Tagen: 0 ✅. Probelauf des Admins: alles 0 ✅ |

**Abweichungen P6:**
- **P6-A1 – Modell-Klassen statt API** (8.11 Punkt 3): Mit `ENABLE_ADMIN_CHAT_ACCESS=false` darf auch der Admin über die API keine fremden Chats auflisten (`routers/chats.py`). Der Job nutzt deshalb im laufenden Container dieselben Klassen, über die die API-Endpunkte löschen. Das Schema der fixierten Version ist geprüft, SQLite lässt den gleichzeitigen Zugriff zu. Direktes SQL nur zum Lesen, zum Altern der Testdaten und für verwaiste Verknüpfungszeilen.
- **P6-A2 – Auch Bewertungen und verwaiste Dateien:** Über die PRD hinaus löscht der Job Bewertungen (enthalten Chat-Kopien) und Dateien, deren Chat ein Nutzer schon selbst gelöscht hat, sowie zurückgebliebene Vektor-Sammlungen. Sonst blieben Büro-Daten über die 90 Tage hinaus erhalten.
- **P6-A3 – Sicherungen nach 90 Tagen löschen:** Auf Entscheidung des Admins, damit keine Chats in DB-Kopien länger als 90 Tage erhalten bleiben. Eingriffe der letzten 90 Tage lassen sich weiter rückgängig machen.

## P7 Übergabe – Beginn 2026-10-04

| Schritt | Ergebnis |
|---|---|
| `ADMIN.md` | Betrieb: Konten anlegen (Anmeldename `vorname@localhost`, keine echte E-Mail nötig), Passwort, Konto löschen, Rechte der Nutzer, Profile/Prompts/Vorschläge ändern (`git pull` + `scripts/p5-profile.sh`), Löschung nach 90 Tagen, Zustand prüfen, Neustart, Root-Zertifikat auf Büro-PCs, Pi (verschoben), Abschaltung nach PRD 10 (Volume `ki_open-webui`), Regeln für Claude Code ✅ |
| `Wartung.md` (Wunsch des Admins) | Technikübersicht mit Versionen und Update-Wegen; monatliche Systemupdates und Aufräumen (`apt autoremove --purge`, `apt clean`, rc-Pakete, Neustart bei `reboot-required`); Hinweis: unattended-upgrades installiert nur `resolute` und `-security`, nicht `-updates` (neue NVIDIA-Treiber meist dort); Open-WebUI-Update mit Digest, Sicherung, Test und Rückrollen (WAL-Dateien beachten); llama.cpp-Update mit Flag-Prüfung und Benchmarks; Modellwechsel; Docker-Aufräumen und verbotene Befehle (`volume prune`, `down -v`); Kontrollplan; Fehlersuche ✅ |

| A2 Server-Neustart (2026-10-05) | Neustart durch den Admin, Boot 07:17:21 UTC, alle Dienste nach ca. 10 s aktiv, ohne manuellen Eingriff: llama-server active, `/health` ok, Modell geladen (VRAM 24.628 MiB), Testanfrage beantwortet ✅; Open WebUI `healthy`, `/health` ok ✅; Caddy `https://192.168.10.129` HTTP 200 ✅; gpu-powerlimit 500 W ✅; `chat-retention.timer` geplant (nächster Lauf 06.10. 03:33 UTC) ✅; ufw aktiv (nur 22 und 443 aus 192.168.10.0/24), Passwort-Login aus, unattended-upgrades aktiv ✅; Ports nach außen nur 22 und 443, 3000/8080/2019 nur auf 127.0.0.1 ✅. Keine fehlgeschlagenen Units. **A2 bestanden** |

### Gesamtübersicht der Abnahmetests (PRD 11) – Stand 2026-10-05

| # | Test | Ergebnis | Nachweis |
|---|---|---|---|
| A1 | `nvidia-smi` nach Neustart | ✅ bestanden, RTX 5090 erkannt; Limit 500 W statt 400 W (P3-A6), nach dem Neustart am 2026-10-05 erneut 500 W | P2, P3-A6, A2 (2026-10-05) |
| A2 | Server-Neustart | ✅ bestanden (2026-10-03 und 2026-10-05) | A2, P7 |
| A3 | Leistung 1 Anfrage | ✅ bestanden, 118–148 Token/s, ≤ 21,2 s (400 W und 500 W) | P3 |
| A4 | 2 parallele Anfragen | ✅ bestanden, je 98–124 Token/s, 3. Anfrage wartet und wird beantwortet | P3 |
| A5 | Bild/Scan (Rechnung) | – entfällt (P5-A7), Vision eingerichtet | P5 |
| A6 | PDF mit ca. 20 Seiten | – entfällt (P5-A7) | P5 |
| A7 | Websuche | – entfällt (P5-A7), Websuche eingerichtet | P5 |
| A8 | Ungültiger Brave-Key | – entfällt (P5-A7) | P5 |
| A9 | Zwei Nutzer | ✅ bestanden (Browsertest durch den Admin) | P5 |
| A10 | Registrierung ohne Admin | ✅ bestanden (HTTP 403) | P5 |
| A11 | Port-Scan aus dem LAN | ✅ bestanden: 22 und 443 offen, 3000/8080 zu; 22 aus dem ganzen Büronetz, nur per Schlüssel (P1-A1) | P1, P4-Nachtrag, A2 (2026-10-05) |
| A12 | IDE-Anbindung | ⏳ verschoben (P5-A3), nur mit Admin-Schlüssel (P5-A1) | P5 |
| A13 | Löschung nach 90 Tagen | ✅ bestanden | P6 |
| A14 | VRAM unter Last | ✅ bestanden: in P3 24.676 MiB bei 2 × 54k; mit dem heutigen Kontext 2 × 64k (`-c 131072`) 24.628 MiB nach dem Neustart, KV-Cache wird beim Start komplett reserviert | P3, P5, A2 (2026-10-05) |
| A15 | Pi auf Arbeitsplatz-Rechner | ⏳ verschoben mit Pi (P5-A2) | P5 |

**Ergebnis:** 9 von 15 Tests bestanden (A1–A4, A9–A11, A13, A14). Keiner ist fehlgeschlagen. A5–A8 entfallen auf Entscheidung des Admins. A12 und A15 werden nachgeholt, sobald IDE-Anbindung und Pi eingerichtet sind.

**Monitoring an der Konsole (2026-10-05):** Auf Wunsch des Admins `btop` 1.4.6 und `nvtop` 3.2.0 aus den Ubuntu-Paketquellen installiert. Beide sind reine Terminal-Programme ohne offenen Port, ein Desktop wird nicht installiert. In `~/.config/btop/btop.conf` (Benutzer msb) ist das GPU-Feld eingeblendet (`shown_boxes = "cpu mem net proc gpu0"`). btop erkennt die RTX 5090 über NVML. Die Bedienung steht in `ADMIN.md` Abschnitt 4.

**Stand P7:** `ADMIN.md`, `Wartung.md`, A2 und Gesamtübersicht erledigt. Offen bleiben nur A12 und A15 (nach Einrichtung von IDE und Pi).
