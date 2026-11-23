# Relevo LiDAR de Interlagos (Prefeitura de São Paulo / GeoSampa, levantamento a laser 2017, nuvem LAZ em
# SIRGAS 2000 / UTM 23S, EPSG:31983) já rasterizado por download_lidar.py em build/interlagos/lidar/:
#   mdt.npy + mdt.json        terreno nu (pontos classe 2), 0,5 m, buracos preenchidos (mdt_preenchido.npy = máscara)
#   mds.npy + mds.json        superfície (maior retorno por célula, sem ruído), 1 m
#   copa.npy                  mds - mdt reamostrado em 1 m (altura de copa/prédio), para a etapa de árvores
#   piso.npy + piso.json      chão perto da pista (classes 2 + 20), 0,5 m, faixa de 40 m das linhas nova e antiga
#                             (download_lidar.py --piso); piso_n.npy = pontos por célula, piso_int.npy = intensidade
#
# Uso por outra etapa (de REPOS/gt3-godot):
#   import sys; sys.path.insert(0, 'tools/tracks/interlagos'); import lidar
#   y = lidar.altura(x, z)            # altitude (m, absoluta) do chão em (x, z) do jogo, arrays ou escalares
#                                     # (piso perto da pista, MDT + offset fora; fonte='mdt' = só classe 2, antigo)
#   h = lidar.copa(x, z)              # altura de copa/prédio acima do terreno (m)
#   s = lidar.superficie(x, z)        # MDS (copas, prédios), absoluto
#   E, N = lidar.jogo_para_utm(x, z)  # x = leste, z = sul; origem lat -23.7036, lon -46.6997; + REGISTRO (abaixo)
#
# Conferências + grade de relevo do cenário (tools/tracks/interlagos/interlagos-terrain.json):
#   python tools/tracks/interlagos/lidar.py --conferir
import json
import math
import os
import sys

import numpy as np
from scipy.ndimage import gaussian_filter1d, map_coordinates, median_filter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
OUT = os.path.join(ROOT, 'build', 'interlagos', 'lidar')
HERE = os.path.dirname(os.path.abspath(__file__))

# georreferência do jogo (igual a gt3-time-attack/scripts/ref-lib.ts readLap)
LAT0, LON0 = -23.7036, -46.6997
ML = 111320.0
MO = ML * math.cos(math.radians(LAT0))
# Registro do LiDAR no mundo do jogo: o mundo é o referencial do OSM (linha atual), que fica ~2 m deslocado do
# terreno georreferenciado. Medido em 23/11/2026 pelo contraste de intensidade do laser (asfalto escuro × faixa de
# 0,5–2,5 m além das bordas) com a pista nova (interlagos.json, larguras): melhor em (+1,50, −1,75) m na volta e
# (+1,0…1,5, −1,25…−2,75) por quarto de volta; pela cor (RGB da nuvem) (+1,75, −1,75). Mesmo sentido do satélite
# Esri (+2,1, −2,2) e do GPS do iRacing (+2,5, −2,8). Ponto do LiDAR = ponto do mundo + REGISTRO (x, z em m).
# `lidar.py --conferir` mede o resíduo de novo (deve ficar perto de 0).
REGISTRO = (1.50, -1.75)


def jogo_para_ll(x, z):
    x, z = np.asarray(x, np.float64), np.asarray(z, np.float64)
    return LAT0 - z / ML, LON0 + x / MO


def ll_para_jogo(lat, lon):
    return (np.asarray(lon, np.float64) - LON0) * MO, -(np.asarray(lat, np.float64) - LAT0) * ML


# ---- UTM (Transverse Mercator, série de Krüger de 6ª ordem; GRS80 = SIRGAS 2000), zona 23 Sul
_A, _F = 6378137.0, 1 / 298.257222101
_K0, _LON_C, _FE, _FN = 0.9996, -45.0, 500000.0, 10000000.0
_n = _F / (2 - _F)
_AA = _A / (1 + _n) * (1 + _n ** 2 / 4 + _n ** 4 / 64 + _n ** 6 / 256)
_al = [
    _n / 2 - 2 * _n ** 2 / 3 + 5 * _n ** 3 / 16 + 41 * _n ** 4 / 180 - 127 * _n ** 5 / 288 + 7891 * _n ** 6 / 37800,
    13 * _n ** 2 / 48 - 3 * _n ** 3 / 5 + 557 * _n ** 4 / 1440 + 281 * _n ** 5 / 630 - 1983433 * _n ** 6 / 1935360,
    61 * _n ** 3 / 240 - 103 * _n ** 4 / 140 + 15061 * _n ** 5 / 26880 + 167603 * _n ** 6 / 181440,
    49561 * _n ** 4 / 161280 - 179 * _n ** 5 / 168 + 6601661 * _n ** 6 / 7257600,
    34729 * _n ** 5 / 80640 - 3418889 * _n ** 6 / 1995840,
    212378941 * _n ** 6 / 319334400,
]
_be = [
    _n / 2 - 2 * _n ** 2 / 3 + 37 * _n ** 3 / 96 - _n ** 4 / 360 - 81 * _n ** 5 / 512 + 96199 * _n ** 6 / 604800,
    _n ** 2 / 48 + _n ** 3 / 15 - 437 * _n ** 4 / 1440 + 46 * _n ** 5 / 105 - 1118711 * _n ** 6 / 3870720,
    17 * _n ** 3 / 480 - 37 * _n ** 4 / 840 - 209 * _n ** 5 / 4480 + 5569 * _n ** 6 / 90720,
    4397 * _n ** 4 / 161280 - 11 * _n ** 5 / 504 - 830251 * _n ** 6 / 7257600,
    4583 * _n ** 5 / 161280 - 108847 * _n ** 6 / 3991680,
    20648693 * _n ** 6 / 638668800,
]
_E2 = 2 * _n / (1 + _n)  # excentricidade: e = sqrt(f (2 - f))
_e = math.sqrt(_F * (2 - _F))


