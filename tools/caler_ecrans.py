# -*- coding: utf-8 -*-
# Recale les quadrilatères de art/cockpit.json sur le bord des vitres de art/cockpit.png.
# Chaque bord est déplacé (±R px à chaque extrémité) vers le contour le plus net, avec un cadre uniforme juste à l extérieur.
# python tools/caler_ecrans.py art/cockpit.png art/cockpit.json <sortie.json> [R=16]
# Vérifier ensuite chaque écran : sur les petits moniteurs flous, le résultat peut s accrocher au contenu dessiné.
import json, sys, numpy as np
from PIL import Image, ImageFilter
art, js, out = sys.argv[1:4]
R = int(sys.argv[4]) if len(sys.argv) > 4 else 12
im = Image.open(art).convert("RGB").filter(ImageFilter.GaussianBlur(1.0))
A = np.asarray(im).astype(np.float32)
H, W = A.shape[:2]
def samp(p):  # bilinear, p: (N,2) x,y -> (N,3)
    x = np.clip(p[:,0], 0, W-2); y = np.clip(p[:,1], 0, H-2)
    x0 = x.astype(int); y0 = y.astype(int); fx = (x-x0)[:,None]; fy = (y-y0)[:,None]
    return (A[y0,x0]*(1-fx)*(1-fy) + A[y0,x0+1]*fx*(1-fy) + A[y0+1,x0]*(1-fx)*fy + A[y0+1,x0+1]*fx*fy)
q = json.load(open(js, encoding="utf-8"))
res = {}
for k, v in q.items():
    if not isinstance(v[0], list):
        res[k] = v; continue
    P = np.array(v) * [W, H]
    ctr = P.mean(0)
    lines = []
    for i in range(4):
        a, b = P[i], P[(i+1) % 4]
        d = (b-a) / np.linalg.norm(b-a); n = np.array([-d[1], d[0]])
        if np.dot(ctr - (a+b)/2, n) < 0: n = -n   
        t = np.linspace(0.12, 0.88, 120)[:,None]
        best = (-1e9, 0, 0)
        for da in np.arange(-R, R+0.1, 0.5):
            for db in np.arange(-R, R+0.1, 0.5):
                pa = a + n*da; pb = b + n*db
                pts = pa + (pb-pa)*t
                diff = np.abs(samp(pts + n*1.5) - samp(pts - n*1.5)).sum(1)
                outs = np.stack([samp(pts - n*o) for o in (3, 4.5, 6)])   
                var = outs.std(axis=1).sum(-1).mean()
                s = np.median(diff) - 1.2 * var
                if s > best[0]: best = (s, da, db)
        lines.append((a + n*best[1], b + n*best[2]))
    def inter(l1, l2):
        p, r = l1[0], l1[1]-l1[0]; qq, s = l2[0], l2[1]-l2[0]
        t = np.cross(qq-p, s) / np.cross(r, s); return p + r*t
    C = [inter(lines[3], lines[0])] + [inter(lines[i-1], lines[i]) for i in (1, 2, 3)]
    res[k] = [[round(c[0]/W, 4), round(c[1]/H, 4)] for c in C]
    print(k, " ".join("(%.1f,%.1f)" % tuple(c - p) for c, p in zip(C, P)))
with open(out, "w", encoding="utf-8") as f:
    f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(v).replace(", ", ", ")) for k, v in res.items()) + "\n}\n")
