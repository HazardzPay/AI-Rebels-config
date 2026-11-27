#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/seedvr-background.log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"

(
  set -euo pipefail

  COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  SEEDVR_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-SeedVR2_VideoUpscaler"
  SEEDVR_MODELS_DIR="$COMFY_ROOT/models/SEEDVR2"
  TMP_DIR="/workspace/hf-downloads"
  HEALTH_URL="http://127.0.0.1:8188"

  source <(curl -fsSL "https://raw.githubusercontent.com/hazardzpay/AI-Rebels-config/main/registry.sh")

  export HF_HUB_ENABLE_HF_TRANSFER=1
  export HF_XET_HIGH_PERFORMANCE=1
  export HF_XET_RECONSTRUCTION_DOWNLOAD_BUFFER_SIZE=4gb
  export HF_XET_RECONSTRUCTION_DOWNLOAD_BUFFER_PERFILE_SIZE=2gb
  export HF_XET_RECONSTRUCTION_DOWNLOAD_BUFFER_LIMIT=4gb
  export HF_HUB_DOWNLOAD_TIMEOUT=60
  MAX_PARALLEL_DOWNLOADS=2

  DOWNLOAD_TIMEOUT=600
  DOWNLOAD_KILL_GRACE=30
  if command -v timeout >/dev/null 2>&1; then
    DL_TIMEOUT_CMD="timeout --kill-after=$DOWNLOAD_KILL_GRACE $DOWNLOAD_TIMEOUT"
    DOWNLOAD_LIMIT_DESC="${DOWNLOAD_TIMEOUT}s timeout, SIGKILL at $((DOWNLOAD_TIMEOUT + DOWNLOAD_KILL_GRACE))s"
  else
    DL_TIMEOUT_CMD=""
    DOWNLOAD_LIMIT_DESC="NO TIMEOUT - 'timeout' not found on PATH"
  fi

  download_hf_file() {
    local url="$1" dest_dir="$2" repo repo_path filename dl_tmp attempt rc start
    repo="$(echo "$url" | sed -E 's#https://huggingface.co/([^/]+/[^/]+)/.*#\1#')"
    repo_path="$(echo "$url" | sed -E 's#https://huggingface.co/[^/]+/[^/]+/resolve/[^/]+/##')"
    filename="$(basename "$url")"
    dl_tmp="$TMP_DIR/$filename"
    mkdir -p "$dest_dir" "$dl_tmp"
    for attempt in 1 2 3; do
      echo "Downloading: $url (attempt $attempt/3, $DOWNLOAD_LIMIT_DESC)"
      start=$SECONDS; rc=0
      $DL_TIMEOUT_CMD hf download "$repo" "$repo_path" --local-dir "$dl_tmp" || rc=$?
      if [ "$rc" -eq 0 ]; then
        mv -f "$dl_tmp/$repo_path" "$dest_dir/$filename"
        echo "Finished: $filename in $((SECONDS - start))s (attempt $attempt/3)."
        return 0
      fi
      case "$rc" in
        124) echo "Download of $filename TIMED OUT after $((SECONDS - start))s (attempt $attempt/3)." ;;
        137) echo "Download of $filename ignored SIGTERM, SIGKILLed (attempt $attempt/3)." ;;
        *)   echo "Download of $filename FAILED, hf exit $rc (attempt $attempt/3)." ;;
      esac
    done
    echo "Download of $filename failed after 3 attempts."
    return 1
  }

  CLONE_TIMEOUT=1200
  CLONE_KILL_GRACE=30
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout --kill-after=$CLONE_KILL_GRACE $CLONE_TIMEOUT"
    CLONE_LIMIT_DESC="${CLONE_TIMEOUT}s timeout, SIGKILL at $((CLONE_TIMEOUT + CLONE_KILL_GRACE))s"
  else
    TIMEOUT_CMD=""
    CLONE_LIMIT_DESC="NO TIMEOUT - 'timeout' not found on PATH"
  fi

  die() {
    echo "======================================================="
    echo "SETUP FAILED: $1"
    echo "Nothing further will run. Redeploy the pod."
    echo "Failed after $((SECONDS / 60))m$((SECONDS % 60))s."
    echo "======================================================="
    exit 1
  }

  clone_node() {
    local name="$1" url="$2" dest="$3"
    if [ -d "$dest" ]; then echo "$name already present, skipping clone."; return 0; fi
    local attempt rc start
    for attempt in 1 2; do
      echo "Cloning $name (attempt $attempt/2, $CLONE_LIMIT_DESC)..."
      start=$SECONDS; rc=0
      $TIMEOUT_CMD git -c http.version=HTTP/1.1 clone --quiet "$url" "$dest" || rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "Cloned $name in $((SECONDS - start))s ($(du -sh "$dest" 2>/dev/null | cut -f1))."
        return 0
      fi
      case "$rc" in
        124) echo "Clone of $name TIMED OUT after $((SECONDS - start))s (attempt $attempt/2)." ;;
        137) echo "Clone of $name ignored SIGTERM, SIGKILLed (attempt $attempt/2)." ;;
        *)   echo "Clone of $name FAILED, git exit $rc (attempt $attempt/2)." ;;
      esac
      rm -rf "$dest"
    done
    die "could not clone $name after 2 attempts"
  }

  install_node_reqs() {
    local name="$1" dir="$2"
    if [ -f "$dir/requirements.txt" ]; then
      "$COMFY_PY" -m pip install -q -r "$dir/requirements.txt"
      echo "$name requirements installed."
    fi
  }

  echo "-------------------------------------------------------"
  echo "BACKGROUND WATCHER STARTED: SEEDVR2 CONFIG"
  echo "-------------------------------------------------------"

  echo "Waiting for ComfyUI root to exist..."
  for i in $(seq 1 300); do
    [ -d "$COMFY_ROOT" ] && break
    sleep 2
  done
  [ -d "$COMFY_ROOT" ] || { echo "Timed out waiting for ComfyUI root: $COMFY_ROOT"; exit 1; }

  echo "Waiting for ComfyUI server on 8188..."
  for i in $(seq 1 600); do
    curl -fsS "$HEALTH_URL" >/dev/null 2>&1 && break
    sleep 2
  done
  curl -fsS "$HEALTH_URL" >/dev/null 2>&1 || { echo "Timed out waiting for ComfyUI server: $HEALTH_URL"; exit 1; }

  echo "ComfyUI is live. Installing custom node and downloading models..."

  COMFY_PY="$(readlink -f "/proc/$(pgrep -f 'main\.py' | head -1)/exe" 2>/dev/null || true)"
  if [ ! -x "$COMFY_PY" ]; then
    COMFY_PY="$COMFY_ROOT/.venv-cu128/bin/python"
  fi
  echo "Using interpreter: $COMFY_PY"

  if ! command -v hf >/dev/null 2>&1; then
    "$COMFY_PY" -m pip install -q -U "huggingface_hub[hf_transfer]"
  fi

  ARGS_FILE="/workspace/runpod-slim/comfyui_args.txt"
  if [ -f "$ARGS_FILE" ] && ! grep -q "enable-cors-header" "$ARGS_FILE"; then
    echo "--enable-cors-header" >> "$ARGS_FILE"
  fi

  clone_node "seedvr2" "${CUSTOM_NODES[seedvr2]}" "$SEEDVR_NODE_DIR"
  install_node_reqs "seedvr2" "$SEEDVR_NODE_DIR"

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  ALL_DOWNLOAD_QUEUE=(
    "${HF_MODELS[seedvr2_ema_7b_fp16.safetensors]}|$SEEDVR_MODELS_DIR"
    "${HF_MODELS[ema_vae_fp16.safetensors]}|$SEEDVR_MODELS_DIR"
  )

  wait_for_download_batch() {
    local pid failed=0
    for pid in "${DOWNLOAD_PIDS[@]}"; do wait "$pid" || failed=1; done
    DOWNLOAD_PIDS=()
    return "$failed"
  }

  echo "Downloading ${#ALL_DOWNLOAD_QUEUE[@]} files (max $MAX_PARALLEL_DOWNLOADS at once)..."
  DOWNLOAD_PIDS=()
  for entry in "${ALL_DOWNLOAD_QUEUE[@]}"; do
    download_hf_file "${entry%%|*}" "${entry##*|}" &
    DOWNLOAD_PIDS+=("$!")
    if [ "${#DOWNLOAD_PIDS[@]}" -ge "$MAX_PARALLEL_DOWNLOADS" ]; then
      wait_for_download_batch || die "one or more model downloads failed"
    fi
  done
  [ "${#DOWNLOAD_PIDS[@]}" -gt 0 ] && { wait_for_download_batch || die "one or more model downloads failed"; }

  rm -rf "$TMP_DIR"

  echo "Downloads complete. Restarting ComfyUI to load node..."
  pkill -f "main.py" || true
  sleep 3
  cd "$COMFY_ROOT" && "$COMFY_PY" main.py --listen 0.0.0.0 --port 8188 --enable-cors-header >> /proc/1/fd/1 2>> /proc/1/fd/2 &

  echo "Waiting for ComfyUI to come back online..."
  for i in $(seq 1 300); do
    curl -fsS "$HEALTH_URL" >/dev/null 2>&1 && break
    sleep 2
  done
  curl -fsS "$HEALTH_URL" >/dev/null 2>&1 || { echo "Timed out waiting for ComfyUI to restart."; exit 1; }

  echo "-------------------------------------------------------"
  echo "DOWNLOAD COMPLETE - SEEDVR2 INSTALLED"
  echo "-------------------------------------------------------"

) 2>&1 | tee -a "$LOG_FILE" >> /proc/1/fd/1 &

echo "seedvr.sh: background watcher started, main boot can continue"
echo "seedvr.sh: tail -f $LOG_FILE"
exit 0
