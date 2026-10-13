---
name: boot-script
description: Create or update a ComfyUI RunPod setup script in this repository. Use for new pod scripts and for adding, replacing, or removing registered models or custom nodes.
---

## CURRENT PRACTICE — supersedes the template below

Canonical reference: `scripts/krea2v2.sh` (and `scripts/krea2v2-seedvr2.sh`).
The Step 3 template is the ORIGINAL from the upstream fork and is out of date.
Match these deltas instead:

- `timeout --kill-after=<grace> <sec>` on every clone and download (plain `timeout`
  alone does not cap a SIGTERM-ignoring child).
- `die()` fail-fast helper + 2-3 attempt retry loops around clones and downloads.
- Sparse clone via `--filter=blob:none` with per-repo exclude lists for large
  example/doc dirs.
- `COMFY_PY` auto-detected from the running `main.py` process, not hardcoded.
- `--enable-cors-header` appended to `/workspace/runpod-slim/comfyui_args.txt`.
- `hf_transfer` + Xet buffer caps, with `MAX_PARALLEL_DOWNLOADS` gating concurrency.
- `LOG_FILE` falls back to `/dev/null` if `/workspace` is not mounted.
- CivitAI downloads use `curl -fL` with an `Authorization: Bearer` header (never a
  token in the URL), sourced from `CIVITAI_LORAS` in `registry.sh`.

# Boot script

Work only with scripts in `scripts/` and the catalog in `registry.sh`.

## Existing scripts

Read the target script and `registry.sh` before editing. Confirm every requested
model or custom-node key is present in the relevant registry array. If a key is
missing, explain that it must be added to `registry.sh` first.

For a model-only change, modify only the corresponding `download_hf_file` lines:

- Add a line before `wait` for an addition.
- Replace one download line for a swap.
- Remove only that line for a removal.

Preserve the script's setup, node installation, restart, and logging behavior.

## New scripts

Read `registry.sh` and a relevant existing script first. Create the new file in
`scripts/`, using the established RunPod/ComfyUI script structure. Use
`CUSTOM_NODES[...]` and `HF_MODELS[...]` from `registry.sh`; do not hardcode
repository or model URLs in the shell script.

Use the repository's standard ComfyUI location and virtual-environment Python,
keep downloads parallel with one final `wait`, and retain the post-install
ComfyUI restart so newly installed nodes and models are loaded.

When details that affect the file are missing (filename, registry keys, or model
destination folders), ask before writing it. Validate shell syntax after a
change and summarize exactly what changed.
