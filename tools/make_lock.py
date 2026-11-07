#!/usr/bin/env python3
"""make_lock.py - write lock.sh (the build lock the boot scripts read) for one boot script.

The lock pins what a boot installs: a commit SHA per custom node, an HF revision and a sha256 per model file,
and the ComfyUI version the pods are expected to report. Sources, strongest first:
  --pod URL          a pod booted with LOCK_MODE=record (or enforce): reads /view?filename=build_fingerprint.json
                     &type=input (node SHAs as checked out, sha256 of every downloaded file, ComfyUI and torch
                     versions) and /object_info (which node packs actually loaded)
  --fingerprint F    the same fingerprint as a file (e.g. copied from /workspace/BUILD_FINGERPRINT.json)
  --upstream         fill the gaps from upstream: node HEAD via git ls-remote (rgthree: main), HF revision and
                     LFS sha256 via the HF API, CivitAI SHA256 via its API. Used alone it gives a DRAFT lock (what a
                     pod booted now would get), not a record of what a pod ran.
Where two sources give a file's sha256 and they differ, the pod wins and a WARNING comment is written; exit 2.

Usage: python3 tools/make_lock.py --registry registry.sh --script scripts/krea2raw-seedvr2.sh
                                  [--pod URL | --fingerprint F] [--upstream] --lock-id ID [--out lock.sh]
No tokens are read or written. Output is bash, sourced by the boot script after registry.sh."""
import argparse, json, re, subprocess, sys, urllib.request, urllib.parse, datetime
UA = {"User-Agent": "Mozilla/5.0"}

def get(url, timeout=30):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout))

def post_form(url, data, timeout=30):
    req = urllib.request.Request(url, data=data.encode(), headers={**UA, "Content-Type": "application/x-www-form-urlencoded"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))

def parse_registry(path):
    t = open(path).read(); out = {}
    for arr in ("CUSTOM_NODES", "HF_MODELS", "CIVITAI_LORAS"):
        out[arr] = dict(re.findall(arr + r'\[([^\]]+)\]="([^"]+)"', t))
    return out

def parse_script(path):
    t = open(path).read()
    hf = re.findall(r'\$\{HF_MODELS\[([^\]]+)\]\}', t)
    m = re.search(r'CIVITAI_QUEUE=\((.*?)\n\s*\)', t, re.S)
    civ = re.findall(r'"([^"]+)"', m.group(1)) if m else []
    nodes = re.findall(r'clone_node "([^"]+)"', t)
    return list(dict.fromkeys(hf)), civ, list(dict.fromkeys(nodes))

def hf_parts(url):
    m = re.match(r'https://huggingface.co/([^/]+/[^/]+)/resolve/([^/]+)/(.+)$', url)
    return m.groups() if m else (None, None, None)

def upstream_hf(url):
    repo, rev, path = hf_parts(url)
    info = get(f"https://huggingface.co/api/models/{repo}/revision/{rev}")
    repo = info.get("id", repo)  # canonical id: a renamed repo answers POST paths-info with a 307
    pi = post_form(f"https://huggingface.co/api/models/{repo}/paths-info/{info['sha']}", "paths=" + urllib.parse.quote(path))
    sha = (pi[0].get("lfs") or {}).get("oid") if pi else None
    return info["sha"], sha

def upstream_civitai(url):
    m = re.search(r'/models/(\d+)', url); f = re.search(r'fileId=(\d+)', url)
    d = get(f"https://civitai.com/api/v1/model-versions/{m.group(1)}")
    files = d.get("files", [])
    pick = [x for x in files if f and str(x.get("id")) == f.group(1)] or files[:1]
    s = pick[0].get("hashes", {}).get("SHA256") if pick else None
    return s.lower() if s else None

def upstream_node(name, url):
    ref = "refs/heads/main" if name == "rgthree" else "HEAD"
    out = subprocess.run(["git", "ls-remote", url, ref], capture_output=True, text=True, timeout=60).stdout.split()
    return out[0] if out else None

ap = argparse.ArgumentParser()
ap.add_argument("--registry", required=True); ap.add_argument("--script", required=True)
ap.add_argument("--pod"); ap.add_argument("--fingerprint"); ap.add_argument("--upstream", action="store_true")
ap.add_argument("--lock-id", required=True); ap.add_argument("--out")
a = ap.parse_args()
reg = parse_registry(a.registry); hf_keys, civ_keys, node_keys = parse_script(a.script)
fp, loaded = {}, None
if a.pod:
    base = a.pod.rstrip("/")
    fp = get(base + "/view?filename=build_fingerprint.json&type=input")
    oi = get(base + "/object_info", timeout=120)
    loaded = {v.get("python_module", "") for v in oi.values()}
