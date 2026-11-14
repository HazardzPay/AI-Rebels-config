#!/usr/bin/env python3
"""comfy_queue.py - run a test definition against a live ComfyUI through its HTTP API.

Why: SimplePromptBatcher writes the batcher's inputs into every PNG (not the line that made
it), joins parts with ", ", and runs as a list. Queuing each run as its own job fixes all
three: every PNG's embedded metadata holds the exact prompt that made it, filenames carry
the run label, and each render is an ordinary standalone run.

Usage (on the pod):
    python3 comfy_queue.py TEST.json --dry-run     # print runs, word and token counts, queue nothing
    python3 comfy_queue.py TEST.json               # queue every run, wait for each
    python3 comfy_queue.py TEST.json --zip         # ...then zip images + index for download
    # off the pod: queue through RunPod's proxy and download every image as it finishes
    python3 comfy_queue.py TEST.json --server https://PODID-8188.proxy.runpod.net \
        --output-dir ~/results --fetch
    # queue-ahead (2026-11-02, preferred off the pod): queue everything once, then collect in calls;
    # the pod renders back to back between calls. tools/run_pods.sh wraps this for one or more pods.
    python3 comfy_queue.py TEST.json --server ... --output-dir ... --enqueue
    python3 comfy_queue.py TEST.json --server ... --output-dir ... --collect --fetch --wait 100
    python3 comfy_queue.py TEST.json --server ... --output-dir ... --cancel   # stop: drop unfinished jobs

TEST.json (keep it next to the API-format workflow export it names):
{
  "name": "hmb_shape",                      # output subfolder and zip name
  "workflow": "workflow_api.json",          # API-format export, path relative to TEST.json
  "defaults": {
    "seed": 42424242,                       # -> KreaDualResolutionSelector.random_seed
    "sampler": {"handoff_percent": 12, "stage2_steps": 12},   # -> KreaTwoStageSampler inputs
    "loras": {"HMBreasts_krea2_epoch12.safetensors": {"on": true, "strength": 0.9}},
    "negative": "",                         # optional; omitted = leave as exported
    "selector": {"aspect_ratio": "16:9"},   # optional; KreaDualResolutionSelector inputs
    "nodes": {"203": {"strength_model": 0.7}}  # optional; set inputs on any node by id
  },
  "grid": {                                 # optional: cartesian product of axes
    "template": "{pose} ... {slot} ...",
    "axes": {"pose": {"upright": "...", "leaning": "..."}, "slot": {"perky": "...", "saggy": "..."}}
  },
  "runs": [                                 # optional: explicit runs (after grid runs)
    {"label": "x", "prompt": "full text", "seed": 1, "sampler": {...}, "loras": {...}},
    {"label": "y", "prompt": "stage 1 text", "stage2_prompt": "stage 2 text", "seed": 1}   # needs an s2 export
  ]
}

Behaviour:
- Nodes are found by type, not id: the KreaTwoStageSampler, the CLIPTextEncode nodes its
  positive/negative inputs point at, KreaDualResolutionSelector, Power Lora Loader (rgthree)
  and SaveImage. The positive text is written straight into the encoder, so any batcher
  feeding it is cut out of the graph.
- Warm-up: before the first run, and before any run whose LoRA state or seed differs from
  the run before it, one discarded render is queued (saved under NAME/_warmup/). It uses the
  measured run's seed and settings with " Warmup." appended to the prompt, so it is not served
  from cache and no measured run is the first render after a seed change. Confirmed
  2026-10-23 (TESTS): that first render comes out in a different scene from later renders of
  the identical job. Mechanism unknown. --no-warmup skips it.
  Retired 2026-11-01 (the effect does not occur in memory mode; vault TESTS-archive 'Closed — First render
  after a seed change'): pass --no-warmup; queue-ahead modes (--enqueue, --collect, --cancel) never warm up.
- A run whose render settings match an earlier one (filename aside) gets a NOTE: ComfyUI
  reuses its cached image and saves a copy, so it is not an independent render.
- Upscaling is whatever the exported workflow had: a muted SeedVR2 branch is absent from an
  API export, so these runs are pre-upscale unless it was enabled before exporting.
- "nodes" (defaults or per run, merged per node) sets literal inputs on nodes by id, e.g. the
  strength of a LoraLoaderModelOnly on the stage 1 (RAW) path, which the Power Lora Loader
  does not reach. The node and input must already exist in the export (no new links).
  Node overrides count as LoRA state for the warm-up decision.
- Token counts (2026-11-07, P02): with tools/token_count.py beside this file and its tokenizer installed, the
  dry run prints each prompt's Qwen3-VL tokens and the total with Krea 2's template (34-token prefix, 5-token
  suffix), flags totals above 512 (the trained text length) and notes parentheses and brackets (literal text in
  Krea 2: no weighting). The index records "tokens" (prompt only) when available. Pod-side runs without it are unchanged.
- Adult check (task item 128, owner 2026-11-12): on the Mac (tools/prompt_lint.py beside this file) the dry run and
  --enqueue fail a run whose prompt or stage-2 prompt lacks 'adult woman' in its opening sentence, or whose negative
  does not end with ', child, teenager', unless the run carries "adult_exempt": "reason" (listed). Pod copies skip it.
- Stage-2 prompt (2026-11-07, P07): when the export wires a CLIPTextEncode into the sampler's
  stage2_positive_optional input (tests/workflow_api_production_sh_gen_s2.json), that encoder gets the run's
  "stage2_prompt", or the run's prompt when the run has none (identical conditioning, so the render matches the
  base export). A run with "stage2_prompt" against an export without that input is refused.
- index.jsonl in the output subfolder records every run: label, files, exact prompt, words,
  seed, sampler settings, LoRA state, warm-up flag, prompt id, seconds.
- Queue-ahead, since task item 124 (2026-11-13; tested against tools/comfy_stub.py by tools/test_comfy_queue.py):
  a GET with no usable answer is asked three times, a POST once (W4); --enqueue reads /queue once and /history only
  for the ids it must check (W1); a job already in the pod's queue with this run's whole graph is taken over, not
  queued again (W2); a run that failed twice, or twice finished with no image, is FAILED: recorded in failed.jsonl,
  not queued again, and the collect line then ends 'ALL DONE, n FAILED: labels'; an interrupted job counts as no
  attempt; --enqueue --retry-failed clears failed.jsonl (W3). A failed or unreadable answer is never read as
  'the pod does not have this job': the script stops.
"""
import argparse
import copy
import itertools
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import hashlib
import http.client as http_client  # 'http' is this file's own function
import zipfile
try:  # Mac-side token counts (P02); absent or without its tokenizer, the dry run shows words only
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import token_count
except ImportError:
    token_count = None

