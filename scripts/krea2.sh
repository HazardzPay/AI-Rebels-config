#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/krea2-background.log"
# If the log file can't be created (e.g. /workspace not mounted yet), fall back
# to /dev/null so tee never kills the watcher.
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"

(
  set -euo pipefail

  COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  RGTHREE_NODE_DIR="$CUSTOM_NODES_DIR/rgthree-comfy"
  RES4LYF_NODE_DIR="$CUSTOM_NODES_DIR/RES4LYF"
  KREA2EDIT_NODE_DIR="$CUSTOM_NODES_DIR/comfyui-krea2edit"
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
    echo "Finished: $filename"
  }

  echo "-------------------------------------------------------"
  echo "BACKGROUND WATCHER STARTED: KREA2 CONFIG"
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

  echo "ComfyUI is live. Updating ComfyUI core, installing custom node(s), and downloading models..."

  if ! command -v hf >/dev/null 2>&1; then
    pip install -U "huggingface_hub[hf_transfer]"
  fi

  # --- update ComfyUI core (krea2 needs >= v0.26.0; baked image is v0.17.2) ---
  # Pinned to a fixed release so boot time and dependencies don't drift with upstream master.
  # The baked repo has no upstream tracking, so a bare `git pull` fails.
  COMFY_PIN="v0.28.0"
  if [ "$(git -C "$COMFY_ROOT" describe --tags --exact-match 2>/dev/null || true)" = "$COMFY_PIN" ]; then
    echo "ComfyUI core already at $COMFY_PIN, skipping update."
  else
    echo "Updating ComfyUI core to $COMFY_PIN..."
    git -C "$COMFY_ROOT" fetch --quiet --depth 1 origin tag "$COMFY_PIN"
    git -C "$COMFY_ROOT" reset --hard --quiet "$COMFY_PIN"
    echo "ComfyUI core updated to: $COMFY_PIN ($(git -C "$COMFY_ROOT" rev-parse --short HEAD))"
    echo "Updating ComfyUI core dependencies... (slow step: torch wheels, often 5-15 min with no output)"
    DEPS_START=$SECONDS
    "$COMFY_ROOT/.venv-cu128/bin/python" -m pip install -q -r "$COMFY_ROOT/requirements.txt"
    DEPS_TOOK=$((SECONDS - DEPS_START))
    echo "Core dependencies installed. (took $((DEPS_TOOK / 60))m$((DEPS_TOOK % 60))s)"
  fi

  # Newer ComfyUI 403s cross-site browser requests (Sec-Fetch-Site check),
  # which breaks access through the RunPod proxy. --enable-cors-header disables that middleware.
  ARGS_FILE="/workspace/runpod-slim/comfyui_args.txt"
  if [ -f "$ARGS_FILE" ] && ! grep -q "enable-cors-header" "$ARGS_FILE"; then
    echo "--enable-cors-header" >> "$ARGS_FILE"
  fi
  # --- end ComfyUI core update ---

  # --- custom node installs ---
  if [ ! -d "$RGTHREE_NODE_DIR" ]; then
    echo "Cloning rgthree..."
    git clone "${CUSTOM_NODES[rgthree]}" "$RGTHREE_NODE_DIR"
  else
    echo "rgthree already present, skipping clone."
  fi
  if [ -f "$RGTHREE_NODE_DIR/requirements.txt" ]; then
    pip install -q -r "$RGTHREE_NODE_DIR/requirements.txt"
    echo "rgthree requirements installed."
  fi
  if [ ! -d "$RES4LYF_NODE_DIR" ]; then
    echo "Cloning res4lyf..."
    git clone "${CUSTOM_NODES[res4lyf]}" "$RES4LYF_NODE_DIR"
  else
    echo "res4lyf already present, skipping clone."
  fi
  if [ -f "$RES4LYF_NODE_DIR/requirements.txt" ]; then
    pip install -q -r "$RES4LYF_NODE_DIR/requirements.txt"
    echo "res4lyf requirements installed."
  fi
  if [ ! -d "$KREA2EDIT_NODE_DIR" ]; then
    echo "Cloning krea2edit..."
    git clone "${CUSTOM_NODES[krea2edit]}" "$KREA2EDIT_NODE_DIR"
  else
    echo "krea2edit already present, skipping clone."
  fi
  if [ -f "$KREA2EDIT_NODE_DIR/requirements.txt" ]; then
    pip install -q -r "$KREA2EDIT_NODE_DIR/requirements.txt"
    echo "krea2edit requirements installed."
  fi
  # --- end custom node installs ---

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  # parallel downloads
  download_hf_file "${HF_MODELS[darkBeastINT8Convrot2_darkBeastKREA2FP8.safetensors]}" "$MODELS_DIR/diffusion_models" &
  download_hf_file "${HF_MODELS[krea2_turbo_fp8_scaled.safetensors]}" "$MODELS_DIR/diffusion_models" &
  download_hf_file "${HF_MODELS[qwen3vl_4b_fp8_scaled.safetensors]}" "$MODELS_DIR/text_encoders" &
  download_hf_file "${HF_MODELS[qwen_image_vae.safetensors]}" "$MODELS_DIR/vae" &
  download_hf_file "${HF_MODELS[realism_engine_krea2_v2.safetensors]}" "$MODELS_DIR/loras" &
  download_hf_file "${HF_MODELS[snofs_krea_v1_1.safetensors]}" "$MODELS_DIR/loras" &
  download_hf_file "${HF_MODELS[krea2_identity_edit_v1_2.safetensors]}" "$MODELS_DIR/loras" &
  wait

  rm -rf "$TMP_DIR"

  echo "Downloads complete. Restarting ComfyUI to load custom node(s)..."
  pkill -f "python main.py" || true
  sleep 3
  cd /workspace/runpod-slim/ComfyUI && .venv-cu128/bin/python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header >> /proc/1/fd/1 2>> /proc/1/fd/2 &

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
  echo "DOWNLOAD COMPLETE - KREA2 INSTALLED"
  echo "-------------------------------------------------------"

) 2>&1 | tee -a "$LOG_FILE" >> /proc/1/fd/1 &

echo "krea2.sh: background watcher started, main boot can continue"
echo "krea2.sh: tail -f $LOG_FILE"
exit 0
