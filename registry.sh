#!/bin/bash
# Registry of custom nodes and model download links.
# Sourced by setup scripts — do not execute directly.

# ComfyUI core source used when building an updated image.
COMFYUI_REPO="https://github.com/Comfy-Org/ComfyUI.git"

# Custom nodes — key: short name, value: git clone URL
declare -A CUSTOM_NODES
CUSTOM_NODES[seedvr2]="https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
CUSTOM_NODES[rgthree]="https://github.com/rgthree/rgthree-comfy"
CUSTOM_NODES[lanpaint]="https://github.com/scraed/LanPaint"
CUSTOM_NODES[videohelper]="https://github.com/kosinkadink/ComfyUI-VideoHelperSuite"
CUSTOM_NODES[frameinterp]="https://github.com/Fannovel16/ComfyUI-Frame-Interpolation"
CUSTOM_NODES[kjnodes]="https://github.com/kijai/ComfyUI-KJNodes"
CUSTOM_NODES[res4lyf]="https://github.com/ClownsharkBatwing/RES4LYF"
CUSTOM_NODES[krea2edit]="https://github.com/lbouaraba/comfyui-krea2edit"
CUSTOM_NODES[minimaxh3mod]="https://github.com/Luisacaotica/ComfyUI-MiniMaxH3Mod"
CUSTOM_NODES[promptbatcher]="https://github.com/ai-joe-git/ComfyUI-Simple-Prompt-Batcher"
CUSTOM_NODES[kreareason]="https://github.com/shootthesound/ComfyUI-KreaReason"
CUSTOM_NODES[krea2nag]="https://github.com/iljung1106/ComfyUI-Krea2-NAG"
CUSTOM_NODES[negpip]="https://github.com/blue-pen5805/ComfyUI-krea2-negpip"
CUSTOM_NODES[nag]="https://github.com/ChenDarYen/ComfyUI-NAG"

# HF models — key: filename, value: full download URL
declare -A HF_MODELS