# First 12 hex of this file's sha256, written into every index line so results can be traced
# to the exact runner that produced them.
T0 = time.time()  # --wait counts from process start, so enqueue time is included
RUNNER_SHA = hashlib.sha256(open(os.path.abspath(__file__), "rb").read()).hexdigest()[:12]


# RunPod's proxy sits behind Cloudflare, which rejects Python's default urllib signature with
# HTTP 403 "error code: 1010". Any ordinary User-Agent passes.
UA = "Mozilla/5.0 (compatible; comfy_queue/1.0)"


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


GET_TRIES = 3            # task item 124, W4: a GET is asked up to three times; a POST never twice
RETRY_WAIT = float(os.environ.get("CQ_RETRY_WAIT", "3"))
HTTP_TIMEOUT = float(os.environ.get("CQ_HTTP_TIMEOUT", "30"))
FAIL_LIMIT = 2           # W3 (owner 2026-11-11): a run that has failed twice is finished, and is not queued again
POLL_MISSES, POLL_FULL_EVERY = 4, 10   # collect: see queued_mode (item 133 (d))
RERUN_PROBE = 12         # item 133 (b): how many runs --enqueue asks the pod about before queuing
HISTORY_BY_ID_MAX = 50   # W1: above this many ids to check, one full /history read is quicker than one call each


def http(server, path, payload=None, timeout=None):
    """One call to the pod. A GET that gets no usable answer (proxy 5xx, timeout, dropped connection, an HTML error
    page instead of JSON) is asked again, GET_TRIES in all; after the last the script stops, as it always did. A POST
    is never repeated: the pod may have acted on the first. An answer that fails is never read as an empty one."""
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"User-Agent": UA}
    if data:
        headers["Content-Type"] = "application/json"
    tries = GET_TRIES if payload is None else 1
    for attempt in range(1, tries + 1):
        req = urllib.request.Request(server + path, data=data, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout or HTTP_TIMEOUT) as r:
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            if e.code < 500 or attempt == tries:
                die(f"{path} returned HTTP {e.code}: {body[:2000]}")
            why = f"HTTP {e.code}"
        except urllib.error.URLError as e:
            if attempt == tries:
                die(f"cannot reach ComfyUI at {server} ({e.reason}). Is it running?" + POST_NOTE * (path == "/prompt"))
            why = str(e.reason)
        except (TimeoutError, ConnectionError, http_client.HTTPException, ValueError) as e:
            if attempt == tries:
                die(f"{path}: no usable answer from {server} ({type(e).__name__}: {e})" + POST_NOTE * (path == "/prompt"))
            why = f"{type(e).__name__}: {e}"
        print(f"  {path.split('?')[0]}: {why}; asking again ({attempt} of {tries})")
        time.sleep(RETRY_WAIT)


POST_NOTE = (". The pod may have taken this job all the same: run --enqueue again; it looks in the pod's queue for the "
             "job before queuing it (W2)")


def one_node(wf, class_type):
    hits = [k for k, n in wf.items() if n.get("class_type") == class_type]
    if len(hits) != 1:
        die(f"expected exactly one {class_type} in the workflow, found {len(hits)}")
    return hits[0]


def linked_node(wf, node_id, input_name):
    v = wf[node_id]["inputs"].get(input_name)
    if not (isinstance(v, list) and len(v) == 2):
        die(f"{wf[node_id]['class_type']}.{input_name} is not linked to a node")
    return str(v[0])


def expand_runs(spec):
    runs = []
    grid = spec.get("grid")
    if grid:
        names = list(grid["axes"].keys())
        for combo in itertools.product(*[list(grid["axes"][a].items()) for a in names]):
            label = "_".join(k for k, _ in combo)
            text = grid["template"].format(**{a: v for a, (_, v) in zip(names, combo)})
            runs.append({"label": label, "prompt": text})
    runs.extend(spec.get("runs", []))
    if not runs:
        die("the definition has no grid and no runs")
    labels = [r["label"] for r in runs]
    dupes = {l for l in labels if labels.count(l) > 1}
    if dupes:
        die(f"duplicate labels: {sorted(dupes)}")
    return runs


