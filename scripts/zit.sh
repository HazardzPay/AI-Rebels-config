#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/zit-background.log"

(
  set -euo pipefail

  COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  RGTHREE_NODE_DIR="$CUSTOM_NODES_DIR/rgthree-comfy"
  MODELS_DIR="$COMFY_ROOT/models"
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
  echo "BACKGROUND WATCHER STARTED: Z-IMAGE-TURBO CONFIG (HF)"
  echo "-------------------------------------------------------"

  echo "Waiting for ComfyUI root to exist..."
  for i in $(seq 1 300); do
    if [ -d "$COMFY_ROOT" ]; then
      break
    fi
    sleep 2
  done

  if [ ! -d "$COMFY_ROOT" ]; then
    echo "Timed out waiting for ComfyUI root: $COMFY_ROOT"
    exit 1
  fi

  echo "Waiting for ComfyUI server on 8188..."
  for i in $(seq 1 600); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
      break
    fi
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

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  download_hf_file "${HF_MODELS[qwen_3_4b.safetensors]}" "$MODELS_DIR/text_encoders" &
  download_hf_file "${HF_MODELS[ae.safetensors]}" "$MODELS_DIR/vae" &
  download_hf_file "${HF_MODELS[z_image_turbo_bf16.safetensors]}" "$MODELS_DIR/diffusion_models" &
  download_hf_file "${HF_MODELS[Mystic-XXX-ZIT-V6.safetensors]}" "$MODELS_DIR/loras" &
  download_hf_file "${HF_MODELS[Z-Detail-Slider.safetensors]}" "$MODELS_DIR/loras" &
  download_hf_file "${HF_MODELS[zimage-igbaddie_pruned.safetensors]}" "$MODELS_DIR/loras" &
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
  echo "DOWNLOAD COMPLETE - Z-IMAGE-TURBO INSTALLED"
  echo "-------------------------------------------------------"
) >> /proc/1/fd/1 2>> /proc/1/fd/2 &

echo "zit.sh: background watcher started, main boot can continue"
echo "zit.sh: tail -f $LOG_FILE"
exit 0