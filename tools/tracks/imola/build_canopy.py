# Detecta posição e altura reais das copas de árvores em volta de Imola usando LiDAR DSM - DTM
# (DsmAgea2008 - Dtm1x1PST) + matas/fileiras do OSM, excluindo pista, brita, prédios, paddock,
# rio Santerno e arquibancadas abertas (Tosa / Rivazza).
# Saída: tools/tracks/imola/imola-canopy.json  ([x, z, scale] * N)
# uso (de REPOS/gt3-godot, depois de tools/pista.ts -- imola): python tools/tracks/imola/build_canopy.py
import json
import os
import numpy as np
from scipy.ndimage import map_coordinates

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'imola')
OUT = os.path.dirname(os.path.abspath(__file__))
LAT0, LON0 = 44.3410, 11.7135
ML = 111320.0
MO = ML * np.cos(np.radians(LAT0))
RE = 6378137.0


class Raster:
    def __init__(self, name: str):
        self.a = np.load(os.path.join(RAW, name + '.npy'))
        self.m = json.load(open(os.path.join(RAW, name + '.json')))

    def sample(self, x, z, order=1):
        lat = LAT0 - np.asarray(z) / ML
        lon = LON0 + np.asarray(x) / MO
        X = RE * np.radians(lon)
        Y = RE * np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))
        col = (X - self.m['x0']) / self.m['px'] - 0.5
        row = (self.m['y1'] - Y) / self.m['px'] - 0.5
        return map_coordinates(self.a, [row, col], order=order, mode='nearest')


def in_polys_mask(xs, zs, polys, pad=0.0):
    mask = np.zeros(xs.shape, dtype=bool)
    for poly in polys:
        p = np.asarray(poly, dtype=np.float64)
        x0, x1 = p[:, 0].min() - pad, p[:, 0].max() + pad
        z0, z1 = p[:, 1].min() - pad, p[:, 1].max() + pad
        cand = (xs >= x0) & (xs <= x1) & (zs >= z0) & (zs <= z1)
        if not cand.any():
            continue
        cx, cz = xs[cand], zs[cand]
        c = np.zeros(cx.shape, dtype=bool)
        m = len(p)
        for i in range(m):
            j = (i - 1) % m
            xi, zi = p[i, 0], p[i, 1]
            xj, zj = p[j, 0], p[j, 1]
            c ^= ((zi > cz) != (zj > cz)) & (cx < ((xj - xi) * (cz - zi)) / (zj - zi + 1e-12) + xi)
        mask[cand] |= c
    return mask


t = json.load(open(os.path.join(ROOT, 'data', 'tracks', 'imola', 'track.json')))
osm = json.load(open(os.path.join(OUT, 'imola-osm.json')))
n = t['n']
S = np.array(t['s']).reshape(n, 16)
P = S[:, [0, 2]]
R = S[:, [6, 7]]
wl, wr, Wl, Wr = S[:, 8], S[:, 9], S[:, 14], S[:, 15]

dem = Raster('dem1m')
dsm = Raster('dsm2m')
chm_offset = float(np.median(dsm.sample(P[:, 0], P[:, 1]) - dem.sample(P[:, 0], P[:, 1])))

xmin, xmax = P[:, 0].min() - 280.0, P[:, 0].max() + 280.0
zmin, zmax = P[:, 1].min() - 280.0, P[:, 1].max() + 280.0

rng = np.random.default_rng(2026)
step = 8.5
gx = np.arange(xmin, xmax, step)
gz = np.arange(zmin, zmax, step)
XX, ZZ = np.meshgrid(gx, gz)
xs = (XX.ravel() + rng.uniform(-step * 0.42, step * 0.42, XX.size)).astype(np.float64)
zs = (ZZ.ravel() + rng.uniform(-step * 0.42, step * 0.42, ZZ.size)).astype(np.float64)

# Distância mínima até a pista
P_sub = P[::2]
Wl_sub = Wl[::2]
Wr_sub = Wr[::2]
R_sub = R[::2]

keep = np.ones(len(xs), dtype=bool)
nearest_d = np.full(len(xs), np.inf)
for k0 in range(0, len(xs), 4000):
    bx = xs[k0:k0 + 4000, None]
    bz = zs[k0:k0 + 4000, None]
    dx = bx - P_sub[None, :, 0]
    dz = bz - P_sub[None, :, 1]
    d2 = dx * dx + dz * dz
    bi = np.argmin(d2, axis=1)
    d = np.sqrt(d2[np.arange(len(bi)), bi])
    nearest_d[k0:k0 + 4000] = d
    lat = dx[np.arange(len(bi)), bi] * R_sub[bi, 0] + dz[np.arange(len(bi)), bi] * R_sub[bi, 1]
    wall = np.where(lat < 0, Wl_sub[bi], Wr_sub[bi])
    # folga de 6 m atrás do muro, máximo 280 m da pista
    keep[k0:k0 + 4000] = (np.abs(lat) > wall + 6.0) & (d < 280.0)

