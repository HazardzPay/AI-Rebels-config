# ComfyUI images

`hazardzpay/comfyui:stablev3` uses `runpod/comfyui:cuda12.8` and installs the
ComfyUI release selected by `COMFYUI_VERSION` in `Dockerfile.stablev3`.
Only ComfyUI is pinned here. Python, CUDA and PyTorch come from RunPod; the
release's own requirements supply ComfyUI dependencies. The build respects
RunPod's dependency constraints and fails if its PyTorch packages change.

## Images

- `hazardzpay/comfyui:stablev2` — base for the live 'Krea2 Raw Upscale Pipeline' template (scripts/krea2raw-seedvr2.sh).
- `hazardzpay/comfyui:stablev3` — Qwen Image 2.1 Edit (not in use since the 2026-11-27 archive).

`docker/archive/Dockerfile` and `docker/archive/Dockerfile.cuda13` are LEGACY (moved to
docker/archive/ 2026-11-27): no workflow builds them. Both originally tagged `airebels/comfyui:*` (the upstream namespace) and
their workflows were removed so a `docker/boot.sh` edit can't trigger a stray push.

`docker/boot.sh` is shared by both live images — treat edits to it carefully.

The build replaces `/opt/comfyui-baked` core files and updates the RunPod bundle
marker. The inherited `/start.sh` copies this into a fresh workspace, or syncs
core into an existing workspace while preserving models and user data.

The `Build and Push Docker Image (stablev3)` GitHub workflow builds the image,
checks startup and Qwen Image 2.1 node registration on CPU with both fresh and
simulated outdated workspaces, then pushes that same tested image to Docker Hub.
Run it manually to rebuild against a newer RunPod base. Relevant Docker files
also trigger it when pushed to `main`.

In RunPod, set the container image to `hazardzpay/comfyui:stablev3` and keep the
existing `SETUP_SCRIPT_URL` pointing to `scripts/archive/qwenimage21edit.sh` (archived 2026-11-27: the
registry no longer carries its models). Models and
extra custom nodes are downloaded by that setup script at boot.

Use a fresh workspace for the first GPU generation test. The automated checks
do not run model inference or prove compatibility with packages installed in
an arbitrary existing workspace's virtual environment.
