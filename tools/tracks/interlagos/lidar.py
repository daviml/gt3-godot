# Relevo LiDAR de Interlagos (Prefeitura de São Paulo / GeoSampa, levantamento a laser 2017, nuvem LAZ em
# SIRGAS 2000 / UTM 23S, EPSG:31983) já rasterizado por download_lidar.py em build/interlagos/lidar/:
#   mdt.npy + mdt.json        terreno nu (pontos classe 2), 0,5 m, buracos preenchidos (mdt_preenchido.npy = máscara)
#   mds.npy + mds.json        superfície (maior retorno por célula, sem ruído), 1 m
#   copa.npy                  mds - mdt reamostrado em 1 m (altura de copa/prédio), para a etapa de árvores
#
# Uso por outra etapa (de REPOS/gt3-godot):
#   import sys; sys.path.insert(0, 'tools/tracks/interlagos'); import lidar
#   y = lidar.altura(x, z)            # altitude (m, absoluta) do terreno nu em (x, z) do jogo, arrays ou escalares
#   h = lidar.copa(x, z)              # altura de copa/prédio acima do terreno (m)
#   E, N = lidar.jogo_para_utm(x, z)  # conversão usada (x = leste, z = sul; origem lat -23.7036, lon -46.6997)
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


def jogo_para_utm(x, z):
    return ll_para_utm(*jogo_para_ll(x, z))


def utm_para_jogo(E, N):
    return ll_para_jogo(*utm_para_ll(E, N))


# ---- amostragem dos rasters (grade UTM alinhada: célula (r, c) tem centro E0 + (c + 0,5) px, N1 - (r + 0,5) px)
class Raster:
    def __init__(self, nome):
        self.a = np.load(os.path.join(OUT, nome + '.npy'), mmap_mode='r')
        self.m = json.load(open(os.path.join(OUT, nome + '.json')))

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


def altura(x, z, order=1):
    """Altitude absoluta (m) do terreno nu (MDT 0,5 m) em coordenadas do jogo."""
    return _r('mdt').jogo(x, z, order)


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


def _linha_central():
    d = json.load(open(os.path.join(ROOT, 'data', 'track', 'track.json')))
    a = np.array(d['s'], np.float64).reshape(d['n'], d['stride'])
    return a, float(d['step']), d['sections']


def _grafico(path, s, series, marcas, titulo):
    """Gráfico de linhas simples com PIL (sem matplotlib)."""
    from PIL import Image, ImageDraw
    W, H, ml, mr, mt, mb = 1600, 700, 70, 20, 40, 60
    img = Image.new('RGB', (W, H), 'white')
    d = ImageDraw.Draw(img)
    ys = np.concatenate([v for _, v, _ in series])
    y0, y1 = math.floor(np.nanmin(ys) / 5) * 5, math.ceil(np.nanmax(ys) / 5) * 5
    s0, s1 = float(s[0]), float(s[-1])
    X = lambda v: ml + (v - s0) / (s1 - s0) * (W - ml - mr)
    Y = lambda v: H - mb - (v - y0) / (y1 - y0) * (H - mt - mb)
    for yv in range(int(y0), int(y1) + 1, 5):
        d.line([(ml, Y(yv)), (W - mr, Y(yv))], fill=(225, 225, 225))
        d.text((8, Y(yv) - 6), f'{yv:.0f} m', fill='black')
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


