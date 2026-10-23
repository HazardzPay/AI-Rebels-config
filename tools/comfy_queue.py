#!/usr/bin/env python3
"""comfy_queue.py - run a test definition against a live ComfyUI through its HTTP API.

Why: SimplePromptBatcher writes the batcher's inputs into every PNG (not the line that made
it), joins parts with ", ", and runs as a list. Queuing each run as its own job fixes all
three: every PNG's embedded metadata holds the exact prompt that made it, filenames carry
the run label, and each render is an ordinary standalone run.

Usage (on the pod):
    python3 comfy_queue.py TEST.json --dry-run     # print runs and word counts, queue nothing
    python3 comfy_queue.py TEST.json               # queue every run, wait for each
    python3 comfy_queue.py TEST.json --zip         # ...then zip images + index for download

TEST.json (keep it next to the API-format workflow export it names):
{
  "name": "hmb_shape",                      # output subfolder and zip name
  "workflow": "workflow_api.json",          # API-format export, path relative to TEST.json
  "defaults": {
    "seed": 42424242,                       # -> KreaDualResolutionSelector.random_seed
    "sampler": {"handoff_percent": 12, "stage2_steps": 16},   # -> KreaTwoStageSampler inputs
    "loras": {"HMBreasts_krea2_epoch12.safetensors": {"on": true, "strength": 0.9}},
    "negative": ""                          # optional; omitted = leave as exported
  },
  "grid": {                                 # optional: cartesian product of axes
    "template": "{pose} ... {slot} ...",
    "axes": {"pose": {"upright": "...", "leaning": "..."}, "slot": {"perky": "...", "saggy": "..."}}
  },
  "runs": [                                 # optional: explicit runs (after grid runs)
    {"label": "x", "prompt": "full text", "seed": 1, "sampler": {...}, "loras": {...}}
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
- A run whose render settings match an earlier one (filename aside) gets a NOTE: ComfyUI
  reuses its cached image and saves a copy, so it is not an independent render.
- Upscaling is whatever the exported workflow had: a muted SeedVR2 branch is absent from an
  API export, so these runs are pre-upscale unless it was enabled before exporting.
- index.jsonl in the output subfolder records every run: label, files, exact prompt, words,
  seed, sampler settings, LoRA state, warm-up flag, prompt id, seconds.
"""
import argparse
import copy
import itertools
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
import zipfile


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def http(server, path, payload=None, timeout=30):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(server + path, data=data,
                                 headers={"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        die(f"{path} returned HTTP {e.code}: {body[:2000]}")
    except urllib.error.URLError as e:
        die(f"cannot reach ComfyUI at {server} ({e.reason}). Is it running?")


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
    r["seed"] = run.get("seed", defaults.get("seed"))
    r["sampler"] = {**defaults.get("sampler", {}), **run.get("sampler", {})}
    loras = copy.deepcopy(defaults.get("loras", {}))
    for name, cfg in run.get("loras", {}).items():
        loras[name] = {**loras.get(name, {}), **cfg}
    r["loras"] = loras
    r["negative"] = run.get("negative", defaults.get("negative"))
    return r


def build(base, ids, r, seed, prefix):
    wf = copy.deepcopy(base)
    wf[ids["pos"]]["inputs"]["text"] = r["prompt"]
    if r["negative"] is not None:
        wf[ids["neg"]]["inputs"]["text"] = r["negative"]
    if seed is not None:
        wf[ids["sel"]]["inputs"]["random_seed"] = seed
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
    wf[ids["save"]]["inputs"]["filename_prefix"] = prefix
    return wf


def lora_state(wf, ids):
    pl = wf[ids["pll"]]["inputs"]
    return tuple(sorted((v["lora"], bool(v.get("on")), float(v.get("strength", 0)))
                        for k, v in pl.items() if k.startswith("lora_") and isinstance(v, dict)))


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


def main():
    ap = argparse.ArgumentParser(description="Queue a test definition through the ComfyUI API.")
    ap.add_argument("definition")
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--output-dir", default="/workspace/runpod-slim/ComfyUI/output")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--zip", action="store_true")
    ap.add_argument("--no-warmup", action="store_true", help="skip warm-up renders")
    ap.add_argument("--timeout", type=int, default=900, help="seconds to wait per render")
    a = ap.parse_args()

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
    for k in ("pos", "neg"):
        if base[ids[k]]["class_type"] != "CLIPTextEncode":
            die(f"sampler {k} input is not a CLIPTextEncode")

    runs = [resolve(r, spec.get("defaults", {})) for r in expand_runs(spec)]
    print(f"{name}: {len(runs)} runs; nodes {ids}")
    for r in runs:
        print(f"  {r['label']:28s} {len(r['prompt'].split()):4d} words  seed {r['seed']}  "
              f"{r['sampler']}  | {r['prompt'][:70]}...")
    if a.dry_run:
        print("dry run: nothing queued")
        return

    out_dir = os.path.join(a.output_dir, name)
    os.makedirs(out_dir, exist_ok=True)
    index_path = os.path.join(out_dir, "index.jsonl")
    seen, last_state, done = {}, None, 0
    with open(index_path, "a") as idx:
        for r in runs:
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
            state = (lora_state(wf, ids), r["seed"])
            if state != last_state and not a.no_warmup:
                # Same seed as the measured run, one extra word so it is not served from cache.
                # A seed change before a measured run is itself suspected of causing the anomaly.
                wr = {**r, "prompt": r["prompt"] + " Warmup."}
                warm = build(base, ids, wr, r["seed"], f"{name}/_warmup/before_{r['label']}")
                pid, files, secs = run_one(a.server, warm, ids["save"], a.timeout)
                print(f"  warm-up before {r['label']}: {secs}s")
                idx.write(json.dumps({"label": f"_warmup_before_{r['label']}", "warmup": True, "files": files,
                                      "prompt": wr["prompt"], "seed": r["seed"], "loras": r["loras"],
                                      "prompt_id": pid, "seconds": secs}) + "\n")
            last_state = state
            pid, files, secs = run_one(a.server, wf, ids["save"], a.timeout)
            done += 1
            flag = "  (suspiciously fast: cached?)" if secs < 3 else ""
            print(f"[{done}/{len(runs)}] {r['label']}: {secs}s -> {', '.join(files) or 'NO FILE'}{flag}")
            idx.write(json.dumps({"label": r["label"], "warmup": False, "files": files, "prompt": r["prompt"],
                                  "words": len(r["prompt"].split()), "seed": r["seed"], "sampler": r["sampler"],
                                  "loras": r["loras"], "negative": r["negative"], "prompt_id": pid,
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
