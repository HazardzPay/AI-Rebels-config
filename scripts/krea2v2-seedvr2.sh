#!/bin/bash
# krea2v2-seedvr2.sh
# Combined image-gen + upscale pod: krea2v2.sh spine with the SeedVR2 half grafted in.
# Derived from scripts/krea2v2.sh (helpers, hardening, node set) + scripts/seedvr2.sh (node + models).
#
# v3 - boot stall visibility + download throughput (2026-10-23)
# Three pods in a row sat 10+ minutes short of DOWNLOAD COMPLETE with a log that looked
# identical to a healthy one. Two problems: nothing showed whether bytes were moving, and
# the download scheduler started two files and waited for BOTH, so one slow file idled the
# other slot for up to a full timeout. v3 changes:
#   - heartbeat every HEARTBEAT_SECS -> /workspace/BOOT_STATUS (one-command check) + the log
#   - idle detector: STALL_IDLE_TICKS ticks with <2MB received on the network WHILE a
#     download is in flight prints a NO PROGRESS banner (network, not disk: Xet buffers in
#     RAM and writes late, so disk growth reads a healthy download as stalled); STALL_AUTOKILL=1 then kills the stalled transfer
#     and the retry loop resumes it (hf resumes from partial; curl resumes with -C -)
#   - /workspace/dlstatus.sh written by this script: status, ledger, in-flight, partials, log
#   - shared download queue (flock'd counter) replaces the batch barrier: a worker pulls the
#     next item the moment it frees up, so no item ever waits on an unrelated slow one
#   - downloads start BEFORE the node clones and run alongside them; a clone stall no longer
#     freezes downloads
#   - HF_TOKEN passthrough, Xet stream count capped, Xet cache pinned under .boot-state,
#     progress bars off (their \r lines collapse under tee into one static line)
#   - per-phase timings printed at the end and on any failure
#   - CivitAI: per-transfer stall killer (--speed-limit), .part file + resume, so a killed or
#     interrupted transfer is never mistaken for a finished file
set -euo pipefail

LOG_FILE="/workspace/krea2v2-seedvr2-background.log"
# If the log file can't be created (e.g. /workspace not mounted yet), fall back
# to /dev/null so tee never kills the watcher.
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"

