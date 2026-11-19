# Gera tools/tracks/imola/imola.json (TrackData + bank + wallLeft/Right + kerbLeft/Right + sections)
# e tools/tracks/imola/imola-terrain.json a partir de dados reais:
#   1) linha central: 32 trechos highway=raceway do OSM (4.910 m, sentido anti-horário), excluindo Pit Lane e Variante Bassa
#   2) sentido e linha de chegada s=0: alinhamento ótimo das 3 voltas do Garage 61 (*Enzo*.csv)
#   3) larguras e correção do centro: bordas do asfalto medidas na foto de satélite 0,25 m (Esri World Imagery)
#   4) zebras: detecção de vermelho/branco no satélite na faixa logo após wl/wr
#   5) muros: distâncias reais de barrier=wall/fence do OSM (+ folga de caixas de brita)
#   6) altitude e camber: LiDAR 1 m Emilia-Romagna (Dtm1x1PST + Dtm5x5) sob o centro e a ±3,5 m
# uso (de REPOS/gt3-godot): python tools/tracks/imola/build_track.py
import csv
import glob
import json
import os
import re
import numpy as np
from scipy.ndimage import gaussian_filter1d, map_coordinates, median_filter, percentile_filter
from scipy.optimize import minimize

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'imola')
OUT = os.path.dirname(os.path.abspath(__file__))
LAT0, LON0 = 44.3410, 11.7135
ML = 111320.0
MO = ML * np.cos(np.radians(LAT0))
RE = 6378137.0
DS = 1.0  # espaçamento de trabalho (m)


def to_ll(x, z):
    return LAT0 - np.asarray(z) / ML, LON0 + np.asarray(x) / MO


def merc(lat, lon):
    return RE * np.radians(lon), RE * np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))


class Raster:
    def __init__(self, name: str):
        self.a = np.load(os.path.join(RAW, name + '.npy'))
        self.m = json.load(open(os.path.join(RAW, name + '.json')))

    def sample(self, x, z, order=1):
        lat, lon = to_ll(x, z)
        X, Y = merc(lat, lon)
        col = (X - self.m['x0']) / self.m['px'] - 0.5
        row = (self.m['y1'] - Y) / self.m['px'] - 0.5
        if self.a.ndim == 2:
            return map_coordinates(self.a, [row, col], order=order, mode='nearest')
        return np.stack(
            [map_coordinates(self.a[..., c].astype(np.float32), [row, col], order=order, mode='nearest')
             for c in range(self.a.shape[2])],
            -1,
        )


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
    R = np.stack([-T[:, 1], T[:, 0]], 1)  # (x, z): direita de quem corre
    return T, R


# ---------------------------------------------------------------- 1) linha central do OSM + alinhamento Garage 61
xml = open(os.path.join(RAW, 'osm.xml'), encoding='utf8').read()
nodes = {m[0]: (float(m[1]), float(m[2])) for m in re.findall(r'<node id="(\d+)"[^>]*lat="([-\d.]+)" lon="([-\d.]+)"', xml)}
ways = []
pit = None
for m in re.finditer(r'<way id="(\d+)"[^>]*>([\s\S]*?)</way>', xml):
    t = dict(re.findall(r'<tag k="([^"]+)" v="([^"]*)"', m.group(2)))
    if t.get('highway') == 'raceway' and t.get('name') not in ('Pit Lane', 'Variante Bassa'):
        ways.append((t.get('name', ''), re.findall(r'<nd ref="(\d+)"', m.group(2))))
    elif t.get('highway') == 'raceway' and t.get('name') == 'Pit Lane':
        pll = np.array([nodes[r] for r in re.findall(r'<nd ref="(\d+)"', m.group(2)) if r in nodes])
        pit = np.stack([(pll[:, 1] - LON0) * MO, -(pll[:, 0] - LAT0) * ML], 1)

by_start = {w[1][0]: w for w in ways}
loop = []
cur = ways[0]
for _ in ways:
    loop += cur[1][:-1]
    cur = by_start[cur[1][-1]]
assert cur is ways[0], 'trechos do OSM não fecham a volta'
ll = np.array([nodes[n] for n in loop])
P0 = np.stack([(ll[:, 1] - LON0) * MO, -(ll[:, 0] - LAT0) * ML], 1)
P, L = resample_loop(P0, DS)