def ll_para_utm(lat, lon):
    phi = np.radians(np.asarray(lat, np.float64))
    lam = np.radians(np.asarray(lon, np.float64) - _LON_C)
    t = np.sinh(np.arctanh(np.sin(phi)) - _e * np.arctanh(_e * np.sin(phi)))
    xi_ = np.arctan2(t, np.cos(lam))
    eta_ = np.arctanh(np.sin(lam) / np.sqrt(1 + t * t))
    xi, eta = xi_.copy(), eta_.copy()
    for j, a in enumerate(_al, 1):
        xi = xi + a * np.sin(2 * j * xi_) * np.cosh(2 * j * eta_)
        eta = eta + a * np.cos(2 * j * xi_) * np.sinh(2 * j * eta_)
    return _FE + _K0 * _AA * eta, _FN + _K0 * _AA * xi


def utm_para_ll(E, N):
    xi = (np.asarray(N, np.float64) - _FN) / (_K0 * _AA)
    eta = (np.asarray(E, np.float64) - _FE) / (_K0 * _AA)
    xi_, eta_ = xi.copy(), eta.copy()
    for j, b in enumerate(_be, 1):
        xi_ = xi_ - b * np.sin(2 * j * xi) * np.cosh(2 * j * eta)
        eta_ = eta_ - b * np.cos(2 * j * xi) * np.sinh(2 * j * eta)
    chi = np.arcsin(np.sin(xi_) / np.cosh(eta_))
    lam = np.arctan2(np.sinh(eta_), np.cos(xi_))
    # latitude geodésica a partir da conforme (iteração de Newton em tau)
    tau_ = np.tan(chi)
    tau = tau_.copy()
    for _ in range(6):
        s = np.sinh(_e * np.arctanh(_e * tau / np.sqrt(1 + tau * tau)))
        tau_i = tau * np.sqrt(1 + s * s) - s * np.sqrt(1 + tau * tau)
        dtau = (tau_ - tau_i) / np.sqrt(1 + tau_i * tau_i) * (1 + (1 - _e * _e) * tau * tau) / (
            (1 - _e * _e) * np.sqrt(1 + tau * tau))
        tau = tau + dtau
    return np.degrees(np.arctan(tau)), np.degrees(lam) + _LON_C


def jogo_para_utm(x, z, registro=True):
    """(x, z) do mundo do jogo -> (E, N) UTM 23S. Com `registro` (padrão), soma REGISTRO antes: é o ponto
    correspondente no LiDAR. registro=False = conversão geográfica pura da origem do jogo."""
    if registro:
        x, z = np.asarray(x, np.float64) + REGISTRO[0], np.asarray(z, np.float64) + REGISTRO[1]
    return ll_para_utm(*jogo_para_ll(x, z))


def utm_para_jogo(E, N, registro=True):
    x, z = ll_para_jogo(*utm_para_ll(E, N))
    if registro:
        x, z = x - REGISTRO[0], z - REGISTRO[1]
    return x, z


# ---- amostragem dos rasters (grade UTM alinhada: célula (r, c) tem centro E0 + (c + 0,5) px, N1 - (r + 0,5) px)
class Raster:
    def __init__(self, nome):
        self.a = np.load(os.path.join(OUT, nome + '.npy'), mmap_mode='r')
        b = open(os.path.join(OUT, nome + '.json'), 'rb').read()
        try:
            self.m = json.loads(b.decode('utf8'))
        except UnicodeDecodeError:  # mdt/mds/copa.json antigos foram gravados em cp1252
            self.m = json.loads(b.decode('latin-1'))

    def utm(self, E, N, order=1):
        col = (np.asarray(E) - self.m['E0']) / self.m['px'] - 0.5
        row = (self.m['N1'] - np.asarray(N)) / self.m['px'] - 0.5
        shp = np.shape(col)
        v = map_coordinates(self.a, [np.ravel(row), np.ravel(col)], order=order, mode='nearest')
        return v.reshape(shp) if shp else float(v[0])

    def jogo(self, x, z, order=1):
        return self.utm(*jogo_para_utm(x, z), order=order)


_cache = {}


def _r(nome):
    if nome not in _cache:
        _cache[nome] = Raster(nome)
    return _cache[nome]


def _tem_piso():
    return os.path.exists(os.path.join(OUT, 'piso.npy'))


# 'piso' (padrão): chão real perto da pista (classes 2 + 20) e MDT + offset fora da faixa; 'mdt': só a classe 2
# (envelope inferior do solo, ~0,12 m abaixo do chão real, 64% da linha central interpolada) — usado nas
# conferências antes × depois. Variável de ambiente LIDAR_FONTE=mdt força o modo antigo.
FONTE = os.environ.get('LIDAR_FONTE', 'piso')


def altura(x, z, order=1, fonte=None):
    """Altitude absoluta (m) do chão em coordenadas do jogo (arrays ou escalares).
    Até 34 m das linhas centrais (nova e antiga): piso.npy (0,5 m, classes 2 + 20, média robusta, σ 0,75 m);
    34–40 m: mistura suave com o MDT; fora: MDT (classe 2, 0,5 m) + offset (o mesmo nível do piso, sem degrau)."""
    fonte = fonte or FONTE
    if fonte == 'mdt' or not _tem_piso():
        return _r('mdt').jogo(x, z, order)
    E, N = jogo_para_utm(x, z)
    shp = np.shape(E)
    E, N = np.ravel(E), np.ravel(N)
    p = _r('piso')
    col = (E - p.m['E0']) / p.m['px'] - 0.5
    row = (p.m['N1'] - N) / p.m['px'] - 0.5
    dentro = (col >= 1) & (col <= p.m['nx'] - 2) & (row >= 1) & (row <= p.m['ny'] - 2)
    v = np.empty(len(E))
    if dentro.any():
        v[dentro] = map_coordinates(p.a, [row[dentro], col[dentro]], order=order, mode='nearest')
    if (~dentro).any():
        v[~dentro] = np.ravel(_r('mdt').utm(E[~dentro], N[~dentro], order)) + p.m['offset_mdt']
    return v.reshape(shp) if shp else float(v[0])