xs = xs[keep]
zs = zs[keep]
nearest_d = nearest_d[keep]

# Exclusões do OSM (prédios, água, brita, paddock/estacionamentos, pistas de boxes)
bpolys = [b['pts'] for b in osm.get('buildings', [])]
excl = (
    in_polys_mask(xs, zs, bpolys, pad=3.5)
    | in_polys_mask(xs, zs, osm.get('water', []), pad=2.0)
    | in_polys_mask(xs, zs, osm.get('gravel', []), pad=2.0)
    | in_polys_mask(xs, zs, osm.get('paved', []), pad=1.5)
)
# Excluir corredor da pit lane e dos boxes (à direita na reta principal e Traguardo)
for line in osm.get('pitLane', []):
    arr = np.asarray(line)
    for k in range(len(arr) - 1):
        ax, az = arr[k]
        bx, bz = arr[k + 1]
        ddx, ddz = bx - ax, bz - az
        l2 = ddx * ddx + ddz * ddz + 1e-9
        u = np.clip(((xs - ax) * ddx + (zs - az) * ddz) / l2, 0.0, 1.0)
        excl |= np.hypot(xs - ax - ddx * u, zs - az - ddz * u) < 28.0

xs = xs[~excl]
zs = zs[~excl]

# Medir DSM - DTM (altura da copa) e filtrar também manchas de mata do OSM
chm = dsm.sample(xs, zs) - dem.sample(xs, zs) - chm_offset
in_wood = in_polys_mask(xs, zs, osm.get('woods', []))

# Aceita onde DSM - DTM indica copa >= 3,2 m (até 26 m) ou mata densa do OSM com chm >= 1,5 m
tree_ok = ((chm >= 3.2) & (chm <= 26.0)) | (in_wood & (chm >= 1.5))
xs = xs[tree_ok]
zs = zs[tree_ok]
chm = np.clip(chm[tree_ok], 4.5, 22.0)

# Converter altura real (m) em escala do atlas (altura média base ~4.1 m)
scales = np.clip(chm / 4.1, 1.2, 4.8)

# Adicionar fileiras reais de árvores do OSM (natural=tree_row)
extra_x, extra_z, extra_s = [], [], []
for line in osm.get('treeRows', []):
    arr = np.asarray(line)
    for a, b in zip(arr[:-1], arr[1:]):
        dist = np.hypot(b[0] - a[0], b[1] - a[1])
        cnt = max(1, int(round(dist / 8.0)))
        for k in range(cnt):
            u = k / cnt
            tx = float(a[0] + (b[0] - a[0]) * u)
            tz = float(a[1] + (b[1] - a[1]) * u)
            # verifica distância ao traçado
            d2 = (P_sub[:, 0] - tx) ** 2 + (P_sub[:, 1] - tz) ** 2
            bi = int(np.argmin(d2))
            if np.sqrt(d2[bi]) < 280.0:
                lat = (tx - P_sub[bi, 0]) * R_sub[bi, 0] + (tz - P_sub[bi, 1]) * R_sub[bi, 1]
                wall = Wl_sub[bi] if lat < 0 else Wr_sub[bi]
                if abs(lat) > wall + 5.5:
                    h = float(dsm.sample([tx], [tz])[0] - dem.sample([tx], [tz])[0] - chm_offset)
                    extra_x.append(tx)
                    extra_z.append(tz)
                    extra_s.append(float(np.clip(max(h, 8.0) / 4.1, 1.8, 4.5)))

all_x = np.concatenate([xs, np.array(extra_x, dtype=np.float64)])
all_z = np.concatenate([zs, np.array(extra_z, dtype=np.float64)])
all_s = np.concatenate([scales, np.array(extra_s, dtype=np.float64)])

# Limitar a 5.500 árvores para orçamento mobile leve
MAX_TREES = 5500
if len(all_x) > MAX_TREES:
    sel = rng.choice(len(all_x), size=MAX_TREES, replace=False)
    all_x, all_z, all_s = all_x[sel], all_z[sel], all_s[sel]

flat = []
for x, z, sc in zip(all_x, all_z, all_s):
    flat.extend([round(float(x), 1), round(float(z), 1), round(float(sc), 2)])

json.dump(flat, open(os.path.join(OUT, 'imola-canopy.json'), 'w'))
print(f'imola-canopy.json: {len(all_x)} árvores (escala med {np.median(all_s):.2f}, p90 {np.percentile(all_s, 90):.2f})')
