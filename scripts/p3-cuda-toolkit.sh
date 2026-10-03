#!/usr/bin/env bash
# P3: CUDA-Toolkit aus dem NVIDIA-Repo (Ubuntu-Paket 12.4 kann kein sm_120). Idempotent.
set -euo pipefail
CUDA_PKG=cuda-toolkit-13-3
CUDA_VER=13.3.1-1
HERE="$(dirname "$(readlink -f "$0")")"
sudo install -m 644 "$HERE/../etc/apt/preferences.d/nvidia-cuda-repo" /etc/apt/preferences.d/nvidia-cuda-repo
if ! dpkg -s cuda-keyring >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/cuda-keyring.deb" \
    https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i "$tmp/cuda-keyring.deb"
  rm -rf "$tmp"
fi
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  build-essential cmake git libcurl4-openssl-dev pkg-config "$CUDA_PKG=$CUDA_VER"
sudo apt-mark hold "$CUDA_PKG" >/dev/null
echo "/usr/local/cuda-13.3/bin/nvcc: $(/usr/local/cuda-13.3/bin/nvcc --version | tail -2 | head -1)"