elif a.fingerprint:
    fp = json.load(open(a.fingerprint))
if not fp and not a.upstream:
    sys.exit("give --pod, --fingerprint or --upstream")

warn, nodes, hfrev, sha = [], {}, {}, {}
fp_nodes, fp_models = fp.get("nodes", {}), fp.get("models", {})
for n in node_keys:
    if n not in reg["CUSTOM_NODES"]: warn.append(f"node {n} used by the script but not in registry.sh"); continue
    s = (fp_nodes.get(n) or {}).get("commit")
    if fp_nodes.get(n, {}).get("dirty"): warn.append(f"node {n}: working tree dirty on the pod (local edits)")
    if not s and a.upstream: s = upstream_node(n, reg["CUSTOM_NODES"][n])
    if s: nodes[n] = s
    else: warn.append(f"node {n}: no commit found")
    if loaded is not None and fp_nodes.get(n, {}).get("dir"):
        mod = "custom_nodes." + fp_nodes[n]["dir"]
        if mod not in loaded: warn.append(f"node {n}: no node classes from {mod} in /object_info (import failed?)")
for k in hf_keys:
    if k not in reg["HF_MODELS"]: warn.append(f"HF file {k} used by the script but not in registry.sh"); continue
    pod_sha = fp_models.get(k)
    up_rev = up_sha = None
    if a.upstream:
        try: up_rev, up_sha = upstream_hf(reg["HF_MODELS"][k])
        except Exception as e: warn.append(f"HF {k}: upstream lookup failed ({e})")
    if pod_sha and up_sha and pod_sha != up_sha:
        warn.append(f"HF {k}: pod sha256 {pod_sha[:12]} differs from upstream {up_sha[:12]}: the file changed upstream since that pod booted; revision NOT pinned")
        up_rev = None
    if up_rev: hfrev[k] = up_rev
    if pod_sha or up_sha: sha[k] = pod_sha or up_sha
for k in civ_keys:
    if k not in reg["CIVITAI_LORAS"]: warn.append(f"CivitAI file {k} used by the script but not in registry.sh"); continue
    pod_sha = fp_models.get(k); up = None
    if a.upstream:
        try: up = upstream_civitai(reg["CIVITAI_LORAS"][k])
        except Exception as e: warn.append(f"CivitAI {k}: upstream lookup failed ({e})")
    if pod_sha and up and pod_sha != up: warn.append(f"CivitAI {k}: pod sha256 {pod_sha[:12]} differs from CivitAI's {up[:12]}")
    if pod_sha or up: sha[k] = pod_sha or up

src = ("pod " + fp.get("build_id", "?") if fp else "") + (" + upstream" if a.upstream else "")
L = ["#!/bin/bash", "# lock.sh - build lock for the boot scripts. Sourced after registry.sh; do not execute.",
     f"# Generated {datetime.date.today()} by tools/make_lock.py from: {src.strip()}",
     "# Edit by regenerating, not by hand. LOCK_MODE (pod env): off | record (default) | enforce.",
     f'LOCK_ID="{a.lock_id}"',
     f'COMFYUI_EXPECTED="{fp.get("comfyui", "")}"',
     f'TORCH_EXPECTED="{fp.get("torch", "")}"',
     f'PIP_FREEZE_SHA256_EXPECTED="{fp.get("pip_freeze_sha256", "")}"', "",
     "declare -A NODE_LOCK"] + [f'NODE_LOCK[{k}]="{v}"' for k, v in sorted(nodes.items())] + \
    ["", "declare -A HF_REVISION"] + [f'HF_REVISION[{k}]="{v}"' for k, v in sorted(hfrev.items())] + \
    ["", "declare -A MODEL_SHA256"] + [f'MODEL_SHA256[{k}]="{v}"' for k, v in sorted(sha.items())] + [""] + \
    [f"# WARNING: {w}" for w in warn]
text = "\n".join(L) + "\n"
(open(a.out, "w").write(text) if a.out else sys.stdout.write(text))
for w in warn: print("WARNING:", w, file=sys.stderr)
print(f"lock {a.lock_id}: {len(nodes)} nodes, {len(hfrev)} HF revisions, {len(sha)} sha256, {len(warn)} warnings", file=sys.stderr)
sys.exit(2 if any("differs" in w for w in warn) else 0)
