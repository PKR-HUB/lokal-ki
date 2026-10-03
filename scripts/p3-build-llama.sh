#!/usr/bin/env bash
# P3: llama.cpp auf fixiertem Tag mit CUDA (sm_120a, RTX 5090) bauen. Idempotent.
set -euo pipefail
LLAMA_TAG="${LLAMA_TAG:-b11378}"
SRC=/opt/llama.cpp
export PATH=/usr/local/cuda-13.3/bin:$PATH
export CUDACXX=/usr/local/cuda-13.3/bin/nvcc
[ -d "$SRC/.git" ] || git clone --filter=blob:none https://github.com/ggml-org/llama.cpp "$SRC"
git -C "$SRC" fetch -q --tags
git -C "$SRC" -c advice.detachedHead=false checkout -q "$LLAMA_TAG"
cmake -S "$SRC" -B "$SRC/build" -DGGML_CUDA=ON -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_CUDA_ARCHITECTURES=120a -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC/build" --config Release -j"$(nproc)" --target llama-server llama-bench
"$SRC/build/bin/llama-server" --version
