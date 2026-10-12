#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/video-interpolate-upscale-background.log"

(
  set -euo pipefail

  COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  SEEDVR_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-SeedVR2_VideoUpscaler"
  FRAMEINTERP_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-Frame-Interpolation"
  VIDEOHELPER_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-VideoHelperSuite"
  SEEDVR_MODELS_DIR="$COMFY_ROOT/models/SEEDVR2"
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
  echo "BACKGROUND WATCHER STARTED: INTERPOLATION + UPSCALE CONFIG"
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

  echo "ComfyUI is live. Installing interpolation and upscale nodes..."

  if ! command -v hf >/dev/null 2>&1; then
    pip install -U "huggingface_hub[hf_transfer]"
  fi

  # Install upscale node
  if [ ! -d "$SEEDVR_NODE_DIR" ]; then
    echo "Cloning upscale node..."
    git clone "${CUSTOM_NODES[seedvr2]}" "$SEEDVR_NODE_DIR"
  else
    echo "Upscale node already present, skipping clone."
  fi

  if [ -f "$SEEDVR_NODE_DIR/requirements.txt" ]; then
    echo "Installing upscale requirements..."
    pip install -q -r "$SEEDVR_NODE_DIR/requirements.txt"
  fi

  # Install interpolation node
  if [ ! -d "$FRAMEINTERP_NODE_DIR" ]; then
    echo "Cloning interpolation node..."
    git clone "${CUSTOM_NODES[frameinterp]}" "$FRAMEINTERP_NODE_DIR"
  else
    echo "Interpolation node already present, skipping clone."
  fi

  if [ -f "$FRAMEINTERP_NODE_DIR/requirements.txt" ]; then
    echo "Installing interpolation requirements..."
    pip install -q -r "$FRAMEINTERP_NODE_DIR/requirements.txt"
  fi

  # Install video helper node
  if [ ! -d "$VIDEOHELPER_NODE_DIR" ]; then
    echo "Cloning video helper node..."
    git clone "${CUSTOM_NODES[videohelper]}" "$VIDEOHELPER_NODE_DIR"
  else
    echo "Video helper node already present, skipping clone."
  fi

  if [ -f "$VIDEOHELPER_NODE_DIR/requirements.txt" ]; then
    echo "Installing video helper requirements..."
    pip install -q -r "$VIDEOHELPER_NODE_DIR/requirements.txt"
  fi

  # Download upscale models (parallel)
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  download_hf_file "${HF_MODELS[seedvr2_ema_7b_fp16.safetensors]}" "$SEEDVR_MODELS_DIR" &
  download_hf_file "${HF_MODELS[ema_vae_fp16.safetensors]}" "$SEEDVR_MODELS_DIR" &
  wait

  rm -rf "$TMP_DIR"

  echo "Downloads complete. Restarting ComfyUI to load all nodes..."
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
  echo "DOWNLOAD COMPLETE - INTERPOLATION + UPSCALE READY"
  echo "-------------------------------------------------------"

) >> /proc/1/fd/1 2>> /proc/1/fd/2 &

echo "video-interpolate-upscale.sh: background watcher started, main boot can continue"
echo "video-interpolate-upscale.sh: tail -f $LOG_FILE"
exit 0