# Carregar apenas os 3 CSVs de Imola (*Enzo*.csv)
csv_files = sorted(glob.glob(os.path.join(ROOT, 'garage61', '*Enzo*.csv')))
assert len(csv_files) == 3, f'Esperados 3 CSVs de Imola, encontrados {len(csv_files)}'
laps_raw = []
laps_meta = []
for f in csv_files:
    rows = list(csv.DictReader(open(f, encoding='utf-8-sig')))
    la = np.array([float(r['Lat']) for r in rows])
    lo = np.array([float(r['Lon']) for r in rows])
    pts = np.stack([(lo - LON0) * MO, -(la - LAT0) * ML], 1)
    # filtro de salto GPS isolado
    for i in range(1, len(pts) - 1):
        mid = 0.5 * (pts[i - 1] + pts[i + 1])
        step = np.linalg.norm(pts[i + 1] - pts[i - 1])
        if np.linalg.norm(pts[i] - mid) > 2.0 + step:
            pts[i] = mid
    laps_raw.append(pts)
    laps_meta.append({
        'name': os.path.basename(f).split(' - ')[2],
        'speed': np.array([float(r['Speed']) for r in rows]),
        'vert': np.array([float(r['VertAccel']) for r in rows]),
    })


def fit_gps_to_track(g, P_ref):
    cg = g.mean(0)
    P_sub = P_ref[::2]

    def xform(params, q):
        dx, dz, th, sc = params
        c, s = np.cos(th), np.sin(th)
        A = (q - cg) * sc
        return np.stack([cg[0] + c * A[:, 0] - s * A[:, 1] + dx, cg[1] + s * A[:, 0] + c * A[:, 1] + dz], 1)

    def loss(params):
        gf = xform(params, g[::8])
        d2 = np.min(np.sum((gf[:, None, :] - P_sub[None, :, :]) ** 2, axis=2), axis=1)
        return float(np.mean(d2))

    res = minimize(loss, [12.0, 16.0, 0.01, 1.0], method='Nelder-Mead', options={'maxiter': 500})
    return xform(res.x, g), res.x


laps_fit = [fit_gps_to_track(g, P)[0] for g in laps_raw]

