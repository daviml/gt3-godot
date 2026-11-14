# O que há entre a borda da pista (+ zebra + escape pintado) e o muro, de cada lado, em cada amostra de
# data/tracks/laguna-seca/track.json: fração de areia/brita bege (vs. mato/árvore/sombra) medida na foto de
# satélite. O cenário (tools/cenario/laguna/trackView.ts) pinta brita onde a fração passa de 0,5.
# Saída: tools/tracks/laguna-seca/laguna-seca-surfaces.json  { n, sandL: [0..1] × n, sandR: [0..1] × n }
# uso (de REPOS/gt3-godot, depois do tools/pista.ts): python tools/tracks/laguna-seca/build_surfaces.py
import json, os
import numpy as np
from scipy.ndimage import gaussian_filter1d, map_coordinates

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'laguna-seca')
OUT = os.path.dirname(os.path.abspath(__file__))
LAT0, LON0 = 36.5840, -121.7530
ML = 111320.0
MO = ML * np.cos(np.radians(LAT0))
RE = 6378137.0

t = json.load(open(os.path.join(ROOT, 'data', 'tracks', 'laguna-seca', 'track.json')))
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


out = {'n': n}
for side, key, w, k, r, wall in ((-1, 'sandL', wl, kl, rl, Wl), (1, 'sandR', wr, kr, rr, Wr)):
    # todos os pontos de uma vez: 0,5 m de passo entre o escape e o muro, 3 linhas ao longo (±1,5 m)
    d = np.arange(0.0, 40.0, 0.5)
    a = (w + k + r + 0.5)[:, None] + d[None]
    ok = a < (wall - 0.5)[:, None]
    fr = np.zeros(n)
    cnt = np.zeros(n)
    for al in (-1.5, 0.0, 1.5):
        x = P[:, 0, None] + side * R[:, 0, None] * a + T[:, 0, None] * al
        z = P[:, 1, None] + side * R[:, 1, None] * a + T[:, 1, None] * al
        c = rgb_at(x.ravel(), z.ravel()).reshape(n, len(d), 3)
        v = c.mean(2)
        warm = c[..., 0] - c[..., 2]
        # areia/brita/terra: clara e amarelada; mato verde, árvore e sombra: escuros ou esverdeados
        sand = (v > 140) & (warm > 12) & (c[..., 1] <= c[..., 0] + 4)
        fr += (sand & ok).sum(1)
        cnt += ok.sum(1)
    frac = np.where(cnt > 0, fr / np.maximum(cnt, 1), 1.0)
    out[key] = [round(float(f), 2) for f in gaussian_filter1d(frac, 3, mode='wrap')]
json.dump(out, open(os.path.join(OUT, 'laguna-seca-surfaces.json'), 'w'))
for key in ('sandL', 'sandR'):
    a = np.array(out[key])
    print(f'{key}: brita em {np.mean(a > 0.5) * 100:.0f}% da volta')