def superficie(x, z, order=1):
    """Altitude absoluta (m) da superfície (MDS 1 m: copas, prédios, arquibancadas)."""
    return _r('mds').jogo(x, z, order)


def copa(x, z, order=1):
    """Altura (m) acima do terreno de copa/prédio (MDS - MDT, 1 m)."""
    return _r('copa').jogo(x, z, order)


# ---------------------------------------------------------------- conferências
def _srtm():
    p = os.path.join(ROOT, '..', 'gt3-time-attack', 'data', 'tracks', 'interlagos-terrain.json')
    t = json.load(open(p))
    h = np.array(t['h'], np.float64).reshape(t['nz'], t['nx'])

    def amostra(x, z):
        c = (np.asarray(x) - t['x0']) / t['step']
        r = (np.asarray(z) - t['z0']) / t['step']
        return map_coordinates(h, [r, c], order=1, mode='nearest')
    return amostra


TRACK_ANTIGO = os.path.join(OUT, 'track_antigo.json')


def _linha_central():
    """Linha central ANTIGA (a de antes da Fase 2B: n = 2147, 4294 m). data/track/track.json passou a receber a
    pista nova na etapa E, então a antiga fica congelada em build/interlagos/lidar/track_antigo.json
    (git show 6b69c3b:data/track/track.json); sem a cópia, cai no data/track/track.json."""
    p = TRACK_ANTIGO if os.path.exists(TRACK_ANTIGO) else os.path.join(ROOT, 'data', 'track', 'track.json')
    d = json.load(open(p, encoding='utf8'))
    a = np.array(d['s'], np.float64).reshape(d['n'], d['stride'])
    return a, float(d['step']), d['sections']


def _grafico(path, s, series, marcas, titulo, passo_y=5):
    """Gráfico de linhas simples com PIL (sem matplotlib)."""
    from PIL import Image, ImageDraw
    W, H, ml, mr, mt, mb = 1600, 700, 70, 20, 40, 60
    img = Image.new('RGB', (W, H), 'white')
    d = ImageDraw.Draw(img)
    ys = np.concatenate([v for _, v, _ in series])
    y0, y1 = math.floor(np.nanmin(ys) / passo_y) * passo_y, math.ceil(np.nanmax(ys) / passo_y) * passo_y
    s0, s1 = float(s[0]), float(s[-1])
    X = lambda v: ml + (v - s0) / (s1 - s0) * (W - ml - mr)
    Y = lambda v: H - mb - (v - y0) / (y1 - y0) * (H - mt - mb)
    for yv in np.arange(y0, y1 + passo_y / 2, passo_y):
        d.line([(ml, Y(yv)), (W - mr, Y(yv))], fill=(225, 225, 225))
        d.text((8, Y(yv) - 6), f'{yv:g}', fill='black')
    for sv in range(0, int(s1) + 1, 250):
        d.line([(X(sv), mt), (X(sv), H - mb)], fill=(235, 235, 235))
        d.text((X(sv) - 10, H - mb + 6), f'{sv}', fill='black')
    for nome, s_a, _ in marcas:
        d.line([(X(s_a), mt), (X(s_a), H - mb)], fill=(200, 200, 255))
        d.text((X(s_a) + 2, mt + 2 + 12 * (marcas.index((nome, s_a, _)) % 3)), nome, fill=(60, 60, 160))
    for k, (nome, v, cor) in enumerate(series):
        pts = [(X(a), Y(b)) for a, b in zip(s, v) if np.isfinite(b)]
        d.line(pts, fill=cor, width=2)
        d.rectangle([W - 330, 10 + 18 * k, W - 316, 22 + 18 * k], fill=cor)
        d.text((W - 310, 10 + 18 * k), nome, fill='black')
    d.text((ml, 12), titulo, fill='black')
    d.text((W // 2 - 60, H - 24), 's ao longo da volta (m)', fill='black')
    img.save(path)


def _linha_nova(step=2.0):
    """Linha central nova (interlagos.json, pontos [x, y, z] a 4 m) reamostrada a `step` m; seções em s novo."""
    d = json.load(open(os.path.join(HERE, 'interlagos.json'), encoding='utf8'))
    P = np.array(d['points'], np.float64)[:, [0, 2]]
    Q = np.vstack([P, P[:1]])
    sc = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(Q, axis=0), axis=1))])
    L = sc[-1]
    n = int(round(L / step))
    st = L / n
    s = np.arange(n) * st
    return np.stack([np.interp(s, sc, Q[:, 0]), np.interp(s, sc, Q[:, 1])], 1), st, d['sections'], d


def _frames(P):
    T = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    T /= np.linalg.norm(T, axis=1)[:, None]
    return T, np.stack([-T[:, 1], T[:, 0]], 1)  # direita de quem corre (x, z), igual a build_track.py


def _celula(r, x, z):
    E, N = jogo_para_utm(x, z)
    return (np.floor((r.m['N1'] - N) / r.m['px']).astype(int), np.floor((E - r.m['E0']) / r.m['px']).astype(int))


def medida_direta(P):
    """% das amostras da linha com ponto de solo na célula de 0,5 m: só classe 2 (MDT) e classes 2 + 20 (piso)."""
    m = _r('mdt')
    pre = np.load(os.path.join(OUT, 'mdt_preenchido.npy'), mmap_mode='r')
    r, c = _celula(m, P[:, 0], P[:, 1])
    out = {'classe2_pct': round(100 * float(np.mean(~pre[r, c])), 1)}
    if _tem_piso():
        p = _r('piso')
        pn = np.load(os.path.join(OUT, 'piso_n.npy'), mmap_mode='r')
        r, c = _celula(p, P[:, 0], P[:, 1])
        out['classes_2_20_pct'] = round(100 * float(np.mean(pn[r, c] > 0)), 1)
        out['classes_2_20_pts_por_celula_p50'] = float(np.median(pn[r, c]))
    return out


