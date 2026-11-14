# Gera tools/tracks/laguna-seca/laguna-seca.json (formato TrackData do jogo web: points, widthLeft, widthRight)
# a partir de dados reais:
#   1) linha central: trechos highway=raceway do OpenStreetMap (3.605 m), no sentido de corrida
#   2) larguras e correção do centro: bordas do asfalto medidas na foto de satélite (Esri World Imagery, 0,25 m)
#   3) altitude: USGS 3DEP 1 m (LiDAR, terreno nu) sob o centro da pista
#   4) inclinação lateral (camber): diferença de altitude do LiDAR entre as duas bordas
# s = 0 na linha de chegada do iRacing (primeira amostra das voltas do Garage 61).
#
# Entradas (baixadas em build/laguna-seca/, não versionadas; ver download.py): osm.xml, dem1m.npy/.json,
# sat.npy/.json; e as voltas em garage61/*.csv.
# uso (de REPOS/gt3-godot): python tools/tracks/laguna-seca/build_track.py
import csv, glob, json, os, re, sys
import numpy as np
from scipy.ndimage import gaussian_filter1d, median_filter, map_coordinates

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'laguna-seca')
OUT = os.path.dirname(os.path.abspath(__file__))
LAT0, LON0 = 36.5840, -121.7530
ML = 111320.0
MO = ML * np.cos(np.radians(LAT0))
RE = 6378137.0
DS = 1.0  # espaçamento de trabalho (m)


def to_ll(x, z):
    return LAT0 - np.asarray(z) / ML, LON0 + np.asarray(x) / MO


def merc(lat, lon):
    return RE * np.radians(lon), RE * np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))


class Raster:
    def __init__(self, name):
        self.a = np.load(os.path.join(RAW, name + '.npy'))
        self.m = json.load(open(os.path.join(RAW, name + '.json')))

    def sample(self, x, z, order=1):
        lat, lon = to_ll(x, z)
        X, Y = merc(lat, lon)
        col = (X - self.m['x0']) / self.m['px'] - 0.5
        row = (self.m['y1'] - Y) / self.m['px'] - 0.5
        if self.a.ndim == 2:
            return map_coordinates(self.a, [row, col], order=order, mode='nearest')
        return np.stack([map_coordinates(self.a[..., c].astype(np.float32), [row, col], order=order, mode='nearest')
                         for c in range(self.a.shape[2])], -1)


def circ_gauss(a, sigma):
    return gaussian_filter1d(a, sigma, axis=0, mode='wrap')


def resample_loop(P, step):
    seg = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    L = s[-1]
    n = int(round(L / step))
    t = np.arange(n) * (L / n)
    Q = np.vstack([P, P[:1]])
    return np.stack([np.interp(t, s, Q[:, k]) for k in range(P.shape[1])], 1), L


def frames(P):
    T = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    T /= np.linalg.norm(T, axis=1)[:, None]
    R = np.stack([-T[:, 1], T[:, 0]], 1)  # (x, z): direita de quem corre (igual ao Track do web)
    return T, R


# ---------------------------------------------------------------- 1) linha central do OSM
xml = open(os.path.join(RAW, 'osm.xml'), encoding='utf8').read()
nodes = {m[0]: (float(m[1]), float(m[2])) for m in re.findall(r'<node id="(\d+)"[^>]*lat="([-\d.]+)" lon="([-\d.]+)"', xml)}
ways = []
pit = None
for m in re.finditer(r'<way id="(\d+)"[^>]*>([\s\S]*?)</way>', xml):
    t = dict(re.findall(r'<tag k="([^"]+)" v="([^"]*)"', m.group(2)))
    if t.get('highway') == 'raceway' and t.get('name') != 'Pit Lane':
        ways.append((t.get('name'), re.findall(r'<nd ref="(\d+)"', m.group(2))))
    elif t.get('highway') == 'raceway':
        pll = np.array([nodes[r] for r in re.findall(r'<nd ref="(\d+)"', m.group(2))])
        pit = np.stack([(pll[:, 1] - LON0) * MO, -(pll[:, 0] - LAT0) * ML], 1)