def resolve(run, defaults):
    r = {"label": run["label"], "prompt": " ".join(run["prompt"].split())}
    r["stage2_prompt"] = " ".join(run["stage2_prompt"].split()) if run.get("stage2_prompt") else None
    r["seed"] = run.get("seed", defaults.get("seed"))
    r["sampler"] = {**defaults.get("sampler", {}), **run.get("sampler", {})}
    loras = copy.deepcopy(defaults.get("loras", {}))
    for name, cfg in run.get("loras", {}).items():
        loras[name] = {**loras.get(name, {}), **cfg}
    r["loras"] = loras
    r["negative"] = run.get("negative", defaults.get("negative"))
    r["selector"] = {**defaults.get("selector", {}), **run.get("selector", {})}
    nodes = copy.deepcopy(defaults.get("nodes", {}))
    for nid, inp in run.get("nodes", {}).items():
        nodes[nid] = {**nodes.get(nid, {}), **inp}
    r["nodes"] = nodes
    r["adult_exempt"] = run.get("adult_exempt")  # task item 128: an exact re-render of a render made before the adult wording
    r["gate"] = run.get("gate")  # task item 131: the writer's garment and coverage, read by prompt_lint (Mac side)
    return r


def build(base, ids, r, seed, prefix):
    wf = copy.deepcopy(base)
    wf[ids["pos"]]["inputs"]["text"] = r["prompt"]
    if ids.get("pos2"):
        wf[ids["pos2"]]["inputs"]["text"] = r.get("stage2_prompt") or r["prompt"]
    if r["negative"] is not None:
        wf[ids["neg"]]["inputs"]["text"] = r["negative"]
    if seed is not None:
        wf[ids["sel"]]["inputs"]["random_seed"] = seed
    for k, v in r.get("selector", {}).items():
        if k not in wf[ids["sel"]]["inputs"] or k == "random_seed":
            die(f"KreaDualResolutionSelector: '{k}' is not a settable input (use 'seed' for the seed)")
        wf[ids["sel"]]["inputs"][k] = v
    for k, v in r["sampler"].items():
        if k not in wf[ids["smp"]]["inputs"]:
            die(f"KreaTwoStageSampler has no input '{k}'")
        wf[ids["smp"]]["inputs"][k] = v
    if r["loras"]:
        pl = wf[ids["pll"]]["inputs"]
        slots = {v["lora"]: k for k, v in pl.items() if k.startswith("lora_") and isinstance(v, dict)}
        for name, cfg in r["loras"].items():
            if name not in slots:
                die(f"LoRA {name} is not in the exported Power Lora Loader; add it in the UI and re-export")
            pl[slots[name]].update({k: cfg[k] for k in ("on", "strength") if k in cfg})
    for nid, inp in r.get("nodes", {}).items():
        if nid not in wf:
            die(f"node {nid} is not in the exported workflow")
        for k, v in inp.items():
            if k not in wf[nid]["inputs"] or isinstance(wf[nid]["inputs"][k], list):
                die(f"node {nid} ({wf[nid]['class_type']}): '{k}' is not a settable literal input")
            wf[nid]["inputs"][k] = v
    wf[ids["save"]]["inputs"]["filename_prefix"] = prefix
    return wf


def lora_state(wf, ids):
    pl = wf[ids["pll"]]["inputs"]
    return tuple(sorted((v["lora"], bool(v.get("on")), float(v.get("strength", 0)))
                        for k, v in pl.items() if k.startswith("lora_") and isinstance(v, dict)))


def pod_last_state(server):
    """(lora_state, seed) of the most recent job ComfyUI ran, from /history; None if unknown.

    The first-render-after-seed-change effect depends on what the pod actually ran last, which
    may be a browser render or an earlier invocation, not just this invocation's previous run.
    """
    h = http(server, "/history?max_items=1")
    for entry in h.values():
        try:
            graph = entry["prompt"][2]
            sel = [n for n in graph.values() if n.get("class_type") == "KreaDualResolutionSelector"]
            pll = [k for k, n in graph.items() if n.get("class_type") == "Power Lora Loader (rgthree)"]
            if len(sel) == 1 and len(pll) == 1:
                return (lora_state(graph, {"pll": pll[0]}), sel[0]["inputs"]["random_seed"])
        except (KeyError, IndexError, TypeError):
            pass
    return None


def short_name(rel, style=None):
    """Owner naming (definitions with \"layout\": \"test-folder\"). Default (2026-10-31): name_00001_.png -> name-1.png.
    style "subject-batch" (definition key \"name_style\", owner 2026-11-04): the label is SUBJECT_CAMPAIGN-TEST-CODE_variation, so
    subject_rest_00001_.png -> subject-1_rest.png (batch number straight after the subject; a name sorts by subject, then batch,
    then test and variation order). A file name with no underscore before the counter falls back to the default."""
    import re
    if style == "subject-batch":
        d, fn = os.path.split(rel)
        m = re.match(r'^([^_]+)_(.+)_(\d{5})_\.png$', fn)
        if m:
            return os.path.join(d, f'{m.group(1)}-{int(m.group(3))}_{m.group(2)}.png')
    return re.sub(r'_(\d{5})_\.png$', lambda m: f'-{int(m.group(1))}.png', rel)