HB = 3.5  # meia-base do camber (m), sempre sobre o asfalto


def camber_bruto(P, R, hb=HB, passo=0.5, fonte=None):
    """Inclinação lateral (rad, + = direita mais alta) em cada ponto P (n x 2) com vetor direita R (n x 2):
    reta robusta pelas alturas a cada `passo` m entre −hb e +hb (Theil–Sen + 3 iterações de Tukey, c = 0,12 m).
    Ignora degrau/muro/zebra alta num dos lados (ex.: Bico de Pato, s 2680–2730: degrau de 0,9 m a 4 m à
    esquerda no LiDAR 2017), que o método de 2 pontos (±hb) transforma em camber falso."""
    o = np.arange(-hb, hb + 1e-9, passo)
    H = np.stack([altura(P[:, 0] + R[:, 0] * v, P[:, 1] + R[:, 1] * v, fonte=fonte) for v in o], 1)
    i, j = np.triu_indices(len(o), 1)
    b = np.median((H[:, j] - H[:, i]) / (o[j] - o[i]), axis=1)
    a = np.median(H - b[:, None] * o[None], axis=1)
    for _ in range(3):
        r = H - a[:, None] - b[:, None] * o[None]
        w = np.clip(1 - (r / 0.12) ** 2, 0, None) ** 2
        sw = np.maximum(w.sum(1), 1e-9)
        mo, mh = (w * o).sum(1) / sw, (w * H).sum(1) / sw
        b = (w * (o - mo[:, None]) * (H - mh[:, None])).sum(1) / np.maximum((w * (o - mo[:, None]) ** 2).sum(1), 1e-9)
        a = mh - b * mo
    return np.arctan(b)


def perfil(P, step, secs, fonte=None, sig_y=4.0, sig_b=10.0, metodo='robusto'):
    """Altitude e camber sob a linha P (n x 2, fechada, passo `step`):
    mediana de 65 m contra pontes/galerias (> 0,35 m), mediana curta + gaussiana σ `sig_y`; camber pela reta
    robusta entre ±3,5 m (`camber_bruto`) ou, metodo='2pontos', pela diferença a ±3,5 m (como build_track.py
    --lidar hoje; descarta lado a > 0,8 m da mediana); mediana curta + σ `sig_b`. bank + = direita mais alta."""
    n = len(P)
    T, R = _frames(P)
    sig = lambda v, m: gaussian_filter1d(v, m / step, mode='wrap')
    y_raw = altura(P[:, 0], P[:, 1], fonte=fonte)
    y_med = median_filter(y_raw, size=int(65 / step) | 1, mode='wrap')
    troca = np.abs(y_raw - y_med) > 0.35
    y = np.where(troca, y_med, y_raw)
    y = sig(median_filter(y, size=5, mode='wrap'), sig_y)
    hl = altura(P[:, 0] - R[:, 0] * HB, P[:, 1] - R[:, 1] * HB, fonte=fonte)
    hr = altura(P[:, 0] + R[:, 0] * HB, P[:, 1] + R[:, 1] * HB, fonte=fonte)
    hl = np.where(np.abs(hl - y_med) > 0.8, y, hl)
    hr = np.where(np.abs(hr - y_med) > 0.8, y, hr)
    if metodo == '2pontos':
        bank_bruto = np.arctan2(hr - hl, 2 * HB)
        bank = sig(np.arctan2(median_filter(hr - hl, size=7, mode='wrap'), 2 * HB), sig_b)
    else:
        bank_bruto = camber_bruto(P, R, fonte=fonte)
        bank = sig(median_filter(bank_bruto, size=7, mode='wrap'), sig_b)
    dT = np.roll(T, -2, 0) - np.roll(T, 2, 0)
    kap = sig(np.sum(dT * R, 1) / (4 * step), 6)  # > 0 = curva para a direita (para o lado de R)
    curvas = []
    for sc in secs:
        i0, i1 = int(round(sc['s0'] / step)), int(round(sc['s1'] / step))
        idx = np.arange(i0, i1) % n
        km = float(np.mean(kap[idx]))
        bm = float(np.degrees(np.mean(bank[idx])))
        reta = abs(km) < 1 / 400
        coerente = (bm < 0) if km > 0 else (bm > 0)  # curva à direita: fora = esquerda -> bank < 0
        curvas.append({'nome': sc['name'], 's': [sc['s0'], sc['s1']], 'raio_med': round(1 / abs(km)) if km else None,
                       'vira': 'dir' if km > 0 else 'esq', 'bank_med_graus': round(bm, 2),
                       'bank_max_graus': round(float(np.degrees(bank[idx][np.argmax(np.abs(bank[idx]))])), 2),
                       'fora_mais_alto': None if reta else bool(coerente)})
    return {'s': np.arange(n) * step, 'y_raw': y_raw, 'y': y, 'y_med': y_med, 'bank': bank,
            'bank_bruto': bank_bruto, 'kap': kap, 'T': T, 'R': R, 'curvas': curvas,
            'trocas_mediana': int(troca.sum()), 'desnivel': round(float(y.max() - y.min()), 2)}


