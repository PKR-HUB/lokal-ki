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

### Abweichungen von der PRD

- **P3-A1 – CUDA-Toolkit 13.3.1 aus dem NVIDIA-Repo** (8.2): Das Ubuntu-Paket (12.4) unterstützt Blackwell nicht; für Ubuntu 26.04 bietet NVIDIA kein 13.2 an. 13.3 läuft über die CUDA-Minor-Version-Kompatibilität mit Treiber 595 (CUDA 13.2).
- **P3-A2 – Modell-Download per curl statt `hf`-CLI** (8.3): Ubuntu 26.04 blockiert systemweites `pip install` (PEP 668). curl mit Wiederaufnahme und SHA256-Prüfung braucht keine Zusatzsoftware.
- **P3-A3 – `mmproj-F16.gguf`**: wie in der PRD vermutet; im Repo gibt es zusätzlich `mmproj-BF16.gguf`.
- **P3-A4 – llama-server.service**: `After=nvidia-persistenced.service` sowie Härtung (`NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`) ergänzt.
- **P3-A5 – `CMAKE_CUDA_ARCHITECTURES=120a`**: explizit statt automatischer Erkennung gesetzt.
- **Offen**: Entscheidung Leistungslimit 400 W vs. 575 W (oder Zwischenwert) durch den Admin. Aktuell 400 W.
