#!/bin/bash
# check_registry.sh - CI check for registry.sh, lock.sh and the boot scripts (run by
# .github/workflows/registry-check.yml; runs locally too: bash .github/scripts/check_registry.sh).
#   1. bash -n on registry.sh, lock.sh and every live script
#   2. registry.sh sources cleanly and declares its arrays
#   3. every HF_MODELS / CIVITAI_LORAS / CUSTOM_NODES key a live script uses exists in registry.sh
#   4. every lock.sh key exists in registry.sh; every lock value has the right shape
#   5. (ONLINE=1, default in CI) every HF file a live script downloads resolves through the HF API (at the
#      locked revision when there is one; its LFS sha256 must equal the lock's), every CivitAI version
#      exists (and its SHA256 equals the lock's when CivitAI publishes one), every locked node commit exists.
# Reads no secrets. Exit 1 on any failure.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0; bad() { echo "FAIL: $*"; fail=1; }
LIVE="scripts/krea2v2.sh scripts/krea2v2-seedvr2.sh scripts/krea2raw-seedvr2.sh scripts/seedvr.sh scripts/qwenimage21edit.sh scripts/h3.sh"

for f in registry.sh lock.sh $LIVE; do
  [ -f "$f" ] || { [ "$f" = lock.sh ] && continue; bad "$f missing"; continue; }
  bash -n "$f" || bad "bash -n $f"
done

# shellcheck source=/dev/null
( source registry.sh && declare -p CUSTOM_NODES HF_MODELS CIVITAI_LORAS >/dev/null ) || bad "registry.sh does not source or lacks an array"
source registry.sh
if [ -f lock.sh ]; then source lock.sh; else declare -A NODE_LOCK=() HF_REVISION=() MODEL_SHA256=(); fi

for s in $LIVE; do
  [ -f "$s" ] || continue
  for k in $(grep -oE '\$\{HF_MODELS\[[^]]+\]\}' "$s" | sed -E 's/.*\[([^]]+)\].*/\1/' | sort -u); do
    [ -n "${HF_MODELS[$k]+x}" ] || bad "$s uses HF_MODELS[$k], not in registry.sh"
  done
  for k in $(grep -oE '\$\{CUSTOM_NODES\[[^]]+\]\}' "$s" | sed -E 's/.*\[([^]]+)\].*/\1/' | sort -u); do
    [ -n "${CUSTOM_NODES[$k]+x}" ] || bad "$s uses CUSTOM_NODES[$k], not in registry.sh"
  done
  q="$(python3 -c 'import re,sys; m=re.search(r"CIVITAI_QUEUE=\((.*?)\)", open(sys.argv[1]).read(), re.S); print(" ".join(re.findall(r"\"([^\"]+)\"", m.group(1))) if m else "")' "$s")"
  for k in $q; do [ -n "${CIVITAI_LORAS[$k]+x}" ] || bad "$s queues CivitAI $k, not in registry.sh"; done
done

for k in "${!NODE_LOCK[@]}"; do
  [ -n "${CUSTOM_NODES[$k]+x}" ] || bad "lock NODE_LOCK[$k] has no CUSTOM_NODES entry"
  [[ "${NODE_LOCK[$k]}" =~ ^[0-9a-f]{40}$ ]] || bad "lock NODE_LOCK[$k] is not a 40-hex commit"
done
for k in "${!HF_REVISION[@]}"; do
  [ -n "${HF_MODELS[$k]+x}" ] || bad "lock HF_REVISION[$k] has no HF_MODELS entry"
  [[ "${HF_REVISION[$k]}" =~ ^[0-9a-f]{40}$ ]] || bad "lock HF_REVISION[$k] is not a 40-hex revision"
done
for k in "${!MODEL_SHA256[@]}"; do
  [ -n "${HF_MODELS[$k]+x}${CIVITAI_LORAS[$k]+x}" ] || bad "lock MODEL_SHA256[$k] has no registry entry"
  [[ "${MODEL_SHA256[$k]}" =~ ^[0-9a-f]{64}$ ]] || bad "lock MODEL_SHA256[$k] is not a sha256"
done

if [ "${ONLINE:-1}" = "1" ]; then
  UA="Mozilla/5.0"
  used_hf="$(for s in $LIVE; do [ -f "$s" ] && grep -oE '\$\{HF_MODELS\[[^]]+\]\}' "$s"; done | sed -E 's/.*\[([^]]+)\].*/\1/' | sort -u)"
  for k in $used_hf; do
    url="${HF_MODELS[$k]}"
    repo="$(sed -E 's#https://huggingface.co/([^/]+/[^/]+)/resolve/.*#\1#' <<<"$url")"
    path="$(sed -E 's#https://huggingface.co/[^/]+/[^/]+/resolve/[^/]+/##' <<<"$url")"
    rev="${HF_REVISION[$k]:-main}"
    info="$(curl -fsSL -A "$UA" "https://huggingface.co/api/models/$repo/revision/$rev")" || { bad "HF $k: $repo@$rev not reachable"; continue; }
    canon="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$info")"
    lfs="$(curl -fsSL -A "$UA" -X POST "https://huggingface.co/api/models/$canon/paths-info/$rev" --data-urlencode "paths=$path" \
           | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d[0].get("lfs") or {}).get("oid","") if d else "MISSING")')" \
      || { bad "HF $k: paths-info failed"; continue; }
    [ "$lfs" = "MISSING" ] && { bad "HF $k: $path not in $canon@$rev"; continue; }
    want="${MODEL_SHA256[$k]:-}"
    if [ -n "$want" ] && [ -n "$lfs" ] && [ "$want" != "$lfs" ]; then bad "HF $k: sha256 at $rev is $lfs, lock says $want"; fi
    echo "ok HF $k"
  done
  for k in "${!CIVITAI_LORAS[@]}"; do
    vid="$(grep -oE '/models/[0-9]+' <<<"${CIVITAI_LORAS[$k]}" | grep -oE '[0-9]+')"
    j="$(curl -fsSL -A "$UA" "https://civitai.com/api/v1/model-versions/$vid")" || { bad "CivitAI $k: version $vid not reachable"; continue; }
    want="${MODEL_SHA256[$k]:-}"
    if [ -n "$want" ]; then
      fid="$(grep -oE 'fileId=[0-9]+' <<<"${CIVITAI_LORAS[$k]}" | cut -d= -f2)"
      got="$(FID="$fid" python3 -c 'import json,os,sys; d=json.load(sys.stdin); fs=[f for f in d.get("files",[]) if str(f.get("id"))==os.environ["FID"]] or d.get("files",[])[:1]; print(((fs[0].get("hashes") or {}).get("SHA256","") if fs else "").lower())' <<<"$j")"
      if [ -n "$got" ] && [ "$got" != "$want" ]; then bad "CivitAI $k: SHA256 $got, lock says $want"; fi
    fi
    echo "ok CivitAI $k"
  done
  for k in "${!NODE_LOCK[@]}"; do
    repo="$(sed -E 's#https://github.com/##; s#\.git$##' <<<"${CUSTOM_NODES[$k]}")"
    code="$(curl -s -o /dev/null -w '%{http_code}' -A "$UA" ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
            "https://api.github.com/repos/$repo/commits/${NODE_LOCK[$k]}")"
    [ "$code" = "200" ] || bad "node $k: commit ${NODE_LOCK[$k]} not found in $repo (HTTP $code)"
  done
fi

[ "$fail" = 0 ] && echo "check_registry: all checks passed" || echo "check_registry: FAILED"
exit "$fail"