def dentes(dados_nova, fonte):
    """Degraus entre células vizinhas do raster sob o asfalto da linha nova (bordas - 0,5 m).
    'dif' = |z_i - z_j| (inclui a rampa real); 'dente' = |z_-1 - 2 z_0 + z_+1| (desvio da rampa)."""
    r = _r('piso' if fonte == 'piso' else 'mdt')
    a = np.asarray(r.a)
    pts = np.array(dados_nova['points'], np.float64)[:, [0, 2]]
    wl, wr = np.array(dados_nova['widthLeft']), np.array(dados_nova['widthRight'])
    T, R = _frames(pts)
    rr, cc = [], []
    for k in range(4):  # amostras a cada 1 m entre os pontos de 4 m
        Pk = pts + (k / 4) * (np.roll(pts, -1, 0) - pts)
        for o in np.arange(-14, 14.01, 0.25):
            ok = (o > -(wl - 0.5)) & (o < (wr - 0.5))
            r_, c_ = _celula(r, Pk[ok, 0] + R[ok, 0] * o, Pk[ok, 1] + R[ok, 1] * o)
            rr.append(r_); cc.append(c_)
    m = np.zeros(a.shape, bool)
    m[np.concatenate(rr), np.concatenate(cc)] = True
    out = {'celulas': int(m.sum())}
    dif, d2 = [], []
    for ax in (0, 1):
        def sl(i, j):
            return (slice(i, a.shape[0] - j), slice(None)) if ax == 0 else (slice(None), slice(i, a.shape[1] - j))
        mm = m[sl(0, 1)] & m[sl(1, 0)]
        dif.append(np.abs(a[sl(1, 0)] - a[sl(0, 1)])[mm])
        m3 = m[sl(0, 2)] & m[sl(1, 1)] & m[sl(2, 0)]
        d2.append(np.abs(a[sl(0, 2)] - 2 * a[sl(1, 1)] + a[sl(2, 0)])[m3])
    dif, d2 = np.concatenate(dif), np.concatenate(d2)
    out['dif_p50_p99_max_cm'] = [round(100 * float(v), 2) for v in (np.median(dif), np.percentile(dif, 99), dif.max())]
    out['dente_p50_p99_max_cm'] = [round(100 * float(v), 2) for v in (np.median(d2), np.percentile(d2, 99), d2.max())]
    out['dif_acima_3cm_pct'] = round(100 * float(np.mean(dif > 0.03)), 3)
    out['dentes_acima_3cm_pct'] = round(100 * float(np.mean(d2 > 0.03)), 3)
    return out


def registro_residuo(dados_nova, passo=0.25, alcance=2.5):
    """Resíduo do REGISTRO: deslocamento extra (dx, dz) que maximiza o contraste de intensidade do laser entre a
    faixa de 0,5–2,5 m além das bordas e o asfalto (bordas − 0,7 m) da pista nova. Volta inteira e por quarto."""
    from scipy.ndimage import gaussian_filter
    p = _r('piso')
    ip = os.path.join(OUT, 'piso_int.npy')
    if not os.path.exists(ip):
        return 'sem piso_int.npy (rodar download_lidar.py --piso)'
    ii = np.load(ip)
    c = ~np.isnan(ii)
    K = gaussian_filter(c.astype(np.float64), 1)
    inten = np.where(K > 0.3, gaussian_filter(np.where(c, ii, 0.0), 1) / np.maximum(K, 1e-9), np.nan)
    pts = np.array(dados_nova['points'], np.float64)[:, [0, 2]]
    wl, wr = np.array(dados_nova['widthLeft']), np.array(dados_nova['widthRight'])
    T, R = _frames(pts)
    ss = np.arange(len(pts)) * 4.0
    sh = np.arange(-alcance, alcance + 1e-6, passo)

    def amostra(xy, dx, dz):
        E, N = jogo_para_utm(xy[:, 0] + dx, xy[:, 1] + dz)
        return map_coordinates(inten, [(p.m['N1'] - N) / p.m['px'] - 0.5, (E - p.m['E0']) / p.m['px'] - 0.5],
                               order=1, mode='nearest')
    out = {}
    for nome, sel in [('volta', ss >= 0)] + [(f's{a}-{a + 1100}', (ss >= a) & (ss < a + 1100)) for a in (0, 1100, 2200, 3300)]:
        ins, ring = [], []
        for o in np.arange(-18, 18.01, 0.25):
            a_ = (o > -(wl - 0.7)) & (o < wr - 0.7) & sel
            b_ = (((o < -(wl + 0.5)) & (o > -(wl + 2.5))) | ((o > wr + 0.5) & (o < wr + 2.5))) & sel
            ins.append(pts[a_] + R[a_] * o); ring.append(pts[b_] + R[b_] * o)
        ins, ring = np.concatenate(ins), np.concatenate(ring)
        M = np.array([[np.nanmean(amostra(ring, dx, dz)) - np.nanmean(amostra(ins, dx, dz)) for dx in sh] for dz in sh])
        b = np.unravel_index(np.nanargmax(M), M.shape)
        i0 = int(np.argmin(np.abs(sh)))
        out[nome] = {'dx_dz_extra': [round(float(sh[b[1]]), 2), round(float(sh[b[0]]), 2)],
                     'contraste_melhor_e_em_0': [round(float(M[b]), 2), round(float(M[i0, i0]), 2)]}
    out['REGISTRO_atual'] = list(REGISTRO)
    return out