# Conferir sentido pela 1ª volta ajustada
idx = [int(np.argmin(np.linalg.norm(P - q, axis=1))) for q in laps_fit[0][::60]]
steps = np.diff(idx)
steps = (steps + len(P) // 2) % len(P) - len(P) // 2
if np.median(steps) < 0:
    P = P[::-1].copy()

start = np.mean([lf[0] for lf in laps_fit], 0)
i0 = int(np.argmin(np.linalg.norm(P - start, axis=1)))
P = np.roll(P, -i0, 0)
print(f'OSM: {L:.1f} m, chegada em {start.round(1)} (3 voltas alinhadas)')


# ---------------------------------------------------------------- 2) bordas na foto de satélite 0,25 m
sat = Raster('sat')
OFF = np.arange(-14.0, 14.001, 0.25)


def measure(P_cur):
    T, R = frames(P_cur)
    n = len(P_cur)
    X = P_cur[:, None, 0] + R[:, None, 0] * OFF[None]
    Z = P_cur[:, None, 1] + R[:, None, 1] * OFF[None]
    rgb = sat.sample(X.ravel(), Z.ravel()).reshape(n, len(OFF), 3)
    v = rgb.mean(axis=2)
    rg = rgb[..., 0] - rgb[..., 1]
    gb = rgb[..., 1] - rgb[..., 2]
    rb = rgb[..., 0] - rgb[..., 2]
    ref = median_filter(np.median(v[:, np.abs(OFF) <= 2.2], axis=1), size=31, mode='wrap')
    # fora do asfalto em Imola: faixa branca/zebra clara (v > ref+26), zebra vermelha (R-G > 14),
    # grama/tinta verde iluminada (G-B > 15 e v > 62), brita bege (R-B > 20 e v > 120).
    # Sombras de árvores sobre o asfalto (v < 62) não devem encolher a largura medida!
    off = (
        (v > np.maximum(152.0, ref + 26.0)[:, None])
        | ((rg > 14.0) & (v > 65.0))
        | ((gb > 15.0) & (rgb[..., 1] > rgb[..., 0] + 2.0) & (v > 62.0))
        | ((rb > 20.0) & (v > 120.0))
    )
    # marcar onde a sombra da copa cobre a borda para ignorar na recentralização
    shadowed = (v < 58.0)
    # mascarar pit lane à direita da reta principal
    if pit is not None:
        pitd = np.full(X.shape, np.inf)
        for a, b in zip(pit[:-1], pit[1:]):
            dd = b - a
            den = float(dd @ dd)
            if den < 1e-6:
                continue
            t = np.clip(((X - a[0]) * dd[0] + (Z - a[1]) * dd[1]) / den, 0.0, 1.0)
            pitd = np.minimum(pitd, np.hypot(X - a[0] - dd[0] * t, Z - a[1] - dd[1] * t))
        off |= pitd < 4.5

    bad = median_filter(off.astype(np.uint8), size=(7, 1), mode='wrap') > 0
    edges = np.full((n, 2), np.nan)
    # começa a varredura a ±3,5 m do centro (pista FIA Grade 1 tem >= 10 m de asfalto) para evitar marcas no meio
    cL = int(np.searchsorted(OFF, -3.5))
    cR = int(np.searchsorted(OFF, 3.5))
    for side, rng in ((0, range(cL, -1, -1)), (1, range(cR, len(OFF)))):
        for i in range(n):
            run = 0
            for k in rng:
                if shadowed[i, k] and run == 0:
                    continue
                run = run + 1 if bad[i, k] else 0
                if run >= 4:  # 1,0 m seguido fora do asfalto neutro
                    kk = k + 3 if side == 0 else k - 3
                    edges[i, side] = abs(OFF[kk]) + 0.30
                    break
    return edges, ref


# Suavizar polígono do OSM preservando o raio real das chicanes (Tamburello, Villeneuve, Variante Alta)
P = circ_gauss(P, 2.2)
for it in range(3):
    edges, ref = measure(P)
    ok = (
        np.all(np.isfinite(edges), 1)
        & (edges[:, 0] > 4.2) & (edges[:, 1] > 4.2)
        & (edges[:, 0] < 9.5) & (edges[:, 1] < 9.5)
        & (edges.sum(1) > 9.8) & (edges.sum(1) < 18.0)
    )
    e = edges.copy()
    for k in range(2):
        good = np.where(ok)[0]
        e[:, k] = np.interp(np.arange(len(P)), good, e[good, k], period=len(P))
    e = median_filter(e, size=(19, 1), mode='wrap')
    shift = circ_gauss((e[:, 1] - e[:, 0]) / 2.0, 8)
    _, R = frames(P)
    P = P + R * np.clip(shift, -2.0, 2.0)[:, None]
    P, L = resample_loop(P, DS)
    P = circ_gauss(P, 2.0)
    print(f'iteração {it}: válidas {ok.mean() * 100:.0f}%, desvio centro med {np.median(np.abs(shift)):.2f} m, volta {L:.1f} m')

# Número de amostras múltiplo de 4 (saída a cada 4 m)
L = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1).sum()
P, L = resample_loop(P, L / (4 * round(L / 4)))
edges, ref = measure(P)
ok = (
    np.all(np.isfinite(edges), 1)
    & (edges[:, 0] > 4.2) & (edges[:, 1] > 4.2)
    & (edges[:, 0] < 9.5) & (edges[:, 1] < 9.5)
    & (edges.sum(1) > 9.8) & (edges.sum(1) < 18.0)
)
W = edges.copy()
for k in range(2):
    good = np.where(ok)[0]
    W[:, k] = np.interp(np.arange(len(P)), good, W[good, k], period=len(P))
W = circ_gauss(median_filter(W, size=(31, 1), mode='wrap'), 5)
W = np.clip(W, 5.2, 8.2)
print(f'largura total: med {np.median(W.sum(1)):.1f} m, p10 {np.percentile(W.sum(1), 10):.1f}, '
      f'p90 {np.percentile(W.sum(1), 90):.1f}, válidas {ok.mean() * 100:.0f}%')

# Re-ajustar as 3 voltas sobre P final e validar bordas
laps_final = [fit_gps_to_track(g, P)[0] for g in laps_raw]
T, R = frames(P)
for idx_l, (lf, meta) in enumerate(zip(laps_final, laps_meta)):
    j = np.array([int(np.argmin(np.linalg.norm(P - q, axis=1))) for q in lf[::3]])
    dlat = ((lf[::3] - P[j]) * R[j]).sum(1)
    outL = -dlat - 1.0 - W[j, 0]
    outR = dlat - 1.0 - W[j, 1]
    o = np.maximum(outL, outR)
    print(f'  volta {meta["name"]:22s}: lateral {dlat.min():+.1f}..{dlat.max():+.1f} m; '
          f'>1,2 m da borda em {np.mean(o > 1.2) * 100:.2f}% (pior {o.max():.2f} m em s={j[np.argmax(o)] * DS:.0f})')