def fetch(server, rel, dest_root, timeout=300, short=False, style=None):
    """Download one output image through ComfyUI's /view endpoint into dest_root/rel (short=True drops the counter padding; style: see short_name)."""
    sub, fn = os.path.split(rel)
    q = urllib.parse.urlencode({"filename": fn, "subfolder": sub, "type": "output"})
    dest = os.path.join(dest_root, short_name(rel, style) if short else rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    for attempt in (1, 2, 3):
        try:
            with urllib.request.urlopen(urllib.request.Request(f"{server}/view?{q}", headers={"User-Agent": UA}),
                                        timeout=timeout) as r, open(dest + ".part", "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            os.replace(dest + ".part", dest)
            return
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            print(f"  download of {rel} failed (attempt {attempt}/3): {e}")
            time.sleep(3)
    die(f"could not download {rel}")


def run_one(server, wf, save_id, timeout):
    pid = http(server, "/prompt", {"prompt": wf, "client_id": str(uuid.uuid4())})["prompt_id"]
    t0 = time.time()
    while True:
        h = http(server, f"/history/{pid}")
        if pid in h:
            entry = h[pid]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                die(f"render failed: {json.dumps(status.get('messages', []))[:2000]}")
            imgs = entry.get("outputs", {}).get(save_id, {}).get("images", [])
            files = [os.path.join(i.get("subfolder", ""), i["filename"]) for i in imgs]
            return pid, files, round(time.time() - t0, 1)
        if time.time() - t0 > timeout:
            die(f"no result after {timeout}s for prompt {pid}")
        time.sleep(1)


def history_seconds(entry):
    """Render time from a /history entry (execution_start to execution_success), or None."""
    m = {x[0]: x[1].get("timestamp") for x in entry.get("status", {}).get("messages", []) if len(x) == 2}
    s, t = m.get("execution_start"), m.get("execution_success")
    return round((t - s) / 1000, 1) if s and t else None


def queue_ids(server):
    q = http(server, "/queue")
    return {j[1] for k in ("queue_running", "queue_pending") for j in q.get(k, [])}


def read_pending(path):
    if not os.path.exists(path):
        return {}
    return {d["label"]: d for d in (json.loads(l) for l in open(path) if l.strip())}


def pod_has_file(server, rel):
    """Is this output file on the pod? True, False (HTTP 404), or None when the pod gave no usable answer. Only the
    answer's status is read, not the image."""
    sub, fn = os.path.split(rel)
    q = urllib.parse.urlencode({"filename": fn, "subfolder": sub, "type": "output"})
    try:
        with urllib.request.urlopen(urllib.request.Request(f"{server}/view?{q}", headers={"User-Agent": UA}), timeout=HTTP_TIMEOUT):
            return True
    except urllib.error.HTTPError as e:
        return False if e.code == 404 else None
    except Exception:
        return None


def graph_sha(wf):
    return hashlib.sha256(json.dumps(wf, sort_keys=True).encode()).hexdigest()[:16]


def failed_counts(path, sha):
    """{label: failed attempts} from failed.jsonl, counting distinct jobs whose settings are the run's present ones
    (sha: label -> graph_sha of the run without its file name), so a rebuilt definition starts from nought."""
    jobs = {}
    if os.path.exists(path):
        for line in open(path):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("label") in sha and d.get("sha") == sha[d["label"]]:
                jobs.setdefault(d["label"], set()).add(d.get("prompt_id"))
    return {l: len(p) for l, p in jobs.items()}


def write_pending(path, pend):
    with open(path + ".tmp", "w") as f:
        for d in pend.values():
            f.write(json.dumps(d) + "\n")
    os.replace(path + ".tmp", path)


def queued_mode(a, spec, base, ids, runs, out_dir, index_path, done_labels):
    """Queue-ahead mode (2026-11-02). --enqueue puts every remaining run into the pod's own ComfyUI
    queue at once, so the GPU renders back to back with no gaps between calls and no waiting on another
    pod. --collect records and downloads whatever has finished. queued.jsonl in the output subfolder
    holds runs queued but not yet collected (label -> prompt id). Both are idempotent and safe to repeat."""
    name = spec["name"]
    pend_path = os.path.join(out_dir, "queued.jsonl")
    pend = read_pending(pend_path)
    by_label = {r["label"]: r for r in runs}

    if a.cancel:
        mine = [d["prompt_id"] for d in pend.values()]
        if mine:
            http(a.server, "/queue", {"delete": mine})
            running = http(a.server, "/queue").get("queue_running", [])
            if any(j[1] in mine for j in running):
                http(a.server, "/interrupt", {})
        write_pending(pend_path, {})
        print(f"cancel: removed {len(mine)} queued job(s) of {name} from the pod (finished renders stay; collect them first if wanted)")
        return

    # W3 (task item 124; owner 2026-11-11): failed.jsonl holds one line per failed attempt. A run whose present
    # settings have failed FAIL_LIMIT times is finished ('FAILED') and is not queued again; --retry-failed clears it.
    fail_path = os.path.join(out_dir, "failed.jsonl")
    sha = {r["label"]: graph_sha(build(base, ids, r, r["seed"], "")) for r in runs}
    if a.retry_failed:
        open(fail_path, "w").close()
        print("retry-failed: failed.jsonl cleared; failed runs are queued again")
    def final_fails():
        return {l for l, c in failed_counts(fail_path, sha).items() if c >= FAIL_LIMIT and l not in done_labels}

    if a.enqueue:
        final = final_fails()
        cand = [r for r in runs if r["label"] not in done_labels and r["label"] not in final]
        # W1: one /queue read, and only when there is something to check or to queue. No /history read at all when
        # nothing is waiting (it was a full 10000-item read on every call, about 43 s on a long-lived pod).
        q = http(a.server, "/queue") if (pend or any(r["label"] not in pend for r in cand)) else {}
        jobs = [j for k in ("queue_running", "queue_pending") for j in q.get(k, [])]
        live = {j[1] for j in jobs}
        # Drop pending entries the pod no longer knows (pod restarted: queue lost), so they are queued again. An id is
        # asked for singly; past HISTORY_BY_ID_MAX of them (a restart with hundreds waiting) one full read is quicker.
        check = [d["prompt_id"] for d in pend.values() if d["prompt_id"] not in live]
        if len(check) > HISTORY_BY_ID_MAX:
            known = set(http(a.server, "/history?max_items=10000"))
        else:
            known = {p for p in check if p in http(a.server, f"/history/{p}")}
        stale = [l for l, d in pend.items() if d["prompt_id"] not in live and d["prompt_id"] not in known]
        for l in stale:
            del pend[l]
        if stale:
            print(f"enqueue: {len(stale)} queued job(s) lost by the pod (restart?); queuing them again")
        todo = [r for r in cand if r["label"] not in pend]
        if a.max_runs:
            todo = todo[:a.max_runs]
        seen = {}
        for r in runs:
            key = sha[r["label"]]
            if key in seen and r in todo:
                print(f"NOTE {r['label']}: same render settings as {seen[key]}; ComfyUI will save a copy of the cached image")
            seen.setdefault(key, r["label"])
        # W2 (owner 2026-11-11): a job the pod took on a call that was cut off before its record was written is still
        # in the pod's queue. Adopt it instead of queuing it a second time, but only when its whole graph is this run's.
        taken = {d["prompt_id"] for d in pend.values()}
        by_prefix = {}
        for j in jobs:
            g = j[2] if len(j) > 2 and isinstance(j[2], dict) else {}
            pre = ((g.get(ids["save"]) or {}).get("inputs") or {}).get("filename_prefix")
            if isinstance(pre, str):
                by_prefix.setdefault(pre, []).append(j)
        # Task item 133 (b) (owner 2026-11-13): SaveImage numbers on from the files already in the pod's folder, and the
        # Mac name takes that number as the batch image, so a run rendered again on a pod that still holds its earlier
        # files comes back as images 3 and 4 (seen 2026-11-12). Warn before queuing; nothing is blocked and no name changes.
        # Up to RERUN_PROBE runs are asked about, spread over the list, so a large first call stays inside its limit.
        new = [r for r in todo if f"{name}/{r['label']}" not in by_prefix]
        step = max(1, -(-len(new) // RERUN_PROBE))
        ask = new[::step]; held = [r["label"] for r in ask if pod_has_file(a.server, f"{name}/{r['label']}_00001_.png")]
        if held:
            print(f"enqueue: WARNING the pod already holds images for {len(held)} of the {len(ask)} run(s) checked (of {len(new)} to queue), e.g. {', '.join(held[:3])}: "
                  f"a run rendered again there is numbered on from them and arrives as batch images 3, 4, not 1, 2. "
                  f"If this is a deliberate re-run, give it a new definition name (tools/subset_def.py) or use a fresh pod; --cancel drops what this call queues")
        queued = adopted = 0
        for r in todo:
            wf = build(base, ids, r, r["seed"], f"{name}/{r['label']}")
            same = json.loads(json.dumps(wf))
            hit = next((j for j in by_prefix.get(f"{name}/{r['label']}", []) if j[1] not in taken and j[2] == same), None)
            if hit:
                pid = hit[1]; adopted += 1
                print(f"enqueue: {r['label']} is already in the pod's queue (job {pid[:8]}, same graph); taken over, not queued again")
            else:
                pid = http(a.server, "/prompt", {"prompt": wf, "client_id": str(uuid.uuid4())})["prompt_id"]; queued += 1
            taken.add(pid)
            pend[r["label"]] = {"label": r["label"], "prompt_id": pid, "queued": time.time()}
            write_pending(pend_path, pend)  # after every job, so an interrupted call loses nothing
        print(f"enqueue: {queued} job(s) queued now" + (f", {adopted} taken over from the pod's queue" if adopted else "")
              + f"; {len(pend)} of {name} waiting on the pod; "
              f"{len(done_labels)} already collected; {len(runs)} total" + (f"; {len(final)} FAILED, not queued again" if final else ""))
        if not a.collect:
            return

    # --collect: poll until everything queued is collected or --wait seconds pass.
    t_end = T0 + a.wait
    collected = 0
    # Task item 133 (d) (owner 2026-11-13): the pod works through its queue in order, so only the first few waiting jobs
    # can have finished. A pass asks for them in queue order and stops after POLL_MISSES in a row that are not finished;
    # every POLL_FULL_EVERY-th pass, and the first of each call, asks for all of them (jobs taken over or queued again
    # sit out of order). Before, every pass asked for every waiting job: 176 calls a pass on a large definition.
    passes = 0
    with open(index_path, "a") as idx:
        while True:
            full, misses = passes % POLL_FULL_EVERY == 0, 0
            passes += 1
            for label, d in list(pend.items()):
                if not full and misses >= POLL_MISSES:
                    break
                h = http(a.server, f"/history/{d['prompt_id']}")
                if d["prompt_id"] not in h:
                    misses += 1
                    continue
                misses = 0
                entry = h[d["prompt_id"]]
                def failed(reason):
                    # the failure is written before the job leaves queued.jsonl, and counted by job id, so a call
                    # cut off in between neither loses the attempt nor counts it twice
                    with open(fail_path, "a") as ff:
                        ff.write(json.dumps({"label": label, "prompt_id": d["prompt_id"], "sha": sha.get(label),
                                             "time": time.strftime("%Y-%m-%d %H:%M:%S"), "reason": reason}) + "\n")
                    del pend[label]
                    write_pending(pend_path, pend)
                    c = failed_counts(fail_path, sha).get(label, 0)
                    print(f"ERROR {label}: attempt {c} of {FAIL_LIMIT} failed on the pod: {reason} "
                          + ("(FAILED for good: not queued again; --retry-failed clears)" if c >= FAIL_LIMIT
                             else "(not recorded; --enqueue queues it again)"))
                if entry.get("status", {}).get("status_str") == "error":
                    msgs = entry["status"].get("messages", [])
                    if any(isinstance(m, list) and m and m[0] == "execution_interrupted" for m in msgs):
                        del pend[label]   # a cancel or a relaunch is not a failed render: no attempt counted
                        write_pending(pend_path, pend)
                        print(f"NOTE {label}: interrupted on the pod (not counted as a failure; --enqueue queues it again)")
                    else:
                        failed(json.dumps(msgs)[:600])
                    continue
                imgs = entry.get("outputs", {}).get(ids["save"], {}).get("images", [])
                files = [os.path.join(i.get("subfolder", ""), i["filename"]) for i in imgs]
                if not files:
                    # W3: finished with no image (ComfyUI served the whole job from its cache: the same job twice).
                    # It used to be written to the index with no files and counted as done.
                    failed("the job finished with no image in its result (served from ComfyUI's cache: a second copy of an earlier job?)")
                    continue
                if a.fetch:
                    for f in files:
                        fetch(a.server, f, a.output_dir, short=spec.get("layout") == "test-folder", style=spec.get("name_style"))
                r = by_label.get(label)
                if r is None:
                    del pend[label]
                    write_pending(pend_path, pend)
                    print(f"NOTE {label}: finished but no longer in the definition; downloaded, not indexed")
                    continue
                secs = history_seconds(entry)
                collected += 1
                done_labels.add(label)
                print(f"[{len(done_labels)}/{len(runs)}] {label}: {secs}s")
                idx.write(json.dumps({"runner": RUNNER_SHA, "label": label, "warmup": False, "files": files,
                                      "prompt": r["prompt"], "words": len(r["prompt"].split()), "tokens": r.get("tokens"),
                                      "stage2_prompt": r["stage2_prompt"], "seed": r["seed"], "sampler": r["sampler"], "loras": r["loras"], "nodes": r["nodes"],
                                      "selector": r["selector"], "negative": r["negative"],
                                      "prompt_id": d["prompt_id"], "seconds": secs, "mode": "queued"}) + "\n")
                idx.flush()
                # Only now drop it from the pending list (fix 2026-11-02 15:40: dropping it before the download and
                # index write meant a call cut off in between lost the run, and the next --enqueue rendered it again).
                del pend[label]
                write_pending(pend_path, pend)
            if not pend or time.time() >= t_end:
                break
            time.sleep(3)
    final = sorted(final_fails())
    left = len([r for r in runs if r["label"] not in done_labels]) - len(final)   # runs still to render
    print(f"collect: {collected} new; {len(done_labels)}/{len(runs)} done; {len(pend)} still queued on the pod"
          + ("; ALL DONE" + (f", {len(final)} FAILED: {', '.join(final[:20])}{' ...' if len(final) > 20 else ''}" if final else "") if left == 0 else "")
          + (f"; {len(final)} FAILED so far" if final and left else "")
          + (f"; {left - len(pend)} not queued - run --enqueue" if left - len(pend) > 0 else ""))


def main():
    ap = argparse.ArgumentParser(description="Queue a test definition through the ComfyUI API.")
    ap.add_argument("definition")
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--output-dir", default="/workspace/runpod-slim/ComfyUI/output")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--zip", action="store_true")
    ap.add_argument("--no-warmup", action="store_true", help="skip warm-up renders")
    ap.add_argument("--fetch", action="store_true",
                    help="download each image through /view into --output-dir (for running off the pod, "
                         "e.g. --server https://PODID-8188.proxy.runpod.net --output-dir ~/results)")
    ap.add_argument("--timeout", type=int, default=900, help="seconds to wait per render")
    ap.add_argument("--resume", action="store_true",
                    help="skip runs already recorded in this test's index.jsonl")
    ap.add_argument("--max-runs", type=int, default=0,
                    help="stop after this many measured runs (0 = all); use with --resume to run in chunks")
    ap.add_argument("--enqueue", action="store_true",
                    help="queue-ahead: put every remaining run (or --max-runs of them) into the pod's queue at once and return")
    ap.add_argument("--collect", action="store_true",
                    help="queue-ahead: record (and with --fetch download) runs that have finished; waits up to --wait seconds")
    ap.add_argument("--wait", type=int, default=0, help="with --collect: keep polling until this many seconds after start (enqueue time included)")
    ap.add_argument("--cancel", action="store_true", help="queue-ahead: remove this test's unfinished jobs from the pod's queue")
    ap.add_argument("--retry-failed", action="store_true",
                    help="with --enqueue: clear failed.jsonl, so runs that failed twice (FAILED) are queued again")
    a = ap.parse_args()
    if a.retry_failed and not a.enqueue:
        die("--retry-failed goes with --enqueue")
    if (a.enqueue or a.collect or a.cancel) and not a.no_warmup:
        a.no_warmup = True  # warm-ups retired 2026-11-01; queue-ahead never does them

    spec = json.load(open(a.definition))
    name = spec["name"]
    wf_path = os.path.join(os.path.dirname(os.path.abspath(a.definition)), spec["workflow"])
    if not os.path.exists(wf_path):
        die(f"workflow not found: {wf_path}")
    base = json.load(open(wf_path))
    if "nodes" in base:
        die("that is the UI export; use Workflow > Export (API)")

    ids = {"smp": one_node(base, "KreaTwoStageSampler"), "sel": one_node(base, "KreaDualResolutionSelector"),
           "pll": one_node(base, "Power Lora Loader (rgthree)"), "save": one_node(base, "SaveImage")}
    ids["pos"] = linked_node(base, ids["smp"], "positive")
    ids["neg"] = linked_node(base, ids["smp"], "negative")
    v2 = base[ids["smp"]]["inputs"].get("stage2_positive_optional")
    ids["pos2"] = str(v2[0]) if isinstance(v2, list) and len(v2) == 2 else None
    for k in ("pos", "neg", "pos2"):
        if ids[k] and base[ids[k]]["class_type"] != "CLIPTextEncode":
            die(f"sampler {k} input is not a CLIPTextEncode")
    if ids["pos2"] and ids["pos2"] in (ids["pos"], ids["neg"]):
        die("stage2_positive_optional must have its own CLIPTextEncode")

    runs = [resolve(r, spec.get("defaults", {})) for r in expand_runs(spec)]
    if any(r["stage2_prompt"] for r in runs) and not ids["pos2"]:
        die(f"runs carry stage2_prompt but {spec['workflow']} has no stage2_positive_optional encoder (use the _s2 export)")
    print(f"{name}: {len(runs)} runs; runner {RUNNER_SHA}; nodes {ids}")
    cast_fails = 0
    if a.collect or a.cancel:  # task item 108 (2026-11-09): collecting or cancelling queued jobs never depends on the register
        print("cast check: skipped for --collect and --cancel (it ran at the dry run and at --enqueue)")
    else:
        try:  # CAC cast check (task item 64 (b); tools/cast_build/CAC_SPEC.md): Mac side only; on a pod there is no register
            sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "cast_build")); import cast_lib
            cast_fails = cast_lib.report(spec, quiet=True)
        except ImportError:
            print("cast check: cast_lib not here (pod copy); the Mac dry run carries it")
    adult_fails = []
    if not (a.collect or a.cancel):  # task item 128 (owner 2026-11-12): 'adult woman' in the opening and ', child, teenager' ending the negative; Mac side, like the cast check
        try:
            import prompt_lint
            adult_fails, adult_ex = prompt_lint.adult_report(runs)
            for lab, m in adult_fails: print(f"    ADULT FAIL {lab}: {m}")
            for lab, why in adult_ex: print(f"    adult exempt {lab}: {why}")
            print(f"adult check: {len(adult_fails)} fail(s), {len(adult_ex)} exempt run(s) (task item 128)")
        except ImportError:
            print("adult check: prompt_lint not here (pod copy); the Mac dry run carries it")
    for r in runs:
        r["tokens"] = token_count.count(r["prompt"]) if token_count else None
    over = 0
    for r in ([] if (a.enqueue or a.collect or a.cancel) else runs):
        tok = token_count.describe(r["prompt"]) if token_count else "tok n/a"
        over += "OVER" in tok
        print(f"  {r['label']:28s} {len(r['prompt'].split()):4d} words  {tok}  seed {r['seed']}  "
              f"{r['sampler']}{('  nodes ' + json.dumps(r['nodes'])) if r['nodes'] else ''}  | {r['prompt'][:70]}...")
        for note in (token_count.lint(r["prompt"]) if token_count else []):
            print(f"    LINT {r['label']}: {note}")
        if r["stage2_prompt"]:
            tok2 = token_count.describe(r["stage2_prompt"]) if token_count else "tok n/a"
            print(f"    stage 2: {len(r['stage2_prompt'].split()):4d} words  {tok2}  | {r['stage2_prompt'][:70]}...")
            for note in (token_count.lint(r["stage2_prompt"]) if token_count else []):
                print(f"    LINT {r['label']} (stage 2): {note}")
    if a.dry_run:
        try:  # coherence lints (task item 25, owner 2026-11-08: warnings only); Mac side, like the cast check
            import prompt_lint
            notes = [(r["label"], n) for r in runs for n in prompt_lint.lint(r["prompt"], r.get("gate"))]
            notes += [("set", n) for n in prompt_lint.lint_set([(r["seed"], r["prompt"]) for r in runs])]
            notes, info = prompt_lint.summarise(notes) if hasattr(prompt_lint, "summarise") else (notes, [])  # item 102: low-risk framing as one line
            for lab, n in notes: print(f"    LINT {lab}: {n}")
            for line in info: print(f"    INFO {line}")
            print(f"coherence lint: {len(notes)} note(s) (warnings; fix or explain each before the boot gate){f', {len(info)} summary line(s)' if info else ''}")
        except ImportError:
            print("coherence lint: prompt_lint not here (pod copy); the Mac dry run carries it")
        if token_count and token_count.tokenizer() is None:
            print(f"tokens: not counted ({token_count.why()})")
        elif token_count:
            print(f"tokens: {over} of {len(runs)} run(s) above {token_count.BUDGET} with the template")
        print("dry run: nothing queued")
        if cast_fails: die(f"cast check: {cast_fails} fail(s); fix before any render (boot gate)")
        if adult_fails: die(f"adult check: {len(adult_fails)} fail(s); fix before any render (boot gate; task item 128)")
        return
    if cast_fails: die(f"cast check: {cast_fails} fail(s); nothing queued")
    if adult_fails: die(f"adult check: {len(adult_fails)} fail(s); nothing queued (task item 128)")
    try:  # CAC (task item 64 (f)): each cast woman's used_in gets this definition, for the balanced rotation (Mac side only)
        if "cast_lib" in sys.modules and not (a.collect or a.cancel): print("cast use recorded:", ", ".join(sys.modules["cast_lib"].record_use(spec)) or "none")
    except Exception as e: print(f"cast use not recorded ({e})")

    out_dir = os.path.join(a.output_dir, name)
    os.makedirs(out_dir, exist_ok=True)
    index_path = os.path.join(out_dir, "index.jsonl")
    done_labels = set()
    if a.resume and os.path.exists(index_path):
        for line in open(index_path):
            d = json.loads(line)
            if not d.get("warmup"):
                done_labels.add(d["label"])
        if done_labels:
            print(f"resume: {len(done_labels)} run(s) already done")
    if a.enqueue or a.collect or a.cancel:
        if not a.resume and os.path.exists(index_path):  # queue-ahead always resumes from the index
            done_labels = {json.loads(l)["label"] for l in open(index_path) if l.strip() and not json.loads(l).get("warmup")}
        queued_mode(a, spec, base, ids, runs, out_dir, index_path, done_labels)
        return
    seen, done = {}, 0
    last_state = None if a.no_warmup else pod_last_state(a.server)
    with open(index_path, "a") as idx:
        for r in runs:
            if r["label"] in done_labels:
                continue
            if a.max_runs and done >= a.max_runs:
                left = len([x for x in runs if x["label"] not in done_labels]) - done
                print(f"stopping after {done} run(s) (--max-runs); {left} left - rerun with --resume")
                break
            wf = build(base, ids, r, r["seed"], f"{name}/{r['label']}")
            # Same render settings, ignoring the filename: ComfyUI reuses its cached image and
            # only the save re-runs, so the file is a copy, not a new render.
            key = json.dumps(build(base, ids, r, r["seed"], ""), sort_keys=True)
            if key in seen:
                print(f"NOTE {r['label']}: same render settings as {seen[key]}; ComfyUI will save a copy "
                      f"of the cached image, not a new render")
            seen.setdefault(key, r["label"])
            # Warm up on any change of LoRA state or seed: the first render after a seed change
            # was confirmed to render a different scene (TESTS, 2026-10-23).
            state = ((lora_state(wf, ids), json.dumps(r["nodes"], sort_keys=True)) if r["nodes"] else lora_state(wf, ids), r["seed"])
            if state != last_state and not a.no_warmup:
                # Same seed as the measured run, one extra word so it is not served from cache.
                # A seed change before a measured run is itself suspected of causing the anomaly.
                wr = {**r, "prompt": r["prompt"] + " Warmup."}
                warm = build(base, ids, wr, r["seed"], f"{name}/_warmup/before_{r['label']}")
                pid, files, secs = run_one(a.server, warm, ids["save"], a.timeout)
                print(f"  warm-up before {r['label']}: {secs}s")
                idx.write(json.dumps({"runner": RUNNER_SHA, "label": f"_warmup_before_{r['label']}", "warmup": True, "files": files,
                                      "prompt": wr["prompt"], "seed": r["seed"], "loras": r["loras"],
                                      "prompt_id": pid, "seconds": secs}) + "\n")
            last_state = state
            pid, files, secs = run_one(a.server, wf, ids["save"], a.timeout)
            if a.fetch:
                for f in files:
                    fetch(a.server, f, a.output_dir, short=spec.get("layout") == "test-folder", style=spec.get("name_style"))
            done += 1
            flag = "  (suspiciously fast: cached?)" if secs < 3 else ""
            print(f"[{done}/{len(runs)}] {r['label']}: {secs}s -> {', '.join(files) or 'NO FILE'}{flag}")
            idx.write(json.dumps({"runner": RUNNER_SHA, "label": r["label"], "warmup": False, "files": files, "prompt": r["prompt"],
                                  "words": len(r["prompt"].split()), "tokens": r.get("tokens"), "stage2_prompt": r["stage2_prompt"], "seed": r["seed"], "sampler": r["sampler"],
                                  "loras": r["loras"], "nodes": r["nodes"], "selector": r["selector"], "negative": r["negative"], "prompt_id": pid,
                                  "seconds": secs}) + "\n")
            idx.flush()
    print(f"index: {index_path}")

    if a.zip:
        zpath = os.path.join(os.environ.get("CQ_ZIP_DIR", "/workspace"), f"{name}.zip")
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_STORED) as z:
            for root, _, files in os.walk(out_dir):
                for f in files:
                    full = os.path.join(root, f)
                    z.write(full, os.path.relpath(full, a.output_dir))
            z.write(os.path.abspath(a.definition), f"{name}/definition.json")
        print(f"zip: {zpath}  (download it from Jupyter)")


if __name__ == "__main__":
    main()
