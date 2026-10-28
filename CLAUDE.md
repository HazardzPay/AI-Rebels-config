# AI Rebels Config

## Project structure for agents and skills

Always place new subagents in `.claude/agents/` and new skills in `.claude/skills/`. Never create them in AppData, home directories, or any other location.

All URLs and git repos live in `registry.sh` — never hardcode them in `.sh` files.

## Live vs archived

Live templates and the scripts they point at:
- Krea2 t2i / Krea2 Muse → `scripts/krea2v2.sh`
- Integrated gen + upscale → `scripts/krea2v2-seedvr2.sh`
- Integrated gen + upscale (RAW only, faster boot) → `scripts/krea2raw-seedvr2.sh`
- SeedVR2 upscale → `scripts/seedvr.sh`
- Qwen Image 2.1 Edit → `scripts/qwenimage21edit.sh`
- MiniMax H3 image to video → `scripts/h3.sh` (ported to the v3 boot scaffolding 2026-10-27)

Canonical pattern reference: `scripts/krea2v2.sh`. Copy its hardening — retry
loops, `timeout --kill-after`, `die()`, sparse clone, `COMFY_PY` detection —
when writing or editing any script. The template in
`.claude/skills/boot-script/SKILL.md` is superseded; read the CURRENT PRACTICE
block at the top of that file first.

`scripts/archive/` is not in use. `scripts/wan22.sh` and
`scripts/video-interpolate-upscale.sh` are future video work and are unreviewed
since the fork.

## Tools

`tools/comfy_queue.py` — runs a test definition against a live ComfyUI through its HTTP
API, one queued job per run, so every PNG's metadata holds its exact prompt. Warm-up render
after any LoRA-state or seed change; index.jsonl per test; `--dry-run`, `--zip`, `--resume`, `--max-runs`. Test definitions
live in the owner's private vault (tests/), not in this public repo. Run it on the pod, or
remotely with `--server https://PODID-8188.proxy.runpod.net --output-dir DIR --fetch`
(downloads every image through /view; sends a User-Agent because Cloudflare blocks urllib's).

Per-run `nodes` overrides set literal inputs on any node by id (e.g. stage 1 / RAW-path
LoraLoaderModelOnly strengths, which the Power Lora Loader does not reach).

`tools/arcface_div.py` — face-identity diversity: mean pairwise ArcFace (insightface buffalo_l)
cosine similarity between the people in each group of a results folder; lower is more diverse.
Runs anywhere `pip install insightface onnxruntime opencv-python-headless` works (the model
downloads from GitHub on first use).

`tools/compare.py` — pairwise pixel-diff matrix, probable-scene-change flags, embedded-prompt
check and labelled contact/crop sheets for a results folder. Pillow + numpy; runs on the pod
or locally.