# ---------------------------------------------------------------- 3) zebras no satélite (vermelho/branco)
def detect_kerbs(P_cur, W_cur):
    T_c, R_c = frames(P_cur)
    n = len(P_cur)
    offs = np.arange(0.15, 2.25, 0.25)
    kerb_out = np.zeros((n, 2), dtype=np.float32)
    for side in (0, 1):
        sgn = -1.0 if side == 0 else 1.0
        d_grid = sgn * (W_cur[:, side:side + 1] + offs[None])
        X = P_cur[:, 0:1] + R_c[:, 0:1] * d_grid
        Z = P_cur[:, 1:2] + R_c[:, 1:2] * d_grid
        rgb = sat.sample(X.ravel(), Z.ravel()).reshape(n, len(offs), 3)
        red = (rgb[..., 0] - rgb[..., 1] > 16.0) & (rgb[..., 0] - rgb[..., 2] > 16.0) & (rgb[..., 0] > 115.0)
        white = (rgb.min(2) > 155.0) & (np.ptp(rgb, 2) < 28.0)
        paint = red | white
        # zebra tem vermelho/branco alternado em blocos de 1,5 m -> suaviza ao longo de ±4 m
        score = gaussian_filter1d(paint.any(1).astype(np.float32), 2.5, mode='wrap')
        has_k = score > 0.35
        # largura observada quando há zebra
        width_est = np.where(has_k, np.maximum(1.2, (paint.sum(1) * 0.25).clip(1.2, 2.0)), 0.0)
        kerb_out[:, side] = median_filter(width_est, size=7, mode='wrap')
    return kerb_out


kerbs = detect_kerbs(P, W)
# Curvatura para incluir também eventuais zebras cobertas por sombra de árvore densa
curv_raw = np.arcsin(np.clip(T[:-10, 0] * T[10:, 1] - T[:-10, 1] * T[10:, 0], -1.0, 1.0)) if False else np.array([
    np.arcsin(np.clip(T[(i - 5) % len(P), 0] * T[(i + 5) % len(P), 1] - T[(i - 5) % len(P), 1] * T[(i + 5) % len(P), 0], -1.0, 1.0)) / (10 * DS)
    for i in range(len(P))
])
print(f'zebras satélite: L={(kerbs[:, 0] > 0).mean() * 100:.1f}%, R={(kerbs[:, 1] > 0).mean() * 100:.1f}%')


# ---------------------------------------------------------------- 4) muros reais do OSM + caixas de brita
osm = json.load(open(os.path.join(OUT, 'imola-osm.json')))


def densify_lines(lines):
    pts = []
    for line in lines:
        for a, b in zip(line[:-1], line[1:]):
            d = np.hypot(b[0] - a[0], b[1] - a[1])
            k = max(1, int(np.ceil(d / 2.0)))
            for j in range(k + 1):
                u = j / k
                pts.append([a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u])
    return np.array(pts) if pts else np.zeros((0, 2))


wpts = densify_lines(osm['walls'] + osm['fences'])
# Polígonos de brita também dão distância mínima do muro por trás deles
gpts = densify_lines([g + [g[0]] for g in osm['gravel']])

walls = np.zeros((len(P), 2), dtype=np.float32)
for side in (0, 1):
    sgn = -1.0 if side == 0 else 1.0
    raw_w = np.full(len(P), np.nan)
    for i in range(len(P)):
        v = wpts - P[i]
        d2 = (v ** 2).sum(1)
        m1 = d2 < 36.0 ** 2
        if not m1.any():
            continue
        vm = v[m1]
        along = vm @ T[i]
        lat = (vm @ R[i]) * sgn
        min_lat = W[i, side] + 2.2
        m2 = (np.abs(along) < 3.5) & (lat > min_lat) & (lat < 36.0)
        if m2.any():
            raw_w[i] = float(np.min(lat[m2]))
    good = np.where(np.isfinite(raw_w))[0]
    if len(good) > 10:
        filled = np.interp(np.arange(len(P)), good, raw_w[good], period=len(P))
    else:
        filled = W[:, side] + 14.0
    # garantir que caixas de brita mapeadas fiquem dentro do muro
    if len(gpts) > 0:
        for i in range(0, len(P), 2):
            v = gpts - P[i]
            m1 = (v ** 2).sum(1) < 34.0 ** 2
            if not m1.any():
                continue
            vm = v[m1]
            along = vm @ T[i]
            lat = (vm @ R[i]) * sgn
            m2 = (np.abs(along) < 3.5) & (lat > W[i, side] + 2.0) & (lat < 34.0)
            if m2.any():
                filled[i] = max(filled[i], float(np.max(lat[m2])) + 0.8)
    # Reta dos boxes (pit lane à direita, entrada ~4380..4910 e saída 0..560):
    # na zona dos boxes (4550..4910 e 0..460), o muro dos boxes da direita fica recuado além da pit lane
    # (~16-20 m do centro da pista) para dar passagem ao pit lane sem muro falso na pista
    filled = np.clip(filled, W[:, side] + 2.5, 32.0)
    walls[:, side] = circ_gauss(median_filter(filled, size=15, mode='wrap'), 8)

