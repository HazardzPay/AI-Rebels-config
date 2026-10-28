"""Face diversity by ArcFace (insightface buffalo_l w600k_r50).
usage: python3 arcface_div.py IMAGE_DIR GROUP_REGEX [ID_REGEX]
GROUP_REGEX: regex with one group on the file name giving the group (phase/setting).
ID_REGEX (optional): regex group giving the person id, for same-person-across-groups similarity.
Reports per group: mean, min, max pairwise cosine similarity between different people (lower = more diverse),
and the most similar pairs."""
import sys, re, glob, os, itertools, json
import numpy as np, cv2
from insightface.app import FaceAnalysis
d, greg = sys.argv[1], re.compile(sys.argv[2]); ireg = re.compile(sys.argv[3]) if len(sys.argv) > 3 else None
app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'], allowed_modules=['detection', 'recognition'])
app.prepare(ctx_id=-1, det_size=(640, 640))
emb = {}
for f in sorted(glob.glob(os.path.join(d, '**', '*.*'), recursive=True)):
    if not f.lower().endswith(('.png', '.jpg', '.jpeg')): continue
    faces = app.get(cv2.imread(f))
    if not faces: print('NO FACE', f); continue
    fc = max(faces, key=lambda x: (x.bbox[2]-x.bbox[0])*(x.bbox[3]-x.bbox[1]))
    emb[os.path.basename(f)] = (fc.normed_embedding, float(fc.det_score), float(fc.bbox[2]-fc.bbox[0]))
groups = {}
for n in emb:
    m = greg.search(n)
    if m: groups.setdefault(m.group(1), []).append(n)
out = {}
for g, names in sorted(groups.items()):
    sims = [(float(np.dot(emb[a][0], emb[b][0])), a, b) for a, b in itertools.combinations(sorted(names), 2)]
    s = np.array([x[0] for x in sims])
    fw = np.mean([emb[n][2] for n in names])
    print(f'{g}: n={len(names)} pairs={len(s)} mean sim {s.mean():.3f} (sd {s.std():.3f}) min {s.min():.3f} max {s.max():.3f} | face width px {fw:.0f}')
    for v, a, b in sorted(sims, reverse=True)[:3]: print(f'    most similar {v:.3f} {a} {b}')
    out[g] = {'n': len(names), 'mean': float(s.mean()), 'sd': float(s.std()), 'min': float(s.min()), 'max': float(s.max())}
if ireg:
    ids = {}
    for n in emb:
        m, g = ireg.search(n), greg.search(n)
        if m and g: ids.setdefault(m.group(1), {})[g.group(1)] = n
    gs = sorted(groups)
    print('same person across groups (mean cosine sim):')
    for a, b in itertools.combinations(gs, 2):
        v = [float(np.dot(emb[p[a]][0], emb[p[b]][0])) for p in ids.values() if a in p and b in p]
        if v: print(f'  {a} vs {b}: {np.mean(v):.3f} (n={len(v)})')
json.dump(out, open(os.path.join(d, 'arcface_div.json'), 'w'), indent=1)
