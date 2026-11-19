# Classifica o que há entre a borda da pista (+ zebra + escape pintado) e o muro em cada amostra de
# data/tracks/imola/track.json: fração de brita/cascalho claro (vs. grama/mato/asfalto) combinando
# foto de satélite 0,25 m + polígonos natural=sand/surface=gravel do OSM.
# Saída: tools/tracks/imola/imola-surfaces.json  { n, sandL: [0..1] × n, sandR: [0..1] × n }
# uso (de REPOS/gt3-godot, depois do tools/pista.ts -- imola): python tools/tracks/imola/build_surfaces.py
import json
import os
import numpy as np
from scipy.ndimage import gaussian_filter1d, map_coordinates

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'imola')
OUT = os.path.dirname(os.path.abspath(__file__))
LAT0, LON0 = 44.3410, 11.7135
ML = 111320.0
MO = ML * np.cos(np.radians(LAT0))
RE = 6378137.0

t = json.load(open(os.path.join(ROOT, 'data', 'tracks', 'imola', 'track.json')))
osm = json.load(open(os.path.join(OUT, 'imola-osm.json')))
n = t['n']
S = np.array(t['s']).reshape(n, 16)
P = S[:, [0, 2]]
R = S[:, [6, 7]]
T = S[:, [3, 5]] / np.linalg.norm(S[:, [3, 5]], axis=1)[:, None]
wl, wr, kl, kr, rl, rr, Wl, Wr = (S[:, k] for k in range(8, 16))

sat = np.load(os.path.join(RAW, 'sat.npy'))
chans = [sat[..., c].astype(np.float32) for c in range(3)]
meta = json.load(open(os.path.join(RAW, 'sat.json')))


def rgb_at(x, z):
    lat = LAT0 - z / ML
    lon = LON0 + x / MO
    X = RE * np.radians(lon)
    Y = RE * np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))
    col = (X - meta['x0']) / meta['px'] - 0.5
    row = (meta['y1'] - Y) / meta['px'] - 0.5
    return np.stack([map_coordinates(ch, [row, col], order=1, mode='nearest') for ch in chans], -1)


def in_any_poly(x_arr, z_arr, polys):
    inside = np.zeros(x_arr.shape, dtype=bool)
    for poly in polys:
        p = np.asarray(poly)
        x0, x1 = p[:, 0].min(), p[:, 0].max()
        z0, z1 = p[:, 1].min(), p[:, 1].max()
        cand = (x_arr >= x0) & (x_arr <= x1) & (z_arr >= z0) & (z_arr <= z1)
        if not cand.any():
            continue
        xs = x_arr[cand]
        zs = z_arr[cand]
        c = np.zeros(xs.shape, dtype=bool)
        m = len(p)
        for i in range(m):
            j = (i - 1) % m
            xi, zi = p[i, 0], p[i, 1]
            xj, zj = p[j, 0], p[j, 1]
            hit = ((zi > zs) != (zj > zs)) & (xs < ((xj - xi) * (zs - zi)) / (zj - zi + 1e-12) + xi)
            c ^= hit
        inside[cand] |= c
    return inside


gravel_polys = osm.get('gravel', [])
out = {'n': n}
for side, key, w, k, r, wall in ((-1, 'sandL', wl, kl, rl, Wl), (1, 'sandR', wr, kr, rr, Wr)):
    d = np.arange(0.0, 26.0, 0.5)
    a = (w + k + r + 0.5)[:, None] + d[None]
    ok = a < (wall - 0.3)[:, None]
    fr = np.zeros(n)
    cnt = np.zeros(n)
    for al in (-1.5, 0.0, 1.5):
        x = P[:, 0, None] + side * R[:, 0, None] * a + T[:, 0, None] * al
        z = P[:, 1, None] + side * R[:, 1, None] * a + T[:, 1, None] * al
        c = rgb_at(x.ravel(), z.ravel()).reshape(n, len(d), 3)
        v = c.mean(2)
        warm = c[..., 0] - c[..., 2]
        # brita clara cinza-bege de Imola: clara (v > 138), levemente quente (warm > 8) e sem ser grama verde (G - R <= 6)
        sand_sat = (v > 138.0) & (warm > 8.0) & ((c[..., 1] - c[..., 0]) <= 6.0)
        sand_osm = in_any_poly(x.ravel(), z.ravel(), gravel_polys).reshape(n, len(d))
        sand = sand_sat | sand_osm
        fr += (sand & ok).sum(1)
        cnt += ok.sum(1)
    frac = np.where(cnt > 0, fr / np.maximum(cnt, 1), 0.0)
    out[key] = [round(float(f), 2) for f in gaussian_filter1d(frac, 2.5, mode='wrap')]

json.dump(out, open(os.path.join(OUT, 'imola-surfaces.json'), 'w'))
for key in ('sandL', 'sandR'):
    a = np.array(out[key])
    print(f'{key}: brita em {np.mean(a > 0.4) * 100:.0f}% da volta')
