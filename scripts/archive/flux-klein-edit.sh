#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/flux-klein-edit-background.log"

(
  set -euo pipefail

  COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  RGTHREE_NODE_DIR="$CUSTOM_NODES_DIR/rgthree-comfy"
  DIFFUSION_MODELS_DIR="$COMFY_ROOT/models/diffusion_models"
  LORAS_DIR="$COMFY_ROOT/models/loras"
  TEXT_ENCODERS_DIR="$COMFY_ROOT/models/text_encoders"
  VAE_DIR="$COMFY_ROOT/models/vae"
  TMP_DIR="/workspace/hf-downloads"
  HEALTH_URL="http://127.0.0.1:8188"

  source <(curl -fsSL "https://raw.githubusercontent.com/hazardzpay/AI-Rebels-config/main/registry.sh")

  export HF_HUB_ENABLE_HF_TRANSFER=1
  export HF_XET_HIGH_PERFORMANCE=1
  export HF_HUB_DOWNLOAD_TIMEOUT=60

  download_hf_file() {
    local url="$1"
    local dest_dir="$2"
    local repo repo_path filename dl_tmp
    repo="$(echo "$url" | sed -E 's#https://huggingface.co/([^/]+/[^/]+)/.*#\1#')"
    repo_path="$(echo "$url" | sed -E 's#https://huggingface.co/[^/]+/[^/]+/resolve/[^/]+/##')"
    filename="$(basename "$url")"
    dl_tmp="$TMP_DIR/$filename"
    mkdir -p "$dest_dir" "$dl_tmp"
    echo "Downloading: $url"
    hf download "$repo" "$repo_path" --local-dir "$dl_tmp"
    mv -f "$dl_tmp/$repo_path" "$dest_dir/$filename"
  }

  echo "-------------------------------------------------------"
  echo "BACKGROUND WATCHER STARTED: FLUX KLEIN EDIT CONFIG"
  echo "-------------------------------------------------------"

  echo "Waiting for ComfyUI root to exist..."
  for i in $(seq 1 300); do
    if [ -d "$COMFY_ROOT" ]; then break; fi
    sleep 2
  done

  if [ ! -d "$COMFY_ROOT" ]; then
    echo "Timed out waiting for ComfyUI root: $COMFY_ROOT"
    exit 1
  fi

  echo "Waiting for ComfyUI server on 8188..."
  for i in $(seq 1 600); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then break; fi
    sleep 2
  done

  if ! curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    echo "Timed out waiting for ComfyUI server: $HEALTH_URL"
    exit 1
  fi

  echo "ComfyUI is live. Installing custom node and downloading models..."

  if ! command -v hf >/dev/null 2>&1; then
    pip install -U "huggingface_hub[hf_transfer]"
  fi

  # Install custom node
  if [ ! -d "$RGTHREE_NODE_DIR" ]; then
    echo "Cloning rgthree-comfy..."
    git clone "${CUSTOM_NODES[rgthree]}" "$RGTHREE_NODE_DIR"
  else
    echo "Custom node already present, skipping clone."
  fi

  if [ -f "$RGTHREE_NODE_DIR/requirements.txt" ]; then
    echo "Installing requirements..."
    pip install -q -r "$RGTHREE_NODE_DIR/requirements.txt"
  fi

  # Download models (parallel)
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  download_hf_file "${HF_MODELS[flux-2-klein-9b-fp8.safetensors]}" "$DIFFUSION_MODELS_DIR" &
  download_hf_file "${HF_MODELS[Flux2-Klein-9B-consistency-V2.safetensors]}" "$LORAS_DIR" &
  download_hf_file "${HF_MODELS[bfs_head_v1_flux-klein_9b_step3500_rank128.safetensors]}" "$LORAS_DIR" &
  download_hf_file "${HF_MODELS[qwen_3_8b_fp8mixed.safetensors]}" "$TEXT_ENCODERS_DIR" &
  download_hf_file "${HF_MODELS[flux2-vae.safetensors]}" "$VAE_DIR" &
  wait

  rm -rf "$TMP_DIR"

  echo "Downloads complete. Restarting ComfyUI to load node..."
  pkill -f "python main.py" || true
  sleep 3
  cd /workspace/runpod-slim/ComfyUI && .venv-cu128/bin/python main.py --listen 0.0.0.0 --port 8188 >> /proc/1/fd/1 2>> /proc/1/fd/2 &

  echo "Waiting for ComfyUI to come back online..."
  for i in $(seq 1 300); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then break; fi
    sleep 2
  done

  if ! curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    echo "Timed out waiting for ComfyUI to restart."
    exit 1
  fi

  echo "-------------------------------------------------------"
  echo "DOWNLOAD COMPLETE - FLUX KLEIN EDIT INSTALLED"
  echo "-------------------------------------------------------"

) >> /proc/1/fd/1 2>> /proc/1/fd/2 &

echo "flux-klein-edit.sh: background watcher started, main boot can continue"
echo "flux-klein-edit.sh: tail -f $LOG_FILE"
exit 0