by_start = {w[1][0]: w for w in ways}
loop, names = [], []
cur = ways[0]
for _ in ways:
    loop += cur[1][:-1]
    names += [cur[0]] * (len(cur[1]) - 1)
    cur = by_start[cur[1][-1]]
assert cur is ways[0], 'trechos do OSM não fecham a volta'
ll = np.array([nodes[n] for n in loop])
P0 = np.stack([(ll[:, 1] - LON0) * MO, -(ll[:, 0] - LAT0) * ML], 1)

# sentido e linha de chegada pelas voltas do Garage 61
laps = []
for f in sorted(glob.glob(os.path.join(ROOT, 'garage61', '*.csv'))):
    rows = list(csv.DictReader(open(f)))
    la = np.array([float(r['Lat']) for r in rows]); lo = np.array([float(r['Lon']) for r in rows])
    laps.append(np.stack([(lo - LON0) * MO, -(la - LAT0) * ML], 1))
P, L = resample_loop(P0, DS)
gps = laps[0]
idx = [int(np.argmin(np.linalg.norm(P - g, axis=1))) for g in gps[::60]]
steps = np.diff(idx)
steps = (steps + len(P) // 2) % len(P) - len(P) // 2
if np.median(steps) < 0:
    P = P[::-1].copy()
start = np.mean([lap[0] for lap in laps], 0)
i0 = int(np.argmin(np.linalg.norm(P - start, axis=1)))
P = np.roll(P, -i0, 0)
print(f'OSM: {L:.1f} m, chegada em {start.round(1)}')

# ---------------------------------------------------------------- 2) bordas na foto de satélite
sat = Raster('sat')
OFF = np.arange(-15, 15.001, 0.25)


def measure(P):
    T, R = frames(P)
    n = len(P)
    X = P[:, None, 0] + R[:, None, 0] * OFF[None]
    Z = P[:, None, 1] + R[:, None, 1] * OFF[None]
    rgb = sat.sample(X.ravel(), Z.ravel()).reshape(n, len(OFF), 3)
    # o asfalto de Laguna na foto é cinza (brilho ~105–160, quase neutro); fora dele tudo é mais claro ou mais
    # amarelado: faixa branca, zebra, brita/terra bege (brilho > 170 ou R−B > 28). O brilho de referência acompanha
    # o asfalto do trecho (mediana do miolo em ±15 m), para trechos gastos/claros não virarem "fora".
    v = rgb.mean(axis=2)
    warm = rgb[..., 0] - rgb[..., 2]
    ref = median_filter(np.median(v[:, np.abs(OFF) <= 2.0], axis=1), size=31, mode='wrap')
    off = (v > np.maximum(168, ref + 28)[:, None]) | (warm > 28)
    # pit lane (asfalto colado na pista na reta e na entrada dos boxes): pontos a menos de 4 m da linha dela
    pitd = np.full(X.shape, np.inf)
    for a, b in zip(pit[:-1], pit[1:]):
        dd = b - a
        t = np.clip(((X - a[0]) * dd[0] + (Z - a[1]) * dd[1]) / (dd @ dd), 0, 1)
        pitd = np.minimum(pitd, np.hypot(X - a[0] - dd[0] * t, Z - a[1] - dd[1] * t))
    off |= pitd < 4.0
    # ao longo da pista (±2 m): tira carros, marcas e sombras soltas
    bad = median_filter(off.astype(np.uint8), size=(5, 1), mode='wrap') > 0
    edges = np.full((n, 2), np.nan)
    c = len(OFF) // 2
    for side, rng in ((0, range(c, -1, -1)), (1, range(c, len(OFF)))):
        for i in range(n):
            run = 0
            for k in rng:
                run = run + 1 if bad[i, k] else 0
                if run >= 4:  # 1 m seguido fora do asfalto
                    # começo do trecho claro = faixa branca, pintada por dentro da borda (~0,35 m)
                    kk = k + 3 if side == 0 else k - 3
                    edges[i, side] = abs(OFF[kk]) + 0.35
                    break
    return edges, ref


# a linha do OSM é um polígono com vértices espaçados: os "cotovelos" viram curvas fechadas demais (a T6 saía com
# raio de 31 m onde o iRacing passa a 176 km/h). Suaviza (σ = 6 m) e deixa a foto recentralizar a cada passo.
P = circ_gauss(P, 6)
for it in range(5):
    edges, ref = measure(P)
    ok = np.all(np.isfinite(edges), 1) & (edges.sum(1) > 9) & (edges.sum(1) < 22)
    e = edges.copy()
    for k in range(2):
        good = np.where(ok)[0]
        e[:, k] = np.interp(np.arange(len(P)), good, e[good, k], period=len(P))
    e = median_filter(e, size=(25, 1), mode='wrap')
    shift = circ_gauss((e[:, 1] - e[:, 0]) / 2, 12)
    _, R = frames(P)
    P = P + R * np.clip(shift, -5, 5)[:, None]
    P, L = resample_loop(P, DS)
    P = circ_gauss(P, 5)
    print(f'iteração {it}: válidas {ok.mean() * 100:.0f}%, desvio do centro med {np.median(np.abs(shift)):.2f} m '
          f'max {np.abs(shift).max():.2f} m, volta {L:.1f} m')
# número de amostras múltiplo de 4 (a saída pega 1 a cada 4): o último trecho da volta fica igual aos outros
L = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1).sum()
P, L = resample_loop(P, L / (4 * round(L / 4)))
edges, ref = measure(P)
ok = np.all(np.isfinite(edges), 1) & (edges.sum(1) > 9) & (edges.sum(1) < 22)
W = edges.copy()
for k in range(2):
    good = np.where(ok)[0]
    W[:, k] = np.interp(np.arange(len(P)), good, W[good, k], period=len(P))
