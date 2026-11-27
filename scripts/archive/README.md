# Archived scripts

Inherited from the upstream fork and never attached to a RunPod template.
Kept for reference only — not maintained, and they predate the hardening
in scripts/krea2v2.sh.

- krea2.sh — superseded by krea2v2.sh
- sdxl.sh, sdxl-to-zit.sh, sdxlinpaint.sh — SDXL workflows, unused
- zit.sh — Z-Image Turbo workflow, unused
- flux-klein-edit.sh — FLUX Klein edit workflow, unused

Archived 2026-11-27: templates no longer used. Only the 'Krea2 Raw Upscale Pipeline' template
is in use, and it runs scripts/krea2raw-seedvr2.sh. registry.sh was pruned to that script's
downloads at the same time, so these scripts no longer run as they are; their registry entries
are in git history (commit a523091). A RunPod template that still points at one of them by its
old path gets a 404 at boot.

- krea2v2.sh, krea2v2-seedvr2.sh: Krea2 t2i / Muse and integrated gen + upscale (krea2raw-seedvr2.sh's parent)
- seedvr.sh: SeedVR2 upscale
- qwenimage21edit.sh: Qwen Image 2.1 Edit (the stablev3 image)
- h3.sh: MiniMax H3 image to video
- wan22.sh, video-interpolate-upscale.sh: video work, never reviewed after the fork
