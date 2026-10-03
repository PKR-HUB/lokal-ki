#!/usr/bin/env bash
# P3: Modell + Vision-Modul von Hugging Face laden (curl mit Wiederaufnahme)
# und gegen die SHA256-Prüfsummen des Repos prüfen. Idempotent.
set -euo pipefail
REPO=unsloth/Qwen3.8-27B-GGUF
DIR=/srv/models/qwen3.8-27b
FILES=(Qwen3.8-27B-UD-Q4_K_XL.gguf mmproj-F16.gguf)

id llm >/dev/null 2>&1 || sudo useradd -r -s /usr/sbin/nologin llm
sudo install -d -o "$USER" -g llm -m 755 /srv/models "$DIR"

tree=$(curl -fsS "https://huggingface.co/api/models/$REPO/tree/main")
for f in "${FILES[@]}"; do
  sha=$(python3 -c 'import json,sys; print(next(x["lfs"]["oid"] for x in json.load(sys.stdin) if x["path"]==sys.argv[1]))' "$f" <<<"$tree")
  if [ -f "$DIR/$f" ] && echo "$sha  $DIR/$f" | sha256sum -c --status; then
    echo "$f: bereits vorhanden, Prüfsumme ok"; continue
  fi
  echo "$f: lade herunter ..."
  for i in 1 2 3 4 5; do
    curl -fL --retry 5 --retry-all-errors -C - -o "$DIR/$f" \
      "https://huggingface.co/$REPO/resolve/main/$f" && break
    echo "Versuch $i abgebrochen, setze fort ..."; sleep 5
  done
  echo "$sha  $DIR/$f" | sha256sum -c
done
sudo chown -R llm:llm /srv/models
sudo chmod -R a+rX /srv/models
ls -la "$DIR"