# escapes asfaltados e sombras só "alargam" a pista: percentil baixo numa janela de ±20 m
from scipy.ndimage import percentile_filter
W = circ_gauss(percentile_filter(W, 30, size=(41, 1), mode='wrap'), 6)
W = np.clip(W, 4.5, 8.5)
print(f'largura total: med {np.median(W.sum(1)):.1f} m, p10 {np.percentile(W.sum(1), 10):.1f}, '
      f'p90 {np.percentile(W.sum(1), 90):.1f}, medidas válidas {ok.mean() * 100:.0f}%')

# conferência: o carro das voltas do iRacing (centro ±1 m) tem que caber entre as bordas (+ zebra ~1,2 m)
T, R = frames(P)
for lap in laps:
    j = np.array([int(np.argmin(np.linalg.norm(P - q, axis=1))) for q in lap[::3]])
    dlat = ((lap[::3] - P[j]) * R[j]).sum(1)
    outL = -dlat - 1.0 - W[j, 0]
    outR = dlat - 1.0 - W[j, 1]
    o = np.maximum(outL, outR)
    print(f'  volta: lateral {dlat.min():+.1f}..{dlat.max():+.1f} m; fora da borda > 1,2 m em {np.mean(o > 1.2) * 100:.1f}% '
          f'(pior {o.max():.1f} m em s={j[np.argmax(o)] * DS:.0f})')

# ---------------------------------------------------------------- 3) altitude e 4) camber pelo LiDAR
dem = Raster('dem1m')
T, R = frames(P)
y = dem.sample(P[:, 0], P[:, 1])
# pontes sobre a pista não estão no terreno nu; picos isolados viram mediana
y = median_filter(y, size=9, mode='wrap')
y = circ_gauss(y, 4)
# camber: LiDAR a ±3,5 m do centro (sempre sobre o asfalto; nas bordas o LiDAR pega muro/zebra/valeta). O
# abaulamento simétrico do asfalto se cancela. + = lado direito mais alto.
HB = 3.5
hl = dem.sample(P[:, 0] - R[:, 0] * HB, P[:, 1] - R[:, 1] * HB)
hr = dem.sample(P[:, 0] + R[:, 0] * HB, P[:, 1] + R[:, 1] * HB)
bank = circ_gauss(np.arctan2(median_filter(hr - hl, size=15, mode="wrap"), 2 * HB), 10)
ymin = y.min()
print(f'altitude {ymin:.1f}..{y.max():.1f} m (desnível {y.max() - ymin:.1f} m); camber med '
      f'{np.degrees(np.median(np.abs(bank))):.1f}°, max {np.degrees(np.abs(bank).max()):.1f}°')