(
  set -euo pipefail

  COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  PROMPTBATCHER_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-Simple-Prompt-Batcher"
  RGTHREE_NODE_DIR="$CUSTOM_NODES_DIR/rgthree-comfy"
  RES4LYF_NODE_DIR="$CUSTOM_NODES_DIR/RES4LYF"
  KREA2EDIT_NODE_DIR="$CUSTOM_NODES_DIR/comfyui-krea2edit"
  LANPAINT_NODE_DIR="$CUSTOM_NODES_DIR/LanPaint"
  SEEDVR2_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-SeedVR2_VideoUpscaler"
  KJNODES_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-KJNodes"
  KREAREASON_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-KreaReason"
  KREA2NAG_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-Krea2-NAG"
  NEGPIP_NODE_DIR="$CUSTOM_NODES_DIR/ComfyUI-krea2-negpip"
  TWOSTAGE_NODE_DIR="$CUSTOM_NODES_DIR/Krea-2-Two-Stage-Sampler"
  MODELS_DIR="$COMFY_ROOT/models"
  SEEDVR2_MODELS_DIR="$COMFY_ROOT/models/SEEDVR2"
  TMP_DIR="/workspace/hf-downloads"
  HEALTH_URL="http://127.0.0.1:8188"

  # --- telemetry paths ---
  # Deliberately NOT under TMP_DIR, which is rm -rf'd at the end of the run: dlstatus.sh
  # has to keep working after the boot completes.
  STATE_DIR="/workspace/.boot-state"
  INFLIGHT_DIR="$STATE_DIR/inflight"
  POOL_STATE="$STATE_DIR/pool-state"
  POOL_RESULTS="$STATE_DIR/pool-results"
  PHASE_TIMES="$STATE_DIR/phase-times"
  QUEUE_NEXT="$STATE_DIR/queue-next"
  QUEUE_LOCK="$STATE_DIR/queue.lock"
  CLONE_NOW="$STATE_DIR/clone-now"
  BOOT_STATUS_FILE="/workspace/BOOT_STATUS"
  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR" "$INFLIGHT_DIR"
  : > "$POOL_STATE"
  : > "$POOL_RESULTS"
  : > "$PHASE_TIMES"
  echo 0 > "$QUEUE_NEXT"
  REGISTRY_URL="https://raw.githubusercontent.com/hazardzpay/AI-Rebels-config/main/registry.sh"
  REGISTRY_FILE="$STATE_DIR/registry.sh"

  # Keep Xet's high-performance mode, but bound its buffers and run only two model-file
  # downloads at a time. High-performance Xet otherwise permits up to 64GB of buffering per
  # hf process, which can OOM pods with a 28GB RAM limit.
  export HF_XET_HIGH_PERFORMANCE=1
  export HF_XET_RECONSTRUCTION_DOWNLOAD_BUFFER_SIZE=4gb
  export HF_XET_RECONSTRUCTION_DOWNLOAD_BUFFER_PERFILE_SIZE=2gb
  export HF_XET_RECONSTRUCTION_DOWNLOAD_BUFFER_LIMIT=4gb
  export HF_HUB_DOWNLOAD_TIMEOUT=60
  MAX_PARALLEL_DOWNLOADS=2
  export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
  export PYTORCH_ALLOC_CONF=expandable_segments:True
  # v3 additions. HF_HUB_ENABLE_HF_TRANSFER is gone: inert on hub 1.x, which takes the Xet
  # path regardless.
  export HF_XET_NUM_CONCURRENT_RANGE_GETS=8   # default 64-128 sockets/process; one stalled stream among that many is invisible
  export HF_XET_CACHE="$STATE_DIR/xet-cache"  # kept out of ~/.cache and removed at the end of the run
  export HF_HUB_DISABLE_PROGRESS_BARS=1       # \r bars collapse under tee into one static line
  # Anonymous HF throttling shows up as a silent sleep - the likeliest cause of the old
  # 0-byte freezes. The hf CLI reads HF_TOKEN from the environment.
  if [ -z "${HF_TOKEN:-}" ] && [ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]; then
    export HF_TOKEN="$HUGGING_FACE_HUB_TOKEN"
  fi
  # Overridable from the pod environment, e.g. STALL_AUTOKILL=0 to watch only.
  HEARTBEAT_SECS="${HEARTBEAT_SECS:-30}"
  STALL_IDLE_TICKS="${STALL_IDLE_TICKS:-3}"   # 3 x 30s = 90s with no byte movement
  STALL_AUTOKILL="${STALL_AUTOKILL:-1}"
  STALL_MIN_BYTES=$((2 * 1024 * 1024))

  # Belt-and-suspenders: HF_HUB_DOWNLOAD_TIMEOUT only bounds the HTTP read timeout, not the
  # whole `hf download` process, so a stuck download could still hang the script. Same fix
  # as clone_node: wrap in `timeout --kill-after` (plain `timeout N` only sends SIGTERM at N
  # and then waits for the child - if the child ignores it, timeout blocks forever too).
  # 3 attempts: both download paths resume from partial, so a retry is cheap, not a redo.
  # 1800s, not 600s: real stalls are caught by the heartbeat in ~90s, so this cap is only a
  # backstop. At 600s a healthy 16GB file on a host doing ~27MB/s per file would be cut off
  # mid-transfer and burn an attempt for nothing.
  DOWNLOAD_TIMEOUT=1800
  DOWNLOAD_KILL_GRACE=30
  if command -v timeout >/dev/null 2>&1; then
    DL_TIMEOUT_CMD="timeout --kill-after=$DOWNLOAD_KILL_GRACE $DOWNLOAD_TIMEOUT"
    DOWNLOAD_LIMIT_DESC="${DOWNLOAD_TIMEOUT}s timeout, SIGKILL at $((DOWNLOAD_TIMEOUT + DOWNLOAD_KILL_GRACE))s"
  else
    DL_TIMEOUT_CMD=""
    DOWNLOAD_LIMIT_DESC="NO TIMEOUT - 'timeout' not found on PATH"
  fi

  # --- helpers ---
  fmt_dur() { printf '%dm%02ds' $(( $1 / 60 )) $(( $1 % 60 )); }
  fmt_rate() {
    if [ "$1" -ge 1048576 ]; then
      awk -v b="$1" 'BEGIN { printf "%.1f MB/s", b / 1048576 }'
    else
      printf '%d KB/s' $(( $1 / 1024 ))
    fi
  }
  # Progress = bytes received on the pod's network interfaces, NOT disk growth. Measured on
  # a live pod (2026-10-23): a healthy Xet download ran at 51-58 MB/s on the wire while the
  # file on disk stayed flat at 104MB and hf's RAM climbed ~57MB/s - Xet buffers in memory
  # and writes late. A disk-based detector read that as a stall and killed every attempt.
  # The container has its own network namespace, so this counts only this pod's traffic.
  # BOOT_NET_DEV is overridable for testing only.
  BOOT_NET_DEV="${BOOT_NET_DEV:-/proc/net/dev}"
  bytes_now() {
    awk 'NR > 2 && $0 !~ /^ *lo:/ { sub(/^[^:]*:/, ""); s += $1 } END { print s + 0 }' "$BOOT_NET_DEV" 2>/dev/null || echo 0
  }
  pool_log() { echo "[$(date +%H:%M:%S)] $*"; }
  phase() {
    printf '%s\t%s\n' "$SECONDS" "$1" >> "$PHASE_TIMES"
    echo "$1" > "$STATE_DIR/phase"
    echo "======== phase: $1 at $(date +%H:%M:%S), elapsed $(fmt_dur "$SECONDS") ========"
  }
  print_phase_times() {
    echo "---- phase timings ----"
    awk -F'\t' -v end="$SECONDS" '
      { t[NR] = $1; n[NR] = $2 }
      END {
        for (i = 1; i <= NR; i++) {
          stop = (i < NR) ? t[i + 1] : end
          printf "  %-28s %4dm%02ds\n", n[i], int((stop - t[i]) / 60), (stop - t[i]) % 60
        }
        printf "  %-28s %4dm%02ds\n", "TOTAL", int(end / 60), end % 60
      }' "$PHASE_TIMES"
  }

  # Kill every running transfer. Workers are background subshells; killing a worker does
  # not kill the hf/curl it spawned, so the transfers are matched by command line too.
  kill_transfers() {
    pkill -f 'hf download' 2>/dev/null || true
    pkill -f 'civitai.com' 2>/dev/null || true
  }

  POOL_PIDS=()
  HEARTBEAT_PID=""

  die() {
    echo "======================================================="
    echo "SETUP FAILED: $1"
    echo "Nothing further will run. Redeploy the pod."
    echo "Failed after $((SECONDS / 60))m$((SECONDS % 60))s."
    echo "======================================================="
    echo "FAILED: $1 (after $(fmt_dur "$SECONDS"))" > "$BOOT_STATUS_FILE"
    local pid
    for pid in "${POOL_PIDS[@]}" $HEARTBEAT_PID; do
      kill "$pid" 2>/dev/null || true
    done
    kill_transfers
    print_phase_times
    exit 1
  }

  # The old `source <(curl ...)` swallowed a failed fetch: the script carried on with empty
  # arrays and died later on a cryptic arithmetic error. Fetch to a file, retry, fail loudly.
  if ! curl -fsSL --retry 3 --retry-delay 5 "$REGISTRY_URL" -o "$REGISTRY_FILE" \
     || ! grep -q 'declare -A HF_MODELS' "$REGISTRY_FILE"; then
    die "could not fetch registry.sh from $REGISTRY_URL"
  fi
  # shellcheck source=/dev/null
  source "$REGISTRY_FILE"

  # --- /workspace/dlstatus.sh: one command for the full picture, works after the boot ---
  cat > /workspace/dlstatus.sh <<'DLSTATUS'
#!/bin/bash
S=/workspace/.boot-state
echo "==== BOOT_STATUS ===="
cat /workspace/BOOT_STATUS 2>/dev/null || echo "(no BOOT_STATUS yet - still in the early waits for ComfyUI)"
echo
echo "==== download ledger ===="
if [ -f "$S/pool-state" ]; then
  awk '{ c[$2]++ } END { printf "queued %d  started %d  ok %d  fail %d\n", c["QUEUED"]+0, c["START"]+0, c["OK"]+0, c["FAIL"]+0 }' "$S/pool-state"
  grep ' FAIL ' "$S/pool-state" 2>/dev/null || true
fi
echo
echo "==== in flight ===="
found=0
for f in "$S"/inflight/*; do
  [ -e "$f" ] || continue
  echo "  worker $(basename "$f"): $(cat "$f")"; found=1
done
[ "$found" -eq 1 ] || echo "  (nothing)"
[ -s "$S/clone-now" ] && echo "  cloning: $(cat "$S/clone-now")"
echo
echo "==== partial files (size on disk; Xet buffers in RAM, so this lags the network) ===="
{ find /workspace/hf-downloads -name '*.incomplete' -exec du -h {} + 2>/dev/null \
    | sed -E 's#\t/workspace/hf-downloads/([^/]+)/.*#\t\1#'
  find /workspace/runpod-slim/ComfyUI/models -name '*.part' -exec du -h {} + 2>/dev/null \
    | sed -E 's#\t.*/([^/]+)\.part$#\t\1 (civitai)#'
} | sort -rh | sed 's/^/  /'
echo
echo "==== log tail ===="
tail -15 /workspace/krea2v2-seedvr2-background.log 2>/dev/null
DLSTATUS
  chmod +x /workspace/dlstatus.sh

  # Rewrites BOOT_STATUS every tick (never appends). Idle only counts while something is in
  # flight: the clone, pip and restart phases legitimately move no download bytes.
  # Runs in its own background subshell with errexit off: a heartbeat killed by one failed
  # command would leave BOOT_STATUS frozen, which is the exact symptom it exists to rule out.
  heartbeat() {
    set +e +o pipefail
    local prev now delta rate idle=0 done_n fail_n inflight clone ph line
    prev="$(bytes_now)"
    while true; do
      sleep "$HEARTBEAT_SECS"
      now="$(bytes_now)"
      delta=$(( now - prev ))
      [ "$delta" -lt 0 ] && delta=0
      prev="$now"
      rate=$(( delta / HEARTBEAT_SECS ))
      done_n="$(grep -c '^OK' "$POOL_RESULTS" 2>/dev/null || true)"
      fail_n="$(grep -c '^FAIL' "$POOL_RESULTS" 2>/dev/null || true)"
      inflight="$(cat "$INFLIGHT_DIR"/* 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)"
      clone="$(cat "$CLONE_NOW" 2>/dev/null || true)"
      ph="$(cat "$STATE_DIR/phase" 2>/dev/null || echo '?')"
      if [ -n "$inflight" ] && [ "$delta" -lt "$STALL_MIN_BYTES" ]; then
        idle=$(( idle + 1 ))
      else
        idle=0
      fi
      line="[hb $(date +%H:%M:%S)] phase=$ph elapsed=$(fmt_dur "$SECONDS") done=${done_n:-0}/${#POOL_ITEMS[@]} fail=${fail_n:-0} rate=$(fmt_rate "$rate") idle=${idle}x${HEARTBEAT_SECS}s in-flight=[$inflight]${clone:+ cloning=$clone}"
      echo "$line" > "$BOOT_STATUS_FILE"
      echo "$line"
      if [ "$idle" -ge "$STALL_IDLE_TICKS" ]; then
        echo "*** NO PROGRESS for $(( idle * HEARTBEAT_SECS ))s *** in-flight: [$inflight]"
        tail -3 "$POOL_STATE" 2>/dev/null || true
        if [ "$STALL_AUTOKILL" = "1" ]; then
          echo "*** STALL_AUTOKILL=1: killing stalled transfer(s); the retry loop will resume them ***"
          kill_transfers
        else
          echo "*** STALL_AUTOKILL=0: watching only ***"
        fi
        idle=0
      fi
    done
  }

  # Node requirements install in parallel with the downloads, and one of them upgrades
  # huggingface_hub: pip deletes and rewrites the `hf` launcher, and a worker that starts
  # a download in that window gets "failed to run command 'hf'" (exit 127) three times in
  # a row at 0s and kills the boot. Wait for a working hf before each attempt instead.
  wait_for_hf() {
    local i
    for i in $(seq 1 60); do
      hf --version >/dev/null 2>&1 && return 0
      sleep 2
    done
    return 1
  }

  download_hf_file() {
    local url="$1"
    local dest_dir="$2"
    local repo repo_path filename dl_tmp attempt rc start
    repo="$(echo "$url" | sed -E 's#https://huggingface.co/([^/]+/[^/]+)/.*#\1#')"
    repo_path="$(echo "$url" | sed -E 's#https://huggingface.co/[^/]+/[^/]+/resolve/[^/]+/##')"
    filename="$(basename "$url")"
    if [ -s "$dest_dir/$filename" ]; then
      echo "$filename already present, skipping."
      return 0
    fi
    dl_tmp="$TMP_DIR/$filename"
    mkdir -p "$dest_dir" "$dl_tmp"
    for attempt in 1 2 3; do
      echo "Downloading: $url (attempt $attempt/3, $DOWNLOAD_LIMIT_DESC)"
      rc=0
      wait_for_hf || echo "hf CLI still not runnable after 120s, trying anyway."
      start=$SECONDS
      $DL_TIMEOUT_CMD hf download "$repo" "$repo_path" --local-dir "$dl_tmp" || rc=$?
      if [ "$rc" -eq 0 ]; then
        mv -f "$dl_tmp/$repo_path" "$dest_dir/$filename"
        echo "Finished: $filename in $((SECONDS - start))s (attempt $attempt/3)."
        return 0
      fi
      case "$rc" in
        124) echo "Download of $filename TIMED OUT after $((SECONDS - start))s (attempt $attempt/3)." ;;
        137) echo "Download of $filename ignored SIGTERM, SIGKILLed after $((SECONDS - start))s (attempt $attempt/3)." ;;
        127) echo "Download of $filename: hf launcher missing (pip upgrading huggingface_hub?), waiting (attempt $attempt/3)."; sleep 10 ;;
        *)   echo "Download of $filename FAILED, hf exit $rc after $((SECONDS - start))s (attempt $attempt/3)." ;;
      esac
    done
    echo "Download of $filename failed after 3 attempts."
    return 1
  }

  # CivitAI serves via its own API endpoint, so `hf download` can't read these URLs.
  # curl -L follows the redirect to the actual blob; CIVITAI_TOKEN is optional but avoids
  # anonymous rate-limiting. Writes to .part and renames on success, so an interrupted
  # transfer is never mistaken for a finished file; -C - resumes the .part on retry.
  # --speed-limit/--speed-time is curl's own stall killer (<2KB/s for 60s), no daemon needed.
  download_civitai_file() {
    local filename="$1" url="$2" dest_dir="$3"
    local attempt rc
    if [ -s "$dest_dir/$filename" ]; then
      echo "$filename already present, skipping."
      return 0
    fi
    mkdir -p "$dest_dir"
    for attempt in 1 2 3; do
      echo "Downloading (civitai): $filename (attempt $attempt/3, $DOWNLOAD_LIMIT_DESC)"
      rc=0
      $DL_TIMEOUT_CMD curl -fL --retry 3 --retry-delay 5 -C - \
        --speed-limit 2048 --speed-time 60 \
        ${CIVITAI_TOKEN:+-H "Authorization: Bearer $CIVITAI_TOKEN"} \
        "$url" -o "$dest_dir/$filename.part" || rc=$?
      if [ "$rc" -eq 0 ]; then
        mv -f "$dest_dir/$filename.part" "$dest_dir/$filename"
        echo "Finished: $filename (attempt $attempt/3)."
        return 0
      fi
      echo "Download of $filename FAILED, curl exit $rc (attempt $attempt/3)."
    done
    return 1
  }

  # Hands out queue indexes under a lock. Each worker pulls the next item the moment it
  # frees up, so a slow item only ever occupies its own worker.
  next_queue_index() {
    (
      flock 9
      local n
      n="$(cat "$QUEUE_NEXT")"
      echo $(( n + 1 )) > "$QUEUE_NEXT"
      echo "$n"
    ) 9>"$QUEUE_LOCK"
  }

  download_worker() {
    local worker="$1" idx kind key dest label start ok
    while true; do
      # Fail fast: once any item has failed for good the pod needs a redeploy, so take no
      # new items (in-flight ones finish; the main flow dies after the clones).
      if [ -s "$POOL_RESULTS" ] && grep -q '^FAIL' "$POOL_RESULTS"; then
        pool_log "worker $worker: stopping - an earlier download failed"
        break
      fi
      idx="$(next_queue_index)"
      [ "$idx" -lt "${#POOL_ITEMS[@]}" ] || break
      IFS='|' read -r kind key dest <<< "${POOL_ITEMS[$idx]}"
      label="$(basename "$key")"
      echo "$label" > "$INFLIGHT_DIR/$worker"
      echo "$(date +%H:%M:%S) START $label w$worker" >> "$POOL_STATE"
      pool_log "worker $worker: start $label"
      start=$SECONDS
      ok=0
      if [ "$kind" = "hf" ]; then
        download_hf_file "$key" "$dest" && ok=1
      else
        download_civitai_file "$key" "${CIVITAI_LORAS[$key]}" "$dest" && ok=1
      fi
      rm -f "$INFLIGHT_DIR/$worker"
      if [ "$ok" -eq 1 ]; then
        echo "OK $label" >> "$POOL_RESULTS"
        echo "$(date +%H:%M:%S) OK $label $((SECONDS - start))s" >> "$POOL_STATE"
        pool_log "worker $worker: ok $label in $(fmt_dur $((SECONDS - start)))"
      else
        echo "FAIL $label" >> "$POOL_RESULTS"
        echo "$(date +%H:%M:%S) FAIL $label $((SECONDS - start))s" >> "$POOL_STATE"
        pool_log "worker $worker: FAIL $label after $(fmt_dur $((SECONDS - start)))"
      fi
    done
  }

  echo "-------------------------------------------------------"
  echo "BACKGROUND WATCHER STARTED: KREA2 V2 + SEEDVR2 CONFIG (v3.2)"
  echo "-------------------------------------------------------"
  echo "booting" > "$BOOT_STATUS_FILE"

  phase "wait-comfyui"
  echo "Waiting for ComfyUI root to exist..."
  for i in $(seq 1 300); do
    if [ -d "$COMFY_ROOT" ]; then break; fi
    sleep 2
  done

  if [ ! -d "$COMFY_ROOT" ]; then
    die "timed out waiting for ComfyUI root: $COMFY_ROOT"
  fi

  echo "Waiting for ComfyUI server on 8188..."
  for i in $(seq 1 600); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then break; fi
    sleep 2
  done

  if ! curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    die "timed out waiting for ComfyUI server: $HEALTH_URL"
  fi

  echo "ComfyUI is live at $(git -C "$COMFY_ROOT" describe --tags 2>/dev/null || echo unknown)."
  echo "No core update needed (image bakes a current ComfyUI). Installing custom node(s) and downloading models..."

  # RunPod runs ComfyUI from system python on the cuda12.8 image and from .venv-cu128
  # on older ones. Follow whichever interpreter is actually serving 8188 so node
  # requirements and the restart at the end land in the same environment.
  COMFY_PY="$(readlink -f "/proc/$(pgrep -f 'main\.py' | head -1)/exe" 2>/dev/null || true)"
  if [ ! -x "$COMFY_PY" ]; then
    COMFY_PY="$COMFY_ROOT/.venv-cu128/bin/python"
  fi
  echo "Using interpreter: $COMFY_PY"

  # Must precede the download workers - they need the hf CLI.
  if ! command -v hf >/dev/null 2>&1; then
    "$COMFY_PY" -m pip install -q -U "huggingface_hub"
  fi

  # A pod missing a node is unusable and has to be redeployed, so fail fast and loud
  # rather than spending 20 more minutes downloading models nobody will use.
  # CLONE_TIMEOUT caps the stall: a bad host once hung a clone for 12 minutes before
  # erroring out. HTTP/1.1 avoids the HTTP/2 "curl 92 stream not closed cleanly" failure.
  #
  # Deliberately NOT a shallow clone. --depth 1 saved nothing here (RES4LYF is ~250MB
  # packed and its bulk is blobs at HEAD, not history) while forcing the server to build
  # a custom pack without reachability bitmaps - a long pre-transfer stall that GitHub
  # documents as more expensive than a full fetch, and the likely trigger for the
  # "fetch-pack: unexpected disconnect while reading sideband packet" on attempt 1.
  # --no-tags: nothing here consumes tags; it trims the ref advertisement for free.
  CLONE_TIMEOUT=1200
  CLONE_KILL_GRACE=30
  if command -v timeout >/dev/null 2>&1; then
    # --kill-after is not optional. Plain `timeout N` only sends SIGTERM at N and then
    # blocks waiting for the child; if the child does not die from SIGTERM it waits
    # forever, so it caps nothing. Measured: `timeout 3` against a SIGTERM-ignoring child
    # returned after 60s, not 3s. That is what left a res4lyf clone silent for 12+ minutes
    # past a 240s "timeout". --kill-after escalates to SIGKILL so the bound is real.
    TIMEOUT_CMD="timeout --kill-after=$CLONE_KILL_GRACE $CLONE_TIMEOUT"
    CLONE_LIMIT_DESC="${CLONE_TIMEOUT}s timeout, SIGKILL at $((CLONE_TIMEOUT + CLONE_KILL_GRACE))s"
  else
    # Never claim a timeout we are not applying - the old code printed "240s timeout"
    # even in this branch, which made an uncapped hang impossible to diagnose from the log.
    TIMEOUT_CMD=""
    CLONE_LIMIT_DESC="NO TIMEOUT - 'timeout' not found on PATH"
  fi

  # Trailing args (if any) are top-level directory names to exclude via a partial
  # clone + sparse-checkout, instead of a normal full clone. Use this for repos that
  # bundle large example/doc assets nothing at runtime imports - e.g. RES4LYF is
  # 216MB, of which 212MB (98%) is example_workflows/ and workflows/ screenshots;
  # neither __init__.py nor web/js references either dir. --filter=blob:none means
  # git never transfers blobs for excluded paths at all (this is not the --depth 1
  # shallow clone already ruled out above - that still forces a full custom pack on
  # GitHub's side; blob filtering shrinks the pack itself). Measured against the real
  # repo: 2.9s and 5.6MB instead of the multi-minute stall that was timing out here.
  clone_node() {
    local name="$1" url="$2" dest="$3"; shift 3
    local sparse_exclude=("$@")
    if [ -d "$dest" ]; then
      echo "$name already present, skipping clone."
      return 0
    fi
    echo "$name" > "$CLONE_NOW"
    local attempt rc start sparse_pattern p
    for attempt in 1 2; do
      if [ "${#sparse_exclude[@]}" -gt 0 ]; then
        echo "Cloning $name sparse, excluding [${sparse_exclude[*]}] (attempt $attempt/2, $CLONE_LIMIT_DESC)..."
      else
        echo "Cloning $name (attempt $attempt/2, $CLONE_LIMIT_DESC)..."
      fi
      start=$SECONDS
      rc=0
      if [ "${#sparse_exclude[@]}" -gt 0 ]; then
        sparse_pattern="/*"
        for p in "${sparse_exclude[@]}"; do sparse_pattern="$sparse_pattern
!/$p/"; done
        # Whole clone+sparse-checkout+checkout sequence runs under one timeout, same
        # "never hang forever" guarantee as the plain-clone path below.
        $TIMEOUT_CMD bash -c '
          set -e
          git -c http.version=HTTP/1.1 clone --quiet --no-tags --filter=blob:none --no-checkout --sparse "$1" "$2"
          git -C "$2" sparse-checkout init --no-cone
          printf "%s\n" "$3" > "$2/.git/info/sparse-checkout"
          git -C "$2" checkout --quiet
        ' _ "$url" "$dest" "$sparse_pattern" || rc=$?
      else
        $TIMEOUT_CMD git -c http.version=HTTP/1.1 clone --quiet --no-tags "$url" "$dest" || rc=$?
      fi
      if [ "$rc" -eq 0 ]; then
        echo "Cloned $name in $((SECONDS - start))s ($(du -sh "$dest" 2>/dev/null | cut -f1))."
        : > "$CLONE_NOW"
        return 0
      fi
      # Say which failure this was. The old code printed one message for every case, so a
      # timeout and a git error were indistinguishable in the log.
      case "$rc" in
        124) echo "Clone of $name TIMED OUT after $((SECONDS - start))s (attempt $attempt/2)." ;;
        137) echo "Clone of $name ignored SIGTERM, SIGKILLed after $((SECONDS - start))s (attempt $attempt/2)." ;;
        *)   echo "Clone of $name FAILED, git exit $rc after $((SECONDS - start))s (attempt $attempt/2)." ;;
      esac
      rm -rf "$dest"
    done
    die "could not clone $name after 2 attempts"
  }

  install_node_reqs() {
    local name="$1" dir="$2"
    if [ -f "$dir/requirements.txt" ]; then
      echo "$name" > "$CLONE_NOW"
      "$COMFY_PY" -m pip install -q -r "$dir/requirements.txt"
      echo "$name requirements installed."
      : > "$CLONE_NOW"
    fi
  }

  # Newer ComfyUI 403s cross-site browser requests (Sec-Fetch-Site check),
  # which breaks access through the RunPod proxy. --enable-cors-header disables that middleware.
  ARGS_FILE="/workspace/runpod-slim/comfyui_args.txt"
  if [ -f "$ARGS_FILE" ] && ! grep -q "enable-cors-header" "$ARGS_FILE"; then
    echo "--enable-cors-header" >> "$ARGS_FILE"
  fi

  # --- download queue ---
  # Heaviest first, so the two workers open on the biggest transfers and the small files
  # fill in around them at the tail.
  ALL_DOWNLOAD_QUEUE=(
    "${HF_MODELS[seedvr2_ema_7b_fp16.safetensors]}|$SEEDVR2_MODELS_DIR"
    "${HF_MODELS[krea2_raw_fp8_scaled.safetensors]}|$MODELS_DIR/diffusion_models"
    "${HF_MODELS[krea2_turbo_fp8_scaled.safetensors]}|$MODELS_DIR/diffusion_models"
    "${HF_MODELS[museByStableYogi_v35Int8Extended.safetensors]}|$MODELS_DIR/diffusion_models"
    "${HF_MODELS[qwen3vl_4b_fp8_scaled.safetensors]}|$MODELS_DIR/text_encoders"
    "${HF_MODELS[realism_engine_krea2_v2.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[snofs_krea_v1_1.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[krea2_identity_edit_v1_2.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[K_excessivecum.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[snofs_krea_v1_4.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[realism_engine_krea2_v3.1.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[krea2-bloomgirls-realism-step00004000.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[RealisticSnapshotKrea2.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[famegrid_spicy_3167060.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[anal_helper_krea2_loraholic.safetensors]}|$MODELS_DIR/loras"
    "${HF_MODELS[ema_vae_fp16.safetensors]}|$SEEDVR2_MODELS_DIR"
    "${HF_MODELS[qwen_image_vae.safetensors]}|$MODELS_DIR/vae"
    "${HF_MODELS[wan_2.1_vae.safetensors]}|$MODELS_DIR/vae"
  )

  # CivitAI LoRAs - filename only; URLs come from ${CIVITAI_LORAS[filename]} in registry.sh.
  CIVITAI_QUEUE=(
    "HMBreasts_krea2_epoch12.safetensors"
    "kodak.safetensors"
    "ultra_real_krea2_v2.safetensors"
    "realistic_custom_face_krea2.safetensors"
    "krea2_raw_to_turbo_r256_comfy.safetensors"
    "snofs_krea_v1_5.safetensors"
  )

  # One flat queue, built before the heartbeat starts so its total is exact.
  POOL_ITEMS=()
  for entry in "${ALL_DOWNLOAD_QUEUE[@]}"; do
    POOL_ITEMS+=("hf|${entry%%|*}|${entry##*|}")
  done
  for fn in "${CIVITAI_QUEUE[@]}"; do
    POOL_ITEMS+=("civitai|$fn|$MODELS_DIR/loras")
  done
  for item in "${POOL_ITEMS[@]}"; do
    IFS='|' read -r _kind _key _dest <<< "$item"
    echo "$(date +%H:%M:%S) QUEUED $(basename "$_key")" >> "$POOL_STATE"
  done

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  heartbeat &
  HEARTBEAT_PID=$!

  # Downloads start BEFORE the node clones and run alongside them. Clones share nothing
  # with the transfers, so overlapping them takes clone time off the critical path, and a
  # clone stall (sesquilsr, 10+ minutes in git index-pack) can no longer freeze downloads.
  phase "downloads+clones"
  echo "Downloading ${#POOL_ITEMS[@]} files (${#ALL_DOWNLOAD_QUEUE[@]} HF, ${#CIVITAI_QUEUE[@]} CivitAI) on $MAX_PARALLEL_DOWNLOADS workers, alongside the node clones..."
  for w in $(seq 0 $((MAX_PARALLEL_DOWNLOADS - 1))); do
    download_worker "$w" &
    POOL_PIDS+=("$!")
  done

  # --- custom node installs ---
  clone_node "promptbatcher" "${CUSTOM_NODES[promptbatcher]}" "$PROMPTBATCHER_NODE_DIR"
  install_node_reqs "promptbatcher" "$PROMPTBATCHER_NODE_DIR"
  clone_node "rgthree" "${CUSTOM_NODES[rgthree]}" "$RGTHREE_NODE_DIR"
  install_node_reqs "rgthree" "$RGTHREE_NODE_DIR"
  # rgthree's remote HEAD points at refs/heads/dev, which sits at 5f940dd (2023-11-20) and
  # still carries a recursive-execution patch calling execution.recursive_output_delete_if_changed
  # - removed in ComfyUI 0.30.0. That patch sits outside the config guard, so the flag below
  # cannot reach it: the import fails and all 17 rgthree nodes vanish, Power Lora Loader among
  # them. 'main' is current and drops the patch entirely. Do NOT trust the default branch -
  # it has already flipped once between sessions. Fetch and check out main explicitly.
  git -C "$RGTHREE_NODE_DIR" fetch --quiet --no-tags origin main
  git -C "$RGTHREE_NODE_DIR" checkout --quiet -B main FETCH_HEAD
  # Belt-and-braces: inert on main, load-bearing if the checkout above ever lands on dev.
  # Set both configs - the user config may be defeated by a migration routine that
  # deletes the key on read, so the default has to carry it too.
  sed -i 's/"patch_recursive_execution": true/"patch_recursive_execution": false/' "$RGTHREE_NODE_DIR/rgthree_config.json.default"
  printf '{\n  "patch_recursive_execution": false\n}\n' > "$RGTHREE_NODE_DIR/rgthree_config.json"
  echo "rgthree: checked out main - default branch dev is stale and breaks ComfyUI 0.30.0."
  echo "rgthree at $(git -C "$RGTHREE_NODE_DIR" log -1 --format='%h %ci')"
  clone_node "res4lyf" "${CUSTOM_NODES[res4lyf]}" "$RES4LYF_NODE_DIR" "example_workflows" "workflows"
  install_node_reqs "res4lyf" "$RES4LYF_NODE_DIR"
  clone_node "krea2edit" "${CUSTOM_NODES[krea2edit]}" "$KREA2EDIT_NODE_DIR"
  install_node_reqs "krea2edit" "$KREA2EDIT_NODE_DIR"
  clone_node "lanpaint" "${CUSTOM_NODES[lanpaint]}" "$LANPAINT_NODE_DIR" "examples" "example_workflows" "tests"
  install_node_reqs "lanpaint" "$LANPAINT_NODE_DIR"
  clone_node "seedvr2" "${CUSTOM_NODES[seedvr2]}" "$SEEDVR2_NODE_DIR"
  install_node_reqs "seedvr2" "$SEEDVR2_NODE_DIR"
  clone_node "kjnodes" "${CUSTOM_NODES[kjnodes]}" "$KJNODES_NODE_DIR"
  install_node_reqs "kjnodes" "$KJNODES_NODE_DIR"
  clone_node "kreareason" "${CUSTOM_NODES[kreareason]}" "$KREAREASON_NODE_DIR"
  install_node_reqs "kreareason" "$KREAREASON_NODE_DIR"
  clone_node "krea2nag" "${CUSTOM_NODES[krea2nag]}" "$KREA2NAG_NODE_DIR"
  install_node_reqs "krea2nag" "$KREA2NAG_NODE_DIR"
  clone_node "negpip" "${CUSTOM_NODES[negpip]}" "$NEGPIP_NODE_DIR"
  install_node_reqs "negpip" "$NEGPIP_NODE_DIR"
  clone_node "twostagesampler" "${CUSTOM_NODES[twostagesampler]}" "$TWOSTAGE_NODE_DIR" "example_workflows" "images"
  install_node_reqs "twostagesampler" "$TWOSTAGE_NODE_DIR"
  # --- end custom node installs ---

  # ComfyUI 0.30.0 renamed comfy/logging.py -> comfy/internal_logging.py.
  # Flag any custom node still importing the old path so a failed import is
  # obvious in the log instead of showing up as a missing node in the UI.
  if grep -rn "comfy\.logging\|from comfy import logging" "$CUSTOM_NODES_DIR" 2>/dev/null; then
    echo "WARNING: custom node(s) above import comfy.logging, removed in ComfyUI 0.30.0."
  else
    echo "No custom node references to the removed comfy.logging module."
  fi

  phase "downloads-tail"
  echo "Node installs done. Waiting for the remaining downloads..."
  for pid in "${POOL_PIDS[@]}"; do
    wait "$pid" || true
  done
  POOL_PIDS=()
  if grep -q '^FAIL' "$POOL_RESULTS"; then
    die "download(s) failed: $(grep '^FAIL' "$POOL_RESULTS" | cut -d' ' -f2- | tr '\n' ' ')"
  fi

  rm -rf "$TMP_DIR" "$STATE_DIR/xet-cache"

  phase "restart-comfyui"
  echo "Downloads complete. Restarting ComfyUI to load custom node(s)..."
  pkill -f "main.py" || true
  sleep 3
  cd "$COMFY_ROOT" && "$COMFY_PY" main.py --listen 0.0.0.0 --port 8188 --enable-cors-header >> /proc/1/fd/1 2>> /proc/1/fd/2 &

  echo "Waiting for ComfyUI to come back online..."
  for i in $(seq 1 300); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then break; fi
    sleep 2
  done

  if ! curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    die "timed out waiting for ComfyUI to restart"
  fi

  kill "$HEARTBEAT_PID" 2>/dev/null || true
  wait "$HEARTBEAT_PID" 2>/dev/null || true
  phase "complete"
  print_phase_times
  echo "COMPLETE in $(fmt_dur "$SECONDS") - ${#POOL_ITEMS[@]} items, 0 failures" > "$BOOT_STATUS_FILE"

  echo "-------------------------------------------------------"
  echo "DOWNLOAD COMPLETE - KREA2 V2 + SEEDVR2 INSTALLED"
  echo "Total elapsed: $((SECONDS / 60))m$((SECONDS % 60))s"
  echo "-------------------------------------------------------"

) 2>&1 | tee -a "$LOG_FILE" >> /proc/1/fd/1 &

echo "krea2v2-seedvr2.sh: background watcher started, main boot can continue"
echo "krea2v2-seedvr2.sh: tail -f $LOG_FILE  |  cat /workspace/BOOT_STATUS  |  bash /workspace/dlstatus.sh"
exit 0