print(f'muros: L med {np.median(walls[:, 0]):.1f} m (min {walls[:, 0].min():.1f}..max {walls[:, 0].max():.1f}), '
      f'R med {np.median(walls[:, 1]):.1f} m (min {walls[:, 1].min():.1f}..max {walls[:, 1].max():.1f})')


# ---------------------------------------------------------------- 5) altitude e camber pelo LiDAR
dem = Raster('dem1m')
y_raw = dem.sample(P[:, 0], P[:, 1])
# remove passagens inferiores estreitas sob a pista (ex.: s=492..509 onde o DTM cai 4 m dentro da galeria)
y_med = median_filter(y_raw, size=65, mode='wrap')
y = np.where(np.abs(y_raw - y_med) > 0.35, y_med, y_raw)
y = median_filter(y, size=9, mode='wrap')
y = circ_gauss(y, 4)

HB = 3.5
hl = dem.sample(P[:, 0] - R[:, 0] * HB, P[:, 1] - R[:, 1] * HB)
hr = dem.sample(P[:, 0] + R[:, 0] * HB, P[:, 1] + R[:, 1] * HB)
# remove o mesmo efeito de galeria lateralmente no cálculo do camber
hl = np.where(np.abs(hl - y_med) > 0.8, y, hl)
hr = np.where(np.abs(hr - y_med) > 0.8, y, hr)
bank = circ_gauss(np.arctan2(median_filter(hr - hl, size=15, mode='wrap'), 2 * HB), 10)
ymin = float(y.min())
print(f'altitude {ymin:.1f}..{y.max():.1f} m (desnível {y.max() - ymin:.1f} m); '
      f'camber med {np.degrees(np.median(np.abs(bank))):.1f}°, max {np.degrees(np.abs(bank).max()):.1f}°')

# Validação VertAccel vs curvatura vertical da pista
dy_ds = (np.roll(y, -3) - np.roll(y, 3)) / (6.0 * DS)
d2y_ds2 = (np.roll(dy_ds, -4) - np.roll(dy_ds, 4)) / (8.0 * DS)
for lf, meta in zip(laps_final, laps_meta):
    j = np.array([int(np.argmin(np.linalg.norm(P - q, axis=1))) for q in lf])
    pred_g = 1.0 + (meta['speed'] ** 2 * d2y_ds2[j]) / 9.81
    meas_g = meta['vert'] / 9.81
    err = np.abs(pred_g - meas_g)
    print(f'  VertAccel {meta["name"]:22s}: MAE={np.mean(err):.3f} g, p90={np.percentile(err, 90):.3f} g')

# Diagnóstico de curvas (picos de curvatura e velocidade mínima da referência M4)
s_m4 = np.array([int(np.argmin(np.linalg.norm(P - q, axis=1))) for q in laps_final[0]])
v_m4_by_s = np.full(len(P), np.nan)
for k_s, spd in zip(s_m4, laps_meta[0]['speed']):
    v_m4_by_s[k_s] = spd * 3.6
print('Perfil de velocidade e camber a cada 100 m:')
for s_at in range(0, len(P), 100):
    win = slice(s_at, min(len(P), s_at + 100))
    vmin = np.nanmin(v_m4_by_s[win]) if np.any(np.isfinite(v_m4_by_s[win])) else np.nan
    bdeg = np.degrees(bank[s_at + 50 if s_at + 50 < len(P) else s_at])
    c_max = float(np.max(np.abs(curv_raw[win])))
    print(f'  s={s_at:4d}..{min(len(P), s_at+100):4d}: h={y[s_at]-ymin:5.1f}m bank={bdeg:+5.1f}° vmin={vmin:5.1f}km/h curv_max={c_max:.4f} wl/wr={W[s_at,0]:.1f}/{W[s_at,1]:.1f} wall={walls[s_at,0]:.1f}/{walls[s_at,1]:.1f}')


