---
name: boot-script
description: Generate or modify a ComfyUI RunPod pod setup shell script for the AI-Rebels-config repo. Use this skill whenever the user wants to create a boot script, modify an existing script (add/replace/remove models), or says things like "make a script for X", "create a .sh for [model/workflow]", "new pod script", "add [nodes/models] script", "setup script for [workflow name]", "add this model to [script]", "replace the model in [script]", "swap out [model] in [script]". Always invoke this skill rather than writing scripts freehand.
model: sonnet
---

# boot-script

Generate a new setup script, or modify the model downloads in an existing one.

## Step 0: Detect intent — new script or modify existing?

- If the user references an **existing script** by name (e.g. "add X to foo.sh", "replace the model in bar.sh", "swap out Y for Z in baz.sh") → follow the **Modify path** below.
- Otherwise → follow the **New script path**.

---

## MODIFY PATH — add or replace models in an existing script

### M1: Read the target script and the registry

Read the script from `scripts/<name>.sh` and read `registry.sh`. Do both in parallel.

### M2: Validate registry keys

Check that every model key the user wants to add/swap exists in `HF_MODELS` in `registry.sh`. If any key is missing, stop and tell the user — they must add it to `registry.sh` first.

### M3: Apply the change — touch only the download lines

Locate the parallel download block (lines of the form `download_hf_file "${HF_MODELS[...]}" "$MODELS_DIR/..."  &`).

- **Add a model**: insert one new `download_hf_file` line before the `wait`, using the correct `$MODELS_DIR/<subdir>` for that model type.
- **Replace a model**: swap the old `download_hf_file` line for the new one. Keep the destination subdir the same unless the user specifies otherwise.
- **Remove a model**: delete only that `download_hf_file` line.

**Do not touch any other part of the script** — not the header, variables, node installs, restart block, or log lines.

### M4: Confirm

Show the user a diff-style summary of exactly which lines changed. Nothing else.

---

## NEW SCRIPT PATH

## Step 1: Read the registry

Read `registry.sh` from the repo root. Parse all `CUSTOM_NODES[key]` and `HF_MODELS[key]` entries so you know what's available.

If the user requests a key that doesn't exist in the registry, stop and tell them — they must add it to `registry.sh` first before the script can be generated.

## Step 2: Gather requirements

If not already specified by the user, ask for:

1. **Output filename** — written to `scripts/` (e.g. `foo.sh`)
2. **Custom nodes** — which `CUSTOM_NODES[key]` entries to install (omit if models-only)
3. **Models** — which `HF_MODELS[key]` entries to download, and for each: destination subdir under `$COMFY_ROOT/models/` (`diffusion_models`, `checkpoints`, `loras`, `text_encoders`, `vae`, `clip_vision`, or a tool-specific name)

## Step 3: Write the script

Use this exact structure — do not deviate:

```bash
#!/bin/bash
set -euo pipefail

LOG_FILE="/workspace/<name>-background.log"

(
  set -euo pipefail

  COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  # one variable per custom node dir, e.g.:
  # FOO_NODE_DIR="$CUSTOM_NODES_DIR/foo-comfy"
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
  echo "BACKGROUND WATCHER STARTED: <NAME> CONFIG"
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

  echo "ComfyUI is live. Installing custom node(s) and downloading models..."

  if ! command -v hf >/dev/null 2>&1; then
    pip install -U "huggingface_hub[hf_transfer]"
  fi

  # --- custom node installs (repeat block per node) ---
  if [ ! -d "$FOO_NODE_DIR" ]; then
    echo "Cloning foo..."
    git clone "${CUSTOM_NODES[foo]}" "$FOO_NODE_DIR"
  else
    echo "foo already present, skipping clone."
  fi
  if [ -f "$FOO_NODE_DIR/requirements.txt" ]; then
    pip install -q -r "$FOO_NODE_DIR/requirements.txt"
  fi
  # --- end custom node installs ---

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  # parallel downloads — one line per model, all backgrounded
  download_hf_file "${HF_MODELS[model1.safetensors]}" "$MODELS_DIR/diffusion_models" &
  download_hf_file "${HF_MODELS[model2.safetensors]}" "$MODELS_DIR/loras" &
  wait

  rm -rf "$TMP_DIR"

  echo "Downloads complete. Restarting ComfyUI to load custom node(s)..."
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
  echo "DOWNLOAD COMPLETE - <NAME> INSTALLED"
  echo "-------------------------------------------------------"

) >> /proc/1/fd/1 2>> /proc/1/fd/2 &

echo "<name>.sh: background watcher started, main boot can continue"
echo "<name>.sh: tail -f $LOG_FILE"
exit 0
```

### Key rules when filling in the template

- **Always include the ComfyUI restart block** — even if there are no custom nodes, still do it so models are available on first boot without a manual restart
- **Never use bare `python`** — only `.venv-cu128/bin/python`
- **Never hardcode URLs or git repos** — always `${CUSTOM_NODES[key]}` and `${HF_MODELS[key]}`
- **All downloads parallel** — every `download_hf_file` call gets `&`, one `wait` at the end

Write the completed file to `scripts/<filename>`.
