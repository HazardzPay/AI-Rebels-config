#!/bin/bash
# lock.sh - build lock for the boot scripts. Sourced after registry.sh; do not execute.
# Generated 2026-11-07 by tools/make_lock.py from: pod da305969e2b8 + upstream
# 2026-11-10: NODE_SOURCE added (kjnodes); every pin is unchanged, so LOCK_ID is kept.
# Edit by regenerating, not by hand. LOCK_MODE (pod env): off | record (default) | enforce.
LOCK_ID="2026-11-07-a"
COMFYUI_EXPECTED="0.30.0"
TORCH_EXPECTED="2.10.0+cu128"
PIP_FREEZE_SHA256_EXPECTED="2340d7921803846033cd9dfcdf3a5cb51f9e9e784e4e532591c0818edf1a0573"

declare -A NODE_LOCK
NODE_LOCK[kjnodes]="9e185a1a8bc12a919d035a74bdbdcb0f1a14ba81"
NODE_LOCK[krea2edit]="13ef60f20828949becada815d3cbc371eb5ccaab"
NODE_LOCK[krea2nag]="0afb38dfc4ae4040d621ac5a46e1761b83fa2a43"
NODE_LOCK[kreareason]="196b8993e62bfc3450178b2051805f8ddbd366d1"
NODE_LOCK[lanpaint]="2d7912f9a5efe5ece8de334c7ca18317b8288c39"
NODE_LOCK[negpip]="6e2a66505033e4359d69adf4813aa21b74ad01de"
NODE_LOCK[promptbatcher]="f7f14462ff06a50cac6c14b668b822f6e2640a54"
NODE_LOCK[res4lyf]="6780724de0ddb98e7454d54bb80387836a911ece"
NODE_LOCK[rgthree]="bc48c6aaeca87bedbc14245d89f9bc6be37a630e"
NODE_LOCK[seedvr2]="4490bd1f482e026674543386bb2a4d176da245b9"
NODE_LOCK[twostagesampler]="df2692f11d5227b440c501b1f22ca5c63987530c"

# Nodes whose locked commit cannot be fetched from the registry URL: the folder was on the pod before the boot
# script's clone step, at a commit upstream does not serve. The boot script still compares the pod's commit
# with NODE_LOCK and, in enforce mode, stops on a mismatch; it cannot restore the commit if the folder is absent.
declare -A NODE_SOURCE
NODE_SOURCE[kjnodes]="preinstalled"