# ---------------------------------------------------------------- saída (pontos a cada 4 m, como o TUMFTM de Interlagos)
k = 4
out = {
    'name': 'Laguna Seca',
    'source': 'OpenStreetMap (ODbL) + Esri World Imagery (larguras) + USGS 3DEP 1 m (altitude e camber)',
    'origin': {'lat': LAT0, 'lon': LON0},
    'points': [[round(float(P[i, 0]), 3), round(float(y[i] - ymin), 3), round(float(P[i, 1]), 3)] for i in range(0, len(P), k)],
    'widthLeft': [round(float(W[i, 0]), 2) for i in range(0, len(P), k)],
    'widthRight': [round(float(W[i, 1]), 2) for i in range(0, len(P), k)],
    # inclinação lateral (rad, + = lado direito mais alto), uma por ponto
    'bank': [round(float(bank[i]), 4) for i in range(0, len(P), k)],
    # escape asfaltado (faixa verde do LMU) de no máximo 2,5 m atrás da zebra; depois, brita (tools/tracks/bank.ts)
    'maxRunoff': 2.5,
    # trechos com nome (s em m a partir da linha de chegada), pelos ápices medidos na curvatura desta linha:
    # T1 202, Andretti 499, T3 756, T4 1048, T5 1505, T6 1936, T8/8A 2453/2493, Rainey 2636–2750, T10 2997, T11 3268
    'sections': [
        {'name': 'Curva 1', 's0': 150, 's1': 330},
        {'name': 'Andretti Hairpin', 's0': 330, 's1': 640},
        {'name': 'Curva 3', 's0': 640, 's1': 900},
        {'name': 'Curva 4', 's0': 900, 's1': 1300},
        {'name': 'Curva 5', 's0': 1300, 's1': 1720},
        {'name': 'Curva 6', 's0': 1720, 's1': 2010},
        {'name': 'Rahal Straight', 's0': 2010, 's1': 2400},
        {'name': 'Corkscrew', 's0': 2400, 's1': 2560},
        {'name': 'Rainey Curve', 's0': 2560, 's1': 2860},
        {'name': 'Curva 10', 's0': 2860, 's1': 3130},
        {'name': 'Curva 11', 's0': 3130, 's1': 3330},
        {'name': 'Reta dos boxes', 's0': 3330, 's1': 150},
    ],
}
json.dump(out, open(os.path.join(OUT, 'laguna-seca.json'), 'w'))
# grade de relevo (mesmo formato de interlagos-terrain.json do web: altitude absoluta, linha j = z0 + j*step):
# LiDAR 1 m em média por célula de 8 m, cobrindo todo o recorte baixado (~1 km além da pista)
STEP_T = 8.0
lat_a, lat_b = 36.5700 + 0.0005, 36.5980 - 0.0005
lon_a, lon_b = -121.7700 + 0.0005, -121.7370 - 0.0005
x0, x1 = (lon_a - LON0) * MO, (lon_b - LON0) * MO
z0, z1 = -(lat_b - LAT0) * ML, -(lat_a - LAT0) * ML
nx, nz = int((x1 - x0) // STEP_T) + 1, int((z1 - z0) // STEP_T) + 1
gx, gz = np.meshgrid(x0 + np.arange(nx) * STEP_T, z0 + np.arange(nz) * STEP_T)
acc = np.zeros(gx.shape)
for dx in (-3, -1, 1, 3):
    for dz in (-3, -1, 1, 3):
        acc += dem.sample((gx + dx).ravel(), (gz + dz).ravel()).reshape(gx.shape)
acc /= 16
json.dump({'x0': round(float(x0), 2), 'z0': round(float(z0), 2), 'step': STEP_T, 'nx': nx, 'nz': nz,
           'h': [round(float(v), 1) for v in acc.ravel()]},
          open(os.path.join(OUT, 'laguna-seca-terrain.json'), 'w'))
print(f'relevo {nx}x{nz} células de {STEP_T:.0f} m')
np.savez(os.path.join(RAW, 'diag.npz'), P=P, W=W, y=y, bank=bank, edges=edges, ok=ok)
print('gravado', os.path.join(OUT, 'laguna-seca.json'), len(out['points']), 'pontos')
