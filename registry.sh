#!/bin/bash
# Registry of custom nodes and model download links.
# 2026-11-27: pruned to what scripts/krea2raw-seedvr2.sh downloads (the only live template); the full list
#   for the archived scripts is in git history (commit a523091).
# Sourced by setup scripts — do not execute directly.

# ComfyUI core source used when building an updated image.
COMFYUI_REPO="https://github.com/Comfy-Org/ComfyUI.git"

# Custom nodes — key: short name, value: git clone URL
declare -A CUSTOM_NODES
CUSTOM_NODES[seedvr2]="https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
CUSTOM_NODES[rgthree]="https://github.com/rgthree/rgthree-comfy"
CUSTOM_NODES[lanpaint]="https://github.com/scraed/LanPaint"
CUSTOM_NODES[kjnodes]="https://github.com/kijai/ComfyUI-KJNodes"
CUSTOM_NODES[res4lyf]="https://github.com/ClownsharkBatwing/RES4LYF"
CUSTOM_NODES[krea2edit]="https://github.com/lbouaraba/comfyui-krea2edit"
CUSTOM_NODES[promptbatcher]="https://github.com/ai-joe-git/ComfyUI-Simple-Prompt-Batcher"
CUSTOM_NODES[kreareason]="https://github.com/shootthesound/ComfyUI-KreaReason"
CUSTOM_NODES[krea2nag]="https://github.com/iljung1106/ComfyUI-Krea2-NAG"
CUSTOM_NODES[negpip]="https://github.com/blue-pen5805/ComfyUI-krea2-negpip"
CUSTOM_NODES[twostagesampler]="https://github.com/Auryg/Krea-2-Two-Stage-Sampler"
# sesquilsr removed: caused repeated hang in git index-pack at pod deploy; bislerp stays.

# HF models — key: filename, value: full download URL
declare -A HF_MODELS

# Diffusion Models
HF_MODELS[seedvr2_ema_7b_fp16.safetensors]="https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_fp16.safetensors"
HF_MODELS[krea2_raw_fp8_scaled.safetensors]="https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_raw_fp8_scaled.safetensors"

# LoRAs
HF_MODELS[realism_engine_krea2_v2.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/realism_engine_krea2_v2.safetensors"
HF_MODELS[snofs_krea_v1_1.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/snofs_krea_v1_1.safetensors"
HF_MODELS[krea2_identity_edit_v1_2.safetensors]="https://huggingface.co/conradlocke/krea2-identity-edit/resolve/main/krea2_identity_edit_v1_2.safetensors"
HF_MODELS[K_excessivecum.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/K_excessivecum.safetensors"
HF_MODELS[snofs_krea_v1_4.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/snofs_krea_v1_4.safetensors"
HF_MODELS[realism_engine_krea2_v3.1.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/realism_engine_krea2_v3.1.safetensors"
HF_MODELS[krea2-bloomgirls-realism-step00004000.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/krea2-bloomgirls-realism-step00004000.safetensors"
HF_MODELS[RealisticSnapshotKrea2.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/RealisticSnapshotKrea2.safetensors"
HF_MODELS[famegrid_spicy_3167060.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/famegrid_spicy_3167060.safetensors"
HF_MODELS[anal_helper_krea2_loraholic.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/anal_helper_krea2_loraholic.safetensors"

# Text Encoders
HF_MODELS[qwen3vl_4b_fp8_scaled.safetensors]="https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors"

# VAE
HF_MODELS[wan_2.1_vae.safetensors]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
HF_MODELS[ema_vae_fp16.safetensors]="https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors"
HF_MODELS[qwen_image_vae.safetensors]="https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors"

# Original — upstream source URLs for files re-hosted on skhaai/airebels HF for faster download.
# key: filename (matches the HF_MODELS key), value: the original download URL it was copied from.
declare -A ORIGINAL
ORIGINAL[snofs_krea_v1_1.safetensors]="https://civitai.red/models/1972981/snofs-sex-nudes-other-fun-stuff?modelVersionId=3104629"
ORIGINAL[K_excessivecum.safetensors]="https://civitai.red/models/2512358?modelVersionId=3221218"
ORIGINAL[snofs_krea_v1_4.safetensors]="https://civitai.red/models/1972981/snofs-sex-nudes-other-fun-stuff?modelVersionId=3290120"
# realism_engine_krea2_v2: civitai model 2688234, version ID not recorded — source URL unknown.
ORIGINAL[realism_engine_krea2_v3.1.safetensors]="https://civitai.red/models/2688234/realism-engine-ideogram-4-krea-2?modelVersionId=3109006"
ORIGINAL[krea2-bloomgirls-realism-step00004000.safetensors]="https://civitai.red/models/2735553/krea-2-bloomgirls-ultrarealism?modelVersionId=3191538"
ORIGINAL[RealisticSnapshotKrea2.safetensors]="https://civitai.red/models/2268008/realistic-snapshot-z-image-turbo-krea-2?modelVersionId=3084537"
ORIGINAL[famegrid_spicy_3167060.safetensors]="https://civitai.red/api/download/models/3278885?fileId=3167060"
ORIGINAL[anal_helper_krea2_loraholic.safetensors]="https://civitai.red/api/download/models/3105253?fileId=2985077"

# CivitAI LoRAs — key: filename, value: direct download URL
# (CivitAI needs its own fetch — the hf CLI can't read these URLs)
declare -A CIVITAI_LORAS
CIVITAI_LORAS[HMBreasts_krea2_epoch12.safetensors]="https://civitai.com/api/download/models/3081828?fileId=2961104"
CIVITAI_LORAS[kodak.safetensors]="https://civitai.com/api/download/models/3135222?fileId=3015964"
CIVITAI_LORAS[ultra_real_krea2_v2.safetensors]="https://civitai.com/api/download/models/3182356?fileId=3062944"
CIVITAI_LORAS[realistic_custom_face_krea2.safetensors]="https://civitai.com/api/download/models/3293437?fileId=3178040"
CIVITAI_LORAS[krea2_raw_to_turbo_r256_comfy.safetensors]="https://civitai.com/api/download/models/3066079?fileId=2944898"
CIVITAI_LORAS[snofs_krea_v1_5.safetensors]="https://civitai.com/api/download/models/3390681?fileId=3280058"