declare -A HF_REVISION
HF_REVISION[K_excessivecum.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[RealisticSnapshotKrea2.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[anal_helper_krea2_loraholic.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[ema_vae_fp16.safetensors]="09ced71023636e9bc8cdf9cdecfb2625d1e691e8"
HF_REVISION[famegrid_spicy_3167060.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[krea2-bloomgirls-realism-step00004000.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[krea2_identity_edit_v1_2.safetensors]="f33b26291c640e8ec50b0da420bfee3c9a660daa"
HF_REVISION[krea2_raw_fp8_scaled.safetensors]="588feaf955b08b9ac4723eeb751752ab045dba71"
HF_REVISION[qwen3vl_4b_fp8_scaled.safetensors]="588feaf955b08b9ac4723eeb751752ab045dba71"
HF_REVISION[qwen_image_vae.safetensors]="588feaf955b08b9ac4723eeb751752ab045dba71"
HF_REVISION[realism_engine_krea2_v2.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[realism_engine_krea2_v3.1.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[seedvr2_ema_7b_fp16.safetensors]="09ced71023636e9bc8cdf9cdecfb2625d1e691e8"
HF_REVISION[snofs_krea_v1_1.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[snofs_krea_v1_4.safetensors]="7cc34083e013c0daa918eb4d14b8d041aa8f8109"
HF_REVISION[wan_2.1_vae.safetensors]="123acf1cc74bccbb9bfff8ac1ee72edc08c2341d"

declare -A MODEL_SHA256
MODEL_SHA256[HMBreasts_krea2_epoch12.safetensors]="8384956ca76cf2e037b5e05c1e4ccfc75324775bbb54fed85a5d45ded35256cd"
MODEL_SHA256[K_excessivecum.safetensors]="90e4c4270a78f2b6bd8bda542806de69a2764a8b8e9abe86dcefea57fc7a6e76"
MODEL_SHA256[RealisticSnapshotKrea2.safetensors]="dfd67eb881bec4caeb9409e5b7c127adcb9fb724e6007e1e77165af51e6f908d"
MODEL_SHA256[anal_helper_krea2_loraholic.safetensors]="d311f0c556617d45ff29e604794ebe235d5adec7c2a9e2d8fec0119434b13d85"
MODEL_SHA256[ema_vae_fp16.safetensors]="20678548f420d98d26f11442d3528f8b8c94e57ee046ef93dbb7633da8612ca1"
MODEL_SHA256[famegrid_spicy_3167060.safetensors]="7b4a37a9b9ec3885bf39242f2d4f691f186d959cbaaa30b0630e4631767b425e"
MODEL_SHA256[kodak.safetensors]="578be79ba473ca37dd1865fca07eade6f4fc7082241802ba2a7207f281957980"
MODEL_SHA256[krea2-bloomgirls-realism-step00004000.safetensors]="7ff5ed79d0350c7360b1861829257cbd82b7ca0a75adb97c8716dd1327516c72"
MODEL_SHA256[krea2_identity_edit_v1_2.safetensors]="6adf9a69cc9502d286db7b69964d37da7e9cfe4b05b4d004bc275f087d3fd3cf"
MODEL_SHA256[krea2_raw_fp8_scaled.safetensors]="48cd5d6c100297968349b41a8e77c6591d1dac18a215807f5f25f59e5c54cd61"
MODEL_SHA256[krea2_raw_to_turbo_r256_comfy.safetensors]="e9e99b6f28a8fcae4ad7d0298c185b23af71f5fc85ad1819d624724c98df4892"
MODEL_SHA256[qwen3vl_4b_fp8_scaled.safetensors]="54bd5144df0bbc25dd6ccadfcb826b521445a1b06ae5a42570bdd2974ca87094"
MODEL_SHA256[qwen_image_vae.safetensors]="a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f"
MODEL_SHA256[realism_engine_krea2_v2.safetensors]="1815c6ac01216ad62f8dd17edab7c1fd31edf16c1b11434317123bae60e33257"
MODEL_SHA256[realism_engine_krea2_v3.1.safetensors]="a6712629445a2e91a616568e82befa8c8c7518e891a0f7c9918138634b5b54a5"
MODEL_SHA256[realistic_custom_face_krea2.safetensors]="028dd9bb6152a2e077976df249cdcb7ddbd5e8271b469cde29d390c432d1192c"
MODEL_SHA256[seedvr2_ema_7b_fp16.safetensors]="7b8241aa957606ab6cfb66edabc96d43234f9819c5392b44d2492d9f0b0bbe4a"
MODEL_SHA256[snofs_krea_v1_1.safetensors]="af6f66910ab1c0ec158b83cdd551a6ccfd14d0f2f79ceee7485f42fddac90a65"
MODEL_SHA256[snofs_krea_v1_4.safetensors]="767888edde83003f14cf930f13f174fe2a7431e252a515ddf04bd93d382a8932"
MODEL_SHA256[snofs_krea_v1_5.safetensors]="326a1f23ed4f728238d37d5c84b02086871d2a1e4c5c2d9e2b8b17ae17e14d1c"
MODEL_SHA256[ultra_real_krea2_v2.safetensors]="233a8b1df4b3387f9f2bedaa2099d0e14cc946d1105f732de2a8600310b86f07"
MODEL_SHA256[wan_2.1_vae.safetensors]="2fc39d31359a4b0a64f55876d8ff7fa8d780956ae2cb13463b0223e15148976b"

# WARNING: CivitAI HMBreasts_krea2_epoch12.safetensors: upstream lookup failed (<urlopen error Tunnel connection failed: 403 Forbidden>)
# WARNING: CivitAI kodak.safetensors: upstream lookup failed (<urlopen error Tunnel connection failed: 403 Forbidden>)
# WARNING: CivitAI ultra_real_krea2_v2.safetensors: upstream lookup failed (<urlopen error Tunnel connection failed: 403 Forbidden>)
# WARNING: CivitAI realistic_custom_face_krea2.safetensors: upstream lookup failed (<urlopen error Tunnel connection failed: 403 Forbidden>)
# WARNING: CivitAI krea2_raw_to_turbo_r256_comfy.safetensors: upstream lookup failed (<urlopen error Tunnel connection failed: 403 Forbidden>)
# WARNING: CivitAI snofs_krea_v1_5.safetensors: upstream lookup failed (<urlopen error Tunnel connection failed: 403 Forbidden>)