# ---------------------------------------------------------------- 6) saída (pontos a cada 4 m)
k = 4
# Seções oficiais de Imola (10 trechos cobrindo a volta de ~4910 m; ajustados pelos ápices)
# Serão validados/refinados se necessário após imprimir a tabela acima:
sections = [
    {'name': 'Variante del Tamburello', 's0': 460, 's1': 920},
    {'name': 'Variante Villeneuve', 's0': 920, 's1': 1520},
    {'name': 'Curva della Tosa', 's0': 1520, 's1': 1900},
    {'name': 'Curva della Piratella', 's0': 1900, 's1': 2500},
    {'name': 'Acque Minerali', 's0': 2500, 's1': 3100},
    {'name': 'Variante Alta', 's0': 3100, 's1': 3580},
    {'name': 'Discesa verso Rivazza', 's0': 3580, 's1': 4040},
    {'name': 'Rivazza', 's0': 4040, 's1': 4460},
    {'name': 'Traguardo', 's0': 4460, 's1': 4760},
    {'name': 'Reta Principal', 's0': 4760, 's1': 460},
]

out = {
    'name': 'Imola',
    'source': 'OpenStreetMap (ODbL) + Esri World Imagery (larguras/zebras) + Geoportale Emilia-Romagna Dtm1x1PST/Dtm5x5 (altitude e camber)',
    'origin': {'lat': LAT0, 'lon': LON0},
    'points': [[round(float(P[i, 0]), 3), round(float(y[i] - ymin), 3), round(float(P[i, 1]), 3)] for i in range(0, len(P), k)],
    'widthLeft': [round(float(W[i, 0]), 2) for i in range(0, len(P), k)],
    'widthRight': [round(float(W[i, 1]), 2) for i in range(0, len(P), k)],
    'bank': [round(float(bank[i]), 4) for i in range(0, len(P), k)],
    'wallLeft': [round(float(walls[i, 0]), 2) for i in range(0, len(P), k)],
    'wallRight': [round(float(walls[i, 1]), 2) for i in range(0, len(P), k)],
    'kerbLeft': [round(float(kerbs[i, 0]), 2) for i in range(0, len(P), k)],
    'kerbRight': [round(float(kerbs[i, 1]), 2) for i in range(0, len(P), k)],
    'maxRunoff': 2.5,
    'sections': sections,
}
json.dump(out, open(os.path.join(OUT, 'imola.json'), 'w'))

# Grade de relevo (células de 8 m, cobrindo ±1 km)
STEP_T = 8.0
lat_a, lat_b = 44.3260 + 0.0005, 44.3560 - 0.0005
lon_a, lon_b = 11.6880 + 0.0005, 11.7390 - 0.0005
x0, x1 = (lon_a - LON0) * MO, (lon_b - LON0) * MO
z0, z1 = -(lat_b - LAT0) * ML, -(lat_a - LAT0) * ML
nx, nz = int((x1 - x0) // STEP_T) + 1, int((z1 - z0) // STEP_T) + 1
gx, gz = np.meshgrid(x0 + np.arange(nx) * STEP_T, z0 + np.arange(nz) * STEP_T)
acc = np.zeros(gx.shape)
for dx in (-3, -1, 1, 3):
    for dz in (-3, -1, 1, 3):
        acc += dem.sample((gx + dx).ravel(), (gz + dz).ravel()).reshape(gx.shape)
acc /= 16.0
json.dump(
    {
        'x0': round(float(x0), 2),
        'z0': round(float(z0), 2),
        'step': STEP_T,
        'nx': nx,
        'nz': nz,
        'h': [round(float(v), 1) for v in acc.ravel()],
    },
    open(os.path.join(OUT, 'imola-terrain.json'), 'w'),
)
print(f'relevo {nx}x{nz} células de {STEP_T:.0f} m')
np.savez(os.path.join(RAW, 'diag.npz'), P=P, W=W, y=y, bank=bank, walls=walls, kerbs=kerbs, edges=edges, ok=ok)
print('gravado', os.path.join(OUT, 'imola.json'), len(out['points']), 'pontos')