def vertaccel(pf_por_nome, step, P=None):
    """VertAccel do iRacing (Garage 61) × previsão pela geometria na linha antiga (s do track.json):
    a_v = (g cos(rampa) + v² κ_v) cos(bank) − a_lat sin(bank), a_lat = v² κ_h (+ = para a direita).
    Média das voltas por s; tudo filtrado σ 15 m. Retorna, por perfil, rms/p95 da diferença (g) e correlação."""
    import csv
    import glob
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'ref'))
    import ref_garage61 as rg
    aj = json.load(open(os.path.join(ROOT, 'build', 'ref', 'interlagos', 'ajuste_gps.json'), encoding='utf8'))['ajuste']
    from scipy.spatial import cKDTree
    if P is None:
        P = _linha_central()[0][:, [0, 2]]
    n = len(P)
    T, _ = _frames(P)
    arvore = cKDTree(P)

    def localiza(xz):  # s na linha P (projeção na tangente da amostra mais próxima)
        _, k = arvore.query(xz)
        return k * step + np.sum((xz - P[k]) * T[k], 1)
    soma_a, soma_v2, cnt = np.zeros(n), np.zeros(n), np.zeros(n)
    arqs = sorted(glob.glob(os.path.join(ROOT, 'garage61', '*Carlos Pace*.csv')))
    for arq in arqs:
        v = rg.le_volta(arq)
        with open(arq, encoding='utf-8') as f:
            va = np.array([float(r['VertAccel']) for r in csv.DictReader(f)])
        s = localiza(rg.aplica(aj, v['x'], v['z']))
        k = np.round(s / step).astype(int) % n
        np.add.at(soma_a, k, va); np.add.at(soma_v2, k, v['v'] ** 2); np.add.at(cnt, k, 1)
    ok = cnt > 0
    idx = np.arange(n)
    fill = lambda q: np.interp(idx, idx[ok], q[ok] / cnt[ok], period=n)
    A, V2 = fill(soma_a), fill(soma_v2)
    sig = lambda q: gaussian_filter1d(q, 15 / step, mode='wrap')
    g = 9.80665
    As = sig(A)
    out = {'voltas': len(arqs), 'VertAccel_med_g': round(float(A.mean() / g), 3)}
    for nome, (y, bank, kap) in pf_por_nome.items():
        dy = (np.roll(y, -1) - np.roll(y, 1)) / (2 * step)
        kv = (np.roll(y, -1) - 2 * y + np.roll(y, 1)) / step ** 2
        prev = sig((g * np.cos(np.arctan(dy)) + V2 * kv) * np.cos(bank) - V2 * kap * np.sin(bank))
        e = (As - prev) / g
        ec = e - e.mean()
        out[nome] = {'rms_g': round(float(np.sqrt(np.mean(ec ** 2))), 3), 'vies_g': round(float(e.mean()), 3),
                     'p95_abs_g': round(float(np.percentile(np.abs(ec), 95)), 3),
                     'dentro_0_15g_pct': round(100 * float(np.mean(np.abs(ec) <= 0.15)), 1),
                     'corr': round(float(np.corrcoef(As, prev)[0, 1]), 3) if np.std(prev) > 0 else None,
                     'pior_s': int(np.argmax(np.abs(ec)) * step), '_e': e}
    out['_A'], out['_s'] = As / g, idx * step
    return out


