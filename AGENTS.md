# AI Rebels Config

## Project structure for agents and skills

Always place new subagents in `.Codex/agents/` and new skills in `.Codex/skills/`. Never create them in AppData, home directories, or any other location.

All URLs and git repos live in `registry.sh` — never hardcode them in `.sh` files.

## Live vs archived

Live templates and the scripts they point at:
- Krea2 t2i / Krea2 Muse → `scripts/krea2v2.sh`
- Integrated gen + upscale → `scripts/krea2v2-seedvr2.sh`
- SeedVR2 upscale → `scripts/seedvr.sh`
- Qwen Image 2.1 Edit → `scripts/qwenimage21edit.sh`

Canonical pattern reference: `scripts/krea2v2.sh`. Copy its hardening — retry
loops, `timeout --kill-after`, `die()`, sparse clone, `COMFY_PY` detection —
when writing or editing any script. The template in
`.claude/skills/boot-script/SKILL.md` is superseded; read the CURRENT PRACTICE
block at the top of that file first.

`scripts/archive/` is not in use. `scripts/h3.sh`, `scripts/wan22.sh` and
`scripts/video-interpolate-upscale.sh` are future video work and are unreviewed
since the fork.
