#!/usr/bin/env python3
"""compare.py - analyse a results folder from comfy_queue.py (or any folder of PNGs).

Runs anywhere with Pillow + numpy: the pod (ComfyUI's python has both) or a local machine.

    python3 compare.py RESULTS_DIR                       # metrics + labelled contact sheet
    python3 compare.py RESULTS_DIR --crop 300,620,700,1020 [--crop-name chest]
    python3 compare.py RESULTS_DIR --ref upright_natural  # list every image against one label
    python3 compare.py RESULTS_DIR --include upright      # only labels containing a substring

RESULTS_DIR is the runner's output subfolder (e.g. output/hmb_shape) holding index.jsonl.
Without an index, every *.png in the folder is used and labelled by filename.

Writes RESULTS_DIR/compare/:
  metrics.json  - per image: label, file, seed, sampler, embedded-prompt check; pairwise mean
                  absolute pixel difference (0-255 scale, full resolution)
  matrix.txt    - the pairwise matrix, readable
  sheet.jpg     - labelled contact sheet of the whole frames
  <name>.jpg    - labelled sheet of the same crop box from every image (with --crop)

Calibration (pod 5f83f51b72ed, 2026-10-23, 1184x1776): identical job 0.000; one prompt word
changed within one scene ~2-9; a different scene ~12-21. Pairs at or above --scene-threshold
(default 12) are flagged as probable scene changes - compare those by eye, not by number.
"""
import argparse
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def png_prompt_text(path):
    """Return the positive text recorded in a ComfyUI PNG, or None."""
    try:
        data = open(path, "rb").read()
        pos, txt = 8, {}
        while pos < len(data):
            n, t = struct.unpack(">I4s", data[pos:pos + 8])
            body = data[pos + 8:pos + 8 + n]
            pos += 12 + n
            if t == b"tEXt":
                k, v = body.split(b"\0", 1)
                txt[k.decode()] = v.decode("latin1")
        graph = json.loads(txt["prompt"])
        for node in graph.values():
            if node.get("class_type") == "KreaTwoStageSampler":
                pos_id = str(node["inputs"]["positive"][0])
                t = graph[pos_id]["inputs"].get("text")
                return t if isinstance(t, str) else None
    except Exception:
        return None
    return None


def load_items(results_dir, include):
    idx_path = os.path.join(results_dir, "index.jsonl")
    items = []
    if os.path.exists(idx_path):
        parent = os.path.dirname(os.path.abspath(results_dir))
        for line in open(idx_path):
            d = json.loads(line)
            if d.get("warmup"):
                continue
            for f in d.get("files", []):
                cands = [os.path.join(parent, f), os.path.join(results_dir, os.path.basename(f))]
                path = next((c for c in cands if os.path.exists(c)), None)
                if path:
                    items.append({"label": d["label"], "file": path, "seed": d.get("seed"),
                                  "sampler": d.get("sampler"), "prompt": d.get("prompt")})
    else:
        for f in sorted(os.listdir(results_dir)):
            if f.lower().endswith(".png"):
                items.append({"label": os.path.splitext(f)[0], "file": os.path.join(results_dir, f)})
    if include:
        items = [i for i in items if include in i["label"]]
    if not items:
        sys.exit("no images found")
    return items


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/Library/Fonts/Arial Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def sheet(images, labels, tile_w, out, cols=4):
    w0, h0 = images[0].size
    tile_h = int(tile_w * h0 / w0)
    rows = (len(images) + cols - 1) // cols
    bar = 30
    s = Image.new("RGB", (cols * tile_w, rows * (tile_h + bar)), "white")
    d, f = ImageDraw.Draw(s), font(18)
    for k, (im, lab) in enumerate(zip(images, labels)):
        x, y = (k % cols) * tile_w, (k // cols) * (tile_h + bar)
        s.paste(im.resize((tile_w, tile_h)), (x, y + bar))
        d.text((x + 6, y + 5), lab[:48], fill="black", font=f)
    s.save(out, quality=88)


def main():
    ap = argparse.ArgumentParser(description="Pixel-diff matrix and contact sheets for a results folder.")
    ap.add_argument("results_dir")
    ap.add_argument("--crop", help="x0,y0,x1,y1 in full-resolution pixels")
    ap.add_argument("--crop-name", default="crops")
    ap.add_argument("--ref", help="label to compare every image against")
    ap.add_argument("--include", help="only labels containing this substring")
    ap.add_argument("--scene-threshold", type=float, default=12.0)
    ap.add_argument("--tile", type=int, default=400, help="contact-sheet tile width")
    a = ap.parse_args()

    items = load_items(a.results_dir, a.include)
    out_dir = os.path.join(a.results_dir, "compare")
    os.makedirs(out_dir, exist_ok=True)

    imgs = [Image.open(i["file"]).convert("RGB") for i in items]
    sizes = {im.size for im in imgs}
    arrs = [np.asarray(im, dtype=np.int16) for im in imgs] if len(sizes) == 1 else None
    for i in items:
        embedded = png_prompt_text(i["file"])
        i["prompt_check"] = ("no index prompt" if i.get("prompt") is None else
                             "missing in PNG" if embedded is None else
                             "match" if " ".join(embedded.split()) == i["prompt"] else "MISMATCH")
        i.pop("prompt", None)

    labels = [i["label"] for i in items]
    n = len(items)
    matrix = None
    if arrs is not None:
        matrix = [[round(float(np.abs(arrs[r] - arrs[c]).mean()), 3) for c in range(n)] for r in range(n)]
    else:
        print(f"WARNING: images differ in size {sizes}; no pixel matrix")

    lines = []
    if matrix:
        w = max(len(l) for l in labels)
        lines.append(" " * (w + 2) + " ".join(f"{k:>6d}" for k in range(n)))
        for r in range(n):
            lines.append(f"{labels[r]:<{w}} {r:>1d} " + " ".join(f"{matrix[r][c]:6.2f}" for c in range(n)))
        lines.append("")
        flagged = [(labels[r], labels[c], matrix[r][c]) for r in range(n) for c in range(r + 1, n)
                   if matrix[r][c] >= a.scene_threshold]
        lines.append(f"probable scene changes (>= {a.scene_threshold}): " +
                     ("none" if not flagged else "; ".join(f"{x} / {y} {v:.1f}" for x, y, v in flagged)))
        if a.ref:
            if a.ref not in labels:
                sys.exit(f"--ref {a.ref} not among labels")
            r = labels.index(a.ref)
            lines.append(f"against {a.ref}:")
            lines += [f"  {labels[c]:<{w}} {matrix[r][c]:7.3f}" for c in range(n) if c != r]
    bad = [i["label"] for i in items if i["prompt_check"] == "MISMATCH"]
    lines.append("embedded prompt check: " + ("all match" if not bad and all(
        i["prompt_check"] == "match" for i in items) else
        f"mismatch: {bad}" if bad else "not available for some images"))
    text = "\n".join(lines)
    print(text)
    open(os.path.join(out_dir, "matrix.txt"), "w").write(text + "\n")
    json.dump({"items": items, "labels": labels, "matrix": matrix,
               "scene_threshold": a.scene_threshold}, open(os.path.join(out_dir, "metrics.json"), "w"), indent=1)

    sheet(imgs, labels, a.tile, os.path.join(out_dir, "sheet.jpg"))
    if a.crop:
        box = tuple(int(v) for v in a.crop.split(","))
        sheet([im.crop(box) for im in imgs], labels, a.tile, os.path.join(out_dir, f"{a.crop_name}.jpg"))
    print(f"written: {out_dir}")


if __name__ == "__main__":
    main()