# Diffusion Models
HF_MODELS[qwen_image_2.1_int8_convrot.safetensors]="https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_int8_convrot.safetensors"
HF_MODELS[wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors]="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
HF_MODELS[wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors]="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
HF_MODELS[z_image_turbo_bf16.safetensors]="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
HF_MODELS[flux-2-klein-9b-fp8.safetensors]="https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-fp8/resolve/main/flux-2-klein-9b-fp8.safetensors"
HF_MODELS[seedvr2_ema_7b_fp16.safetensors]="https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_fp16.safetensors"
HF_MODELS[darkBeastINT8Convrot2_darkBeastKREA2FP8.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/darkBeastINT8Convrot2_darkBeastKREA2FP8.safetensors"
HF_MODELS[krea2_turbo_fp8_scaled.safetensors]="https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors"
HF_MODELS[minimax_h3_fl2va_pruned_int8_convrot.safetensors]="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"
HF_MODELS[minimax_h3_ref2va_pruned_int8_convrot.safetensors]="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
HF_MODELS[museByStableYogi_v35Int8Extended.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/museByStableYogi_v35Int8Extended.safetensors"

# Checkpoints
HF_MODELS[big_lust_v1.6.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/big_lust_v1.6.safetensors"
HF_MODELS[gonzalomoXLFluxPony_v70PhotoXLDMD.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/gonzalomoXLFluxPony_v70PhotoXLDMD.safetensors"
HF_MODELS[intorealismUltra_v40.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/intorealismUltra_v40.safetensors"

# GGUFs


# LoRAs
HF_MODELS[Wan22_I2V_VBVR_HIGH_rank_64_fp16.safetensors]="https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/VBVR/Wan22_I2V_VBVR_HIGH_rank_64_fp16.safetensors"
HF_MODELS[wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors]="https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors"
HF_MODELS[wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors]="https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors"
HF_MODELS[Flux2-Klein-9B-consistency-V2.safetensors]="https://huggingface.co/dx8152/Flux2-Klein-9B-Consistency/resolve/main/Flux2-Klein-9B-consistency-V2.safetensors"
HF_MODELS[bfs_head_v1_flux-klein_9b_step3500_rank128.safetensors]="https://huggingface.co/Alissonerdx/BFS-Best-Face-Swap/resolve/main/bfs_head_v1_flux-klein_9b_step3500_rank128.safetensors"
HF_MODELS[wan2.2_i2v_high_ulitmate_pussy_asshole.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/wan2.2_i2v_high_ulitmate_pussy_asshole.safetensors"
HF_MODELS[wan2.2_i2v_low_ulitmate_pussy_asshole.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/wan2.2_i2v_low_ulitmate_pussy_asshole.safetensors"
HF_MODELS[Mystic-XXX-ZIT-V6.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/Mystic-XXX-ZIT-V6.safetensors"
HF_MODELS[Z-Detail-Slider.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/Z-Detail-Slider.safetensors"
HF_MODELS[zimage-igbaddie_pruned.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/zimage-igbaddie_pruned.safetensors"
HF_MODELS[realism_engine_krea2_v2.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/realism_engine_krea2_v2.safetensors"
HF_MODELS[snofs_krea_v1_1.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/snofs_krea_v1_1.safetensors"
HF_MODELS[krea2_identity_edit_v1_2.safetensors]="https://huggingface.co/conradlocke/krea2-identity-edit/resolve/main/krea2_identity_edit_v1_2.safetensors"
HF_MODELS[minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors]="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors"
HF_MODELS[MysticXXX_MMH3-V4.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/MysticXXX_MMH3-V4.safetensors"
HF_MODELS[hmmasturbation_v2.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/hmmasturbation_v2.safetensors"
HF_MODELS[H3_VBVR_Pro_attn_only.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/H3_VBVR_Pro_attn_only.safetensors"
HF_MODELS[K_excessivecum.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/K_excessivecum.safetensors"
HF_MODELS[snofs_krea_v1_4.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/snofs_krea_v1_4.safetensors"
HF_MODELS[realism_engine_krea2_v3.1.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/realism_engine_krea2_v3.1.safetensors"
HF_MODELS[krea2-bloomgirls-realism-step00004000.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/krea2-bloomgirls-realism-step00004000.safetensors"
HF_MODELS[RealisticSnapshotKrea2.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/RealisticSnapshotKrea2.safetensors"
HF_MODELS[famegrid_spicy_3167060.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/famegrid_spicy_3167060.safetensors"
HF_MODELS[anal_helper_krea2_loraholic.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/anal_helper_krea2_loraholic.safetensors"

# Text Encoders
HF_MODELS[qwen3vl_8b_int8_convrot.safetensors]="https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3vl_8b_int8_convrot.safetensors"
HF_MODELS[umt5_xxl_fp8_e4m3fn_scaled.safetensors]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
HF_MODELS[qwen_3_4b.safetensors]="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
HF_MODELS[qwen_3_8b_fp8mixed.safetensors]="https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
HF_MODELS[qwen3vl_4b_fp8_scaled.safetensors]="https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors"
HF_MODELS[qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors]="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
HF_MODELS[qwen3vl_4b_heretic_fp8_e4m3fn.safetensors]="https://huggingface.co/DreamFast/Qwen3-VL-4b-Heretic-ComfyUI/resolve/main/qwen3-vl-4b-heretic_fp8_e4m3fn.safetensors"

# VAE
HF_MODELS[qwen_image_2.1_vae_bf16.safetensors]="https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"
HF_MODELS[wan_2.1_vae.safetensors]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
HF_MODELS[ema_vae_fp16.safetensors]="https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors"
HF_MODELS[ae.safetensors]="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
HF_MODELS[flux2-vae.safetensors]="https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
HF_MODELS[qwen_image_vae.safetensors]="https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors"
HF_MODELS[minimax_h3_video_vae_fp16.safetensors]="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors"
HF_MODELS[minimax_h3_audio_vae_fp32.safetensors]="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors"
HF_MODELS[Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors]="https://huggingface.co/skhaai/airebels/resolve/main/models/Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors"

# Clip Vision
HF_MODELS[clip_vision_h.safetensors]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"

# Original — upstream source URLs for files re-hosted on skhaai/airebels HF for faster download.
# key: filename (matches the HF_MODELS key), value: the original download URL it was copied from.
declare -A ORIGINAL
ORIGINAL[snofs_krea_v1_1.safetensors]="https://civitai.red/models/1972981/snofs-sex-nudes-other-fun-stuff?modelVersionId=3104629"
ORIGINAL[MysticXXX_MMH3-V4.safetensors]="https://civitai.red/models/2856467/mmh3-mystic-xxx?modelVersionId=3266628"
ORIGINAL[hmmasturbation_v2.safetensors]="https://civitai.red/api/download/models/3310312?fileId=3195593"
ORIGINAL[H3_VBVR_Pro_attn_only.safetensors]="https://civitai.red/api/download/models/3306139?fileId=3191174"
ORIGINAL[museByStableYogi_v35Int8Extended.safetensors]="https://civitai.red/models/2741166/muse-by-stable-yogi-krea2?modelVersionId=3258954"
ORIGINAL[K_excessivecum.safetensors]="https://civitai.red/models/2512358?modelVersionId=3221218"
ORIGINAL[snofs_krea_v1_4.safetensors]="https://civitai.red/models/1972981/snofs-sex-nudes-other-fun-stuff?modelVersionId=3290120"
ORIGINAL[realism_engine_krea2_v3.1.safetensors]="https://civitai.red/models/2688234/realism-engine-ideogram-4-krea-2?modelVersionId=3109006"
ORIGINAL[krea2-bloomgirls-realism-step00004000.safetensors]="https://civitai.red/models/2735553/krea-2-bloomgirls-ultrarealism?modelVersionId=3191538"
ORIGINAL[RealisticSnapshotKrea2.safetensors]="https://civitai.red/models/2268008/realistic-snapshot-z-image-turbo-krea-2?modelVersionId=3084537"
ORIGINAL[Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors]="https://huggingface.co/spacepxl/Wan2.1-VAE-upscale2x/resolve/main/Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors"
ORIGINAL[famegrid_spicy_3167060.safetensors]="https://civitai.red/api/download/models/3278885?fileId=3167060"
ORIGINAL[anal_helper_krea2_loraholic.safetensors]="https://civitai.red/api/download/models/3105253?fileId=2985077"

# CivitAI LoRAs — key: filename, value: direct download URL
# (CivitAI needs its own fetch — the hf CLI can't read these URLs)
declare -A CIVITAI_LORAS
CIVITAI_LORAS[HMBreasts_krea2_epoch12.safetensors]="https://civitai.com/api/download/models/3081828?fileId=2961104"
CIVITAI_LORAS[kodak.safetensors]="https://civitai.com/api/download/models/3135222?fileId=3015964"
CIVITAI_LORAS[ultra_real_krea2_v2.safetensors]="https://civitai.com/api/download/models/3182356?fileId=3062944"
CIVITAI_LORAS[realistic_custom_face_krea2.safetensors]="https://civitai.com/api/download/models/3293437?fileId=3178040"