def conferir():
    rep = {}
    mdt, mds = _r('mdt'), _r('mds')
    a = np.asarray(mdt.a)
    rep['mdt'] = dict(mdt.m)
    rep['buracos_mdt'] = int(np.isnan(a).sum())
    pre = np.load(os.path.join(OUT, 'mdt_preenchido.npy'), mmap_mode='r')
    rep['mdt_preenchido_pct'] = round(100 * float(np.mean(pre)), 2)

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

    # linha central atual
    tr, step, secs = _linha_central()
    P = tr[:, [0, 2]]
    n = len(P)
    s = np.arange(n) * step
    T = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    T /= np.linalg.norm(T, axis=1)[:, None]
    R = np.stack([-T[:, 1], T[:, 0]], 1)  # direita de quem corre (x, z), igual a imola/build_track.py
    rep['R_coluna6_7_concorda'] = round(float(np.mean(np.sum(R * tr[:, 6:8], 1))), 3)
    sig = lambda v, m: gaussian_filter1d(v, m / step, mode='wrap')

    y_raw = altura(P[:, 0], P[:, 1])
    y_med = median_filter(y_raw, size=int(65 / step) | 1, mode='wrap')
    y = np.where(np.abs(y_raw - y_med) > 0.35, y_med, y_raw)
    y = sig(median_filter(y, size=5, mode='wrap'), 4)
    no_pre = map_coordinates(np.asarray(pre, np.float32),
                             [(mdt.m['N1'] - jogo_para_utm(P[:, 0], P[:, 1])[1]) / px - 0.5,
                              (jogo_para_utm(P[:, 0], P[:, 1])[0] - mdt.m['E0']) / px - 0.5], order=0)
    rep['centro_em_celula_preenchida_pct'] = round(100 * float(np.mean(no_pre > 0.5)), 2)
    srtm = _srtm()(P[:, 0], P[:, 1])
    atual = tr[:, 1]
    rep['desnivel_lidar'] = round(float(y.max() - y.min()), 2)
    rep['desnivel_lidar_bruto'] = round(float(y_raw.max() - y_raw.min()), 2)
    rep['desnivel_srtm'] = round(float(srtm.max() - srtm.min()), 2)
    rep['desnivel_track_json'] = round(float(atual.max() - atual.min()), 2)
    rep['lidar_min_max_abs'] = [round(float(y.min()), 2), round(float(y.max()), 2)]
    rep['s_min_max'] = [float(s[np.argmin(y)]), float(s[np.argmax(y)])]
    off = float(np.median(y - srtm))
    rep['offset_mediano_lidar_menos_srtm'] = round(off, 2)
    dif = y - srtm - off
    rep['dif_srtm_rms'] = round(float(np.sqrt(np.mean(dif ** 2))), 2)
    rep['dif_srtm_max'] = round(float(np.abs(dif).max()), 2)
    yrel = y - y.min()
    dif2 = yrel - (atual - atual.min())
    rep['dif_track_json_rms'] = round(float(np.sqrt(np.mean(dif2 ** 2))), 2)
    por = []
    for k in range(0, n, int(100 / step)):
        w = slice(k, min(n, k + int(100 / step)))
        por.append((int(s[k]), round(float(yrel[k]), 1), round(float(np.mean(dif[w])), 1), round(float(np.mean(dif2[w])), 1)))
    rep['a_cada_100m_s_hrel_difSRTM_difTrack'] = por
    # galeria/ponte: onde a mediana substituiu
    rep['amostras_corrigidas_pela_mediana'] = int(np.sum(np.abs(y_raw - y_med) > 0.35))

    # camber a ±3,5 m
    HB = 3.5
    hl = altura(P[:, 0] - R[:, 0] * HB, P[:, 1] - R[:, 1] * HB)
    hr = altura(P[:, 0] + R[:, 0] * HB, P[:, 1] + R[:, 1] * HB)
    hl = np.where(np.abs(hl - y_med) > 0.8, y, hl)
    hr = np.where(np.abs(hr - y_med) > 0.8, y, hr)
    bank = sig(np.arctan2(median_filter(hr - hl, size=7, mode='wrap'), 2 * HB), 10)
    # curvatura com sinal: > 0 = curva para a direita (para o lado de R)
    dT = np.roll(T, -2, 0) - np.roll(T, 2, 0)
    kap = sig(np.sum(dT * R, 1) / (4 * step), 6)
    curvas = []
    for sc in secs:
        i0, i1 = int(sc['s0'] / step), int(sc['s1'] / step)
        idx = np.arange(i0, i1) % n
        km = float(np.mean(kap[idx]))
        bm = float(np.degrees(np.mean(bank[idx])))
        lado = 'dir' if km > 0 else 'esq'
        # curva para a direita: fora = esquerda -> esperado hl > hr -> bank < 0
        coerente = (bm < 0) if km > 0 else (bm > 0)
        reta = abs(km) < 1 / 400
        curvas.append({'nome': sc['name'], 's': [sc['s0'], sc['s1']], 'raio_med': round(1 / abs(km), 0) if km else None,
                       'vira': lado, 'bank_med_graus': round(bm, 2),
                       'bank_max_graus': round(float(np.degrees(bank[idx][np.argmax(np.abs(bank[idx]))])), 2),
                       'fora_mais_alto': None if reta else bool(coerente)})
    rep['camber_curvas'] = curvas
    rep['camber_med_abs_graus'] = round(float(np.degrees(np.median(np.abs(bank)))), 2)
    rep['camber_max_abs_graus'] = round(float(np.degrees(np.abs(bank).max())), 2)

    marcas = [(c['name'], c['s0'], 0) for c in secs]
    _grafico(os.path.join(OUT, 'perfil_altitude.png'), s,
             [('LiDAR GeoSampa 2017 (mediana + σ4 m)', yrel, (200, 30, 30)),
              ('SRTM 30 m (alinhado pela mediana)', srtm - off - y.min(), (40, 90, 200)),
              ('track.json atual (y)', atual - atual.min(), (30, 150, 60))],
             marcas, f'Interlagos: altitude sob a linha central atual (desnível LiDAR {rep["desnivel_lidar"]} m, oficial ~43 m)')
    _grafico(os.path.join(OUT, 'perfil_camber.png'), s,
             [('camber LiDAR ±3,5 m, σ10 m (graus, + = direita mais alta)', np.degrees(bank), (200, 30, 30)),
              ('curvatura × 1000 (+ = vira à direita)', kap * 1000, (120, 120, 120))],
             marcas, 'Interlagos: camber medido sob a linha central atual')
    np.savez(os.path.join(OUT, 'perfil_linha_atual.npz'), s=s, y=y, y_raw=y_raw, srtm=srtm, bank=bank, kap=kap)

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
    json.dump(rep, open(os.path.join(OUT, 'conferencia.json'), 'w'), ensure_ascii=False, indent=1)
    return rep


if __name__ == '__main__':
    if '--conferir' in sys.argv:
        r = conferir()
        for k, v in r.items():
            if k in ('a_cada_100m_s_hrel_difSRTM_difTrack', 'camber_curvas'):
                print(k)
                for it in v:
                    print('  ', it)
            else:
                print(f'{k}: {v}')
    else:
        print(__doc__ if __doc__ else 'uso: python tools/tracks/interlagos/lidar.py --conferir')
