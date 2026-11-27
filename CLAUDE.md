# AI Rebels Config

## Project structure for agents and skills

Always place new subagents in `.claude/agents/` and new skills in `.claude/skills/`. Never create them in AppData, home directories, or any other location.

All URLs and git repos live in `registry.sh` — never hardcode them in `.sh` files.

## Live vs archived

One RunPod template is in use: 'Krea2 Raw Upscale Pipeline', which runs `scripts/krea2raw-seedvr2.sh`
on the `hazardzpay/comfyui:stablev2` image. Everything in `scripts/archive/` is retired (see its
README); `registry.sh` lists only what the live script downloads.

`scripts/krea2raw-seedvr2.sh` is the pattern reference: copy its hardening (retry loops,
`timeout --kill-after`, `die()`, sparse clone, `COMFY_PY` detection, the boot watcher) when writing
or editing a script.

## A push to main is a deploy

Every pod boot fetches the boot script, `registry.sh` and `lock.sh` from this repo (`CONFIG_REF`,
default main). Never push while a pod is booting. Run `bash -n` on every changed script and
`bash .github/scripts/check_registry.sh` (CI runs it too) before pushing.

## Build lock

`lock.sh` pins a commit per custom node, an HF revision and a sha256 per model, and the expected
ComfyUI, torch and pip set. The pod env `LOCK_MODE` is enforce on the live template, so any
mismatch stops the boot. A new lock comes from a record-mode pod via `tools/make_lock.py`. Every
boot writes BUILD_FINGERPRINT.json and ends BOOT_STATUS with its build ID. `comfy_nodes/` holds
single-file nodes fetched at `CONFIG_REF` and hash-checked like models (none fetched at present).

When the template's `SETUP_SCRIPT_URL` is pinned to an older commit, pin `CONFIG_REF` to the same
commit: an older script reads registry.sh and lock.sh at `CONFIG_REF`.

## Public repo: nothing personal

No real names or emails, no local paths, no pod or template IDs, no keys or tokens. Commits are
authored as HazardzPay <hazardzpay@proton.me> or Claude. Check the staged diff and the commit
metadata before every push.

## Tools

- `tools/comfy_queue.py`: runs a test definition against a live ComfyUI through its HTTP API, one
  queued job per run, so every PNG's metadata holds its exact prompt; `--dry-run`, `--zip`,
  `--resume`, `--max-runs`; remotely with `--server https://PODID-8188.proxy.runpod.net
  --output-dir DIR --fetch` (every download checked whole). Definitions live in the owner's private
  notes, not here. Its Mac-side checks (cast, adult wording, slot repeats) are skipped on a pod.
- `tools/compare.py`: pixel-diff matrix, scene-change flags, embedded-prompt check, contact and
  crop sheets for a results folder.
- `tools/make_lock.py`: writes lock.sh from a record-mode pod's fingerprint.
- `tools/arcface_div.py`: face-identity diversity (insightface buffalo_l).

The master copies of comfy_queue.py and compare.py are kept outside this repo and published here
when a pod-side change goes out.