def conferir():
    rep = {}
    mdt = _r('mdt')
    a = np.asarray(mdt.a)
    rep['mdt'] = dict(mdt.m)
    rep['buracos_mdt'] = int(np.isnan(a).sum())
    pre = np.load(os.path.join(OUT, 'mdt_preenchido.npy'), mmap_mode='r')
    rep['mdt_preenchido_pct'] = round(100 * float(np.mean(pre)), 2)
    if _tem_piso():
        rep['piso'] = {k: v for k, v in _r('piso').m.items() if k != 'proj'}

    # emendas entre blocos LAZ: degrau nas linhas/colunas de borda de cada bloco × degrau típico ao lado
    blocos = json.load(open(os.path.join(OUT, 'blocos.json')))
    px = mdt.m['px']
    gx = np.abs(np.diff(a, axis=1))
    gy = np.abs(np.diff(a, axis=0))
    piores = []
    for b in blocos:
        for E in (b['minx'], b['maxx']):
            c = int(round((E - mdt.m['E0']) / px)) - 1
            if 2 <= c < gx.shape[1] - 2:
                r0 = max(0, int((mdt.m['N1'] - b['maxy']) / px)); r1 = min(a.shape[0], int((mdt.m['N1'] - b['miny']) / px))
                ok = ~pre[r0:r1, c] & ~pre[r0:r1, c + 1]
                if ok.sum() > 50:
                    borda = np.nanmedian(gx[r0:r1, c][ok]); viz = np.nanmedian(gx[r0:r1, c - 2][ok])
                    piores.append((b['cod'], 'E', round(float(borda), 3), round(float(viz), 3)))
        for N in (b['miny'], b['maxy']):
            r = int(round((mdt.m['N1'] - N) / px)) - 1
            if 2 <= r < gy.shape[0] - 2:
                c0 = max(0, int((b['minx'] - mdt.m['E0']) / px)); c1 = min(a.shape[1], int((b['maxx'] - mdt.m['E0']) / px))
                ok = ~pre[r, c0:c1] & ~pre[r + 1, c0:c1]
                if ok.sum() > 50:
                    borda = np.nanmedian(gy[r, c0:c1][ok]); viz = np.nanmedian(gy[r - 2, c0:c1][ok])
                    piores.append((b['cod'], 'N', round(float(borda), 3), round(float(viz), 3)))
    piores.sort(key=lambda t: t[2] - t[3], reverse=True)
    rep['emendas_n'] = len(piores)
    rep['emendas_pior'] = piores[:5]

    # ---- linha central antiga (data/track/track.json) e nova (interlagos.json), antes (mdt) × depois (piso)
    tr, step, secs = _linha_central()
    P = tr[:, [0, 2]]
    n = len(P)
    Pn, stepn, secsn, dn = _linha_nova()
    if _tem_piso():
        rep['registro_residuo'] = registro_residuo(dn)
    rep['medida_direta_linha_antiga'] = medida_direta(P)
    rep['medida_direta_linha_nova'] = medida_direta(Pn)
    fontes = ['mdt', 'piso'] if _tem_piso() else ['mdt']
    fd = fontes[-1]
    # 'mdt' = ANTES (só classe 2, camber de 2 pontos, sem REGISTRO); 'piso' = DEPOIS (piso, reta robusta, REGISTRO);
    # passos intermediários para atribuir a mudança: 'mdt_reg' (antes + REGISTRO), 'piso_2p' (piso, 2 pontos)
    variantes = {'mdt': ('mdt', '2pontos', False), 'mdt_reg': ('mdt', '2pontos', True),
                 'piso_2p': ('piso', '2pontos', True), 'piso': ('piso', 'robusto', True)}
    if not _tem_piso():
        variantes = {'mdt': ('mdt', '2pontos', False), 'mdt_reg': ('mdt', '2pontos', True)}

    def roda(Pl, stl, sel, v):
        global REGISTRO
        guarda = REGISTRO
        try:
            if not v[2]:
                REGISTRO = (0.0, 0.0)
            return perfil(Pl, stl, sel, v[0], metodo=v[1])
        finally:
            REGISTRO = guarda
    A = {k: roda(P, step, secs, v) for k, v in variantes.items()}
    Nv = {k: roda(Pn, stepn, secsn, v) for k, v in variantes.items()}
    dep = A[fd]
    rep['R_coluna6_7_concorda'] = round(float(np.mean(np.sum(dep['R'] * tr[:, 6:8], 1))), 3)
    s = dep['s']
    y, y_raw = dep['y'], dep['y_raw']
    srtm = _srtm()(P[:, 0], P[:, 1])
    atual = tr[:, 1]
    rep['desnivel_antes_depois'] = [A['mdt']['desnivel'], dep['desnivel']]
    rep['desnivel_linha_nova_antes_depois'] = [Nv['mdt']['desnivel'], Nv[fd]['desnivel']]
    rep['desnivel_srtm'] = round(float(srtm.max() - srtm.min()), 2)
    rep['desnivel_track_json'] = round(float(atual.max() - atual.min()), 2)
    rep['lidar_min_max_abs'] = [round(float(y.min()), 2), round(float(y.max()), 2)]
    rep['s_min_max'] = [float(s[np.argmin(y)]), float(s[np.argmax(y)])]
    yant = A['mdt']['y']
    dd = y - yant
    md = float(np.median(dd))
    rep['depois_menos_antes_m'] = {'mediana': round(md, 3), 'rms_sem_offset': round(float(np.std(dd)), 3),
                                   'max_abs_sem_offset': round(float(np.abs(dd - md).max()), 3),
                                   's_do_max': float(s[np.argmax(np.abs(dd - md))])}
    rep['trocas_mediana_antes_depois'] = [A['mdt']['trocas_mediana'], dep['trocas_mediana']]
    off = float(np.median(y - srtm))
    dif = y - srtm - off
    rep['dif_srtm_rms'] = round(float(np.sqrt(np.mean(dif ** 2))), 2)
    yrel = y - y.min()
    dif2 = yrel - (atual - atual.min())
    rep['dif_track_json_rms'] = round(float(np.sqrt(np.mean(dif2 ** 2))), 2)
    por = []
    k100 = int(100 / step)
    for k in range(0, n, k100):
        w = slice(k, min(n, k + k100))
        por.append((int(s[k]), round(float(yrel[k]), 2), round(float(yant[k] - yant.min()), 2),
                    round(float(np.mean(dd[w]) - md), 3),
                    round(float(np.degrees(np.mean(A['mdt']['bank'][w]))), 2),
                    round(float(np.degrees(np.mean(dep['bank'][w]))), 2), round(float(np.mean(dif2[w])), 1)))
    rep['a_cada_100m_s_hrelDepois_hrelAntes_depoisMenosAntes_bankAntes_bankDepois_difTrack'] = por

    # ruído ao longo da pista (amostras sem suavização) na linha antiga
    for f in fontes:
        d2 = np.abs(np.roll(A[f]['y_raw'], -1) - 2 * A[f]['y_raw'] + np.roll(A[f]['y_raw'], 1))
        rep[f'ruido_2a_dif_cm_p50_p95_{f}'] = [round(100 * float(np.median(d2)), 2), round(100 * float(np.percentile(d2, 95)), 2)]
        bb = np.degrees(A[f]['bank_bruto'])
        rep[f'camber_bruto_ruido_graus_{f}'] = round(float(np.std(bb - gaussian_filter1d(bb, 10 / step, mode='wrap'))), 2)

    # camber por curva nas duas linhas, antes × depois
    def tabela(pfs):
        out = []
        for i, c in enumerate(pfs[fd]['curvas']):
            out.append({'nome': c['nome'], 's': c['s'], 'raio': c['raio_med'], 'vira': c['vira'],
                        'bank_med_antes': pfs['mdt']['curvas'][i]['bank_med_graus'],
                        'com_registro': pfs['mdt_reg']['curvas'][i]['bank_med_graus'],
                        'piso_2pontos': pfs['piso_2p']['curvas'][i]['bank_med_graus'] if 'piso_2p' in pfs else None,
                        'bank_med': c['bank_med_graus'], 'bank_max': c['bank_max_graus'],
                        'fora_mais_alto': c['fora_mais_alto'],
                        'fora_mais_alto_antes': pfs['mdt']['curvas'][i]['fora_mais_alto']})
        return out
    rep['camber_curvas_linha_antiga'] = tabela(A)
    rep['camber_curvas_linha_nova'] = tabela(Nv)
    for nome, pfs in (('antiga', A), ('nova', Nv)):
        b = pfs[fd]['bank']
        rep[f'camber_med_abs_max_graus_linha_{nome}'] = [round(float(np.degrees(np.median(np.abs(b)))), 2),
                                                         round(float(np.degrees(np.abs(b).max())), 2)]
    # nova × antiga no mesmo lugar (ponto mais próximo da nova para cada amostra da antiga)
    from scipy.spatial import cKDTree
    _, j = cKDTree(Pn).query(P)
    db = np.degrees(Nv[fd]['bank'][j] - dep['bank'])
    rep['camber_nova_menos_antiga_graus_rms_max_s'] = [round(float(np.sqrt(np.mean(db ** 2))), 2),
                                                       round(float(np.abs(db).max()), 2), float(s[np.argmax(np.abs(db))])]
    dy = Nv[fd]['y'][j] - y
    rep['altitude_nova_menos_antiga_m_rms_max_s'] = [round(float(np.sqrt(np.mean(dy ** 2))), 3),
                                                     round(float(np.abs(dy).max()), 3), float(s[np.argmax(np.abs(dy))])]

    # dentes entre células vizinhas sob o asfalto (linha nova)
    rep['dentes_sob_asfalto'] = {f: dentes(dn, f) for f in fontes}

    # VertAccel do iRacing × v² κ_v (linha antiga, onde o GPS já está mapeado por tools/ref/ref_garage61.py)
    try:
        cand = {'track_json_atual': (atual, np.zeros(n), dep['kap'])}
        for f in A:
            cand[f'{f}_sig4'] = (A[f]['y'], A[f]['bank'], dep['kap'])
        if 'piso' in fontes:
            for sy in (2, 6, 8, 12):
                cand[f'piso_sig{sy}'] = (perfil(P, step, secs, 'piso', sig_y=sy)['y'], dep['bank'], dep['kap'])
            cand['piso_sig4_sem_bank'] = (y, np.zeros(n), dep['kap'])
            cand['plano'] = (np.full(n, y.mean()), np.zeros(n), dep['kap'])
        va = vertaccel(cand, step, P)
        e_s = {k: v.pop('_e') for k, v in va.items() if isinstance(v, dict)}
        As, s_va = va.pop('_A'), va.pop('_s')
        rep['vertaccel'] = va
        _grafico(os.path.join(OUT, 'perfil_vertaccel.png'), s_va,
                 [('VertAccel iRacing (g, média das voltas, σ15 m)', As, (0, 0, 0)),
                  (f'previsto {fd} σ4 m (g)', As - e_s[f'{fd}_sig4'], (200, 30, 30)),
                  ('previsto track.json atual (g)', As - e_s['track_json_atual'], (30, 150, 60))],
                 [(c['name'], c['s0'], 0) for c in secs],
                 'Interlagos: aceleração vertical medida × geometria (linha antiga)', passo_y=0.25)
    except Exception as ex:  # telemetria ausente não impede o resto
        rep['vertaccel'] = f'não feito: {ex!r}'

    marcas = [(c['name'], c['s0'], 0) for c in secs]
    _grafico(os.path.join(OUT, 'perfil_altitude.png'), s,
             [('LiDAR piso 2+20 (mediana + σ4 m)', yrel, (200, 30, 30)),
              ('LiDAR só classe 2 (antes)', yant - yant.min(), (240, 150, 40)),
              ('SRTM 30 m (alinhado pela mediana)', srtm - off - y.min(), (40, 90, 200)),
              ('track.json atual (y)', atual - atual.min(), (30, 150, 60))],
             marcas, f'Interlagos: altitude sob a linha central atual (desnível LiDAR {dep["desnivel"]} m, oficial ~43 m)')
    _grafico(os.path.join(OUT, 'perfil_camber.png'), s,
             [('camber piso ±3,5 m, σ10 m (graus, + = direita mais alta)', np.degrees(dep['bank']), (200, 30, 30)),
              ('camber só classe 2 (antes)', np.degrees(A['mdt']['bank']), (240, 150, 40)),
              ('camber piso na linha nova (no s da nova)', np.interp(s, Nv[fd]['s'], np.degrees(Nv[fd]['bank'])), (40, 90, 200)),
              ('curvatura × 1000 (+ = vira à direita)', dep['kap'] * 1000, (120, 120, 120))],
             marcas, 'Interlagos: camber medido sob a linha central atual e a nova')
    np.savez(os.path.join(OUT, 'perfil_linha_atual.npz'), s=s, y=y, y_raw=y_raw, srtm=srtm, bank=dep['bank'],
             kap=dep['kap'], y_mdt=yant, bank_mdt=A['mdt']['bank'])
    np.savez(os.path.join(OUT, 'perfil_linha_nova.npz'), s=Nv[fd]['s'], y=Nv[fd]['y'], y_raw=Nv[fd]['y_raw'],
             bank=Nv[fd]['bank'], kap=Nv[fd]['kap'])

    # grade de relevo do cenário (mesmo formato de imola-terrain.json: absoluto, células de 8 m, média 4x4)
    STEP_T = 8.0
    E0, N1, px = mdt.m['E0'], mdt.m['N1'], mdt.m['px']
    E1, N0 = E0 + a.shape[1] * px, N1 - a.shape[0] * px
    cx, cz = utm_para_jogo(np.array([E0, E1, E0, E1]), np.array([N0, N0, N1, N1]))
    x0, x1 = math.ceil(max(cx[0], cx[2]) + 4), math.floor(min(cx[1], cx[3]) - 4)
    z0, z1 = math.ceil(max(cz[2], cz[3]) + 4), math.floor(min(cz[0], cz[1]) - 4)
    nx, nz = int((x1 - x0) // STEP_T) + 1, int((z1 - z0) // STEP_T) + 1
    gxx, gzz = np.meshgrid(x0 + np.arange(nx) * STEP_T, z0 + np.arange(nz) * STEP_T)
    acc = np.zeros(gxx.shape)
    for dx in (-3, -1, 1, 3):
        for dz in (-3, -1, 1, 3):
            acc += altura((gxx + dx).ravel(), (gzz + dz).ravel()).reshape(gxx.shape)
    acc /= 16.0
    json.dump({'x0': float(x0), 'z0': float(z0), 'step': STEP_T, 'nx': nx, 'nz': nz,
               'h': [round(float(v), 1) for v in acc.ravel()]},
              open(os.path.join(HERE, 'interlagos-terrain.json'), 'w'))
    rep['terreno_grade'] = {'x0': x0, 'z0': z0, 'nx': nx, 'nz': nz, 'step': STEP_T,
                            'h_min_max': [round(float(acc.min()), 1), round(float(acc.max()), 1)]}
    copa_a = np.asarray(_r('copa').a)
    rep['copa_p50_p99'] = [round(float(np.nanpercentile(copa_a, 50)), 2), round(float(np.nanpercentile(copa_a, 99)), 2)]
    json.dump(rep, open(os.path.join(OUT, 'conferencia.json'), 'w', encoding='utf8'), ensure_ascii=False, indent=1)
    return rep


if __name__ == '__main__':
    if '--conferir' in sys.argv:
        r = conferir()
        for k, v in r.items():
            if isinstance(v, list) and v and isinstance(v[0], (dict, tuple, list)):
                print(k)
                for it in v:
                    print('  ', it)
            else:
                print(f'{k}: {v}')
    else:
        print(__doc__ if __doc__ else 'uso: python tools/tracks/interlagos/lidar.py --conferir')
