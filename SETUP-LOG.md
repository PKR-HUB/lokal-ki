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
