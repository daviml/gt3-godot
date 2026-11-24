# Fase 2B, etapa D2 (PLANO-INTERLAGOS-DETALHES.md): traçado em planta de Interlagos refeito pelo processo de
# Laguna/Imola (GUIA-PISTAS.md §2), no MESMO referencial do mundo de hoje (o do OSM/cenário).
#
#   tools/tracks/interlagos/interlagos.json   TrackData para a classe Track do web / tools/pista.ts: origin, points
#       (a cada 4 m da linha de 1 m), widthLeft/Right, kerbLeft/Right, wallLeft/Right, sections + `medicao`
#       (de onde veio cada trecho: centro, bordas, muros; ignorado pelo Track)
#   tools/tracks/interlagos/s_antigo_novo.json  s do data/track/track.json atual (a cada 2 m) → s novo + lateral
#   build/interlagos/tracado/                   imagens de conferência e diag.json com todos os números
#
# Entradas (só leitura): data/track/track.json (linha atual, altitude, zebras/muros da física), data/track/
#   visual_profile.json (muros desenhados hoje), tools/tracks/interlagos/interlagos-perfil-sat.json e perfil_zebras.py
#   (Fase 2: confiança da borda, candidatos a muro, zebras decididas), build/interlagos/sat19.npy|json (mosaico Esri
#   z19), build/interlagos/osm/osm.xml + interlagos-osm.json (build_osm.py), garage61/*José Carlos Pace*.csv.
#
# Método (números no LEIA-ME.md e no relatório da etapa):
#   1) referencial: deslocamento global de OSM, GPS (cru e ajustado) e satélite contra a linha atual. O mundo fica
#      no referencial da linha atual (= OSM a 0,4 m); o satélite é registrado nele pelo deslocamento medido.
#   2) linha central: parte da linha atual (1 m), mede as bordas do asfalto no satélite (perpendicular, 0,25 m),
#      recentraliza pelo meio das bordas (só onde a borda é confiável; nos buracos, interpolação da vizinhança),
#      suaviza e itera. s = 0 no ponto do mundo onde está o s = 0 de hoje.
#   3) larguras pelas bordas medidas (mediana robusta em janela), buracos pela vizinhança.
#   4) zebras = tabela ZEBRAS do perfil_zebras.py (s antigo → s novo); largura física pela classe.
#      muros = OSM barrier=* > satélite (conf. alta, confirmado pelo perfil) > perfil atual ("não medido").
#   5) altitude = a de hoje levada por projeção (ponto único para o LiDAR: altitude_e_camber()).
#
# uso (de REPOS/gt3-godot): python tools/tracks/interlagos/build_track.py [--lidar] [--sem-imagens]
#   --lidar  usa tools/tracks/interlagos/lidar.py (altura(x, z)) para altitude e camber (`bank`). Sem a opção, a
#            altitude é a do track.json atual e não há `bank` (decisão da etapa D2).
import csv
import glob
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter1d, map_coordinates, median_filter, percentile_filter
from scipy.optimize import minimize
from scipy.spatial import cKDTree

sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, 'build', 'interlagos')
IMG = os.path.join(RAW, 'tracado')
os.makedirs(IMG, exist_ok=True)
sys.path.insert(0, HERE)
import perfil_zebras as PZ  # noqa: E402  (só as tabelas e avalia(); o main dele não roda no import)

LAT0, LON0 = -23.7036, -46.6997
ML = 111320.0
MO = ML * math.cos(math.radians(LAT0))
NT = 2 ** 19
OFICIAL = 4309.0
DS = 1.0          # passo de trabalho (m)
K_OUT = 4         # pontos do TrackData a cada 4 m (como Imola; pista.ts escala as seções por points*4)
KERB_N, KERB_S = 1.2, 2.2   # largura física das zebras: classe normal / larga de saída (Track: KERB_WIDTH/EXIT)
DIAG = {}


def say(*a):
    print(*a, flush=True)


# ================================================================ geometria
def resample_loop(P, step, start=0.0):
    seg = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    L = s[-1]
    n = int(round(L / step))
    t = (start + np.arange(n) * (L / n)) % L
    Q = np.vstack([P, P[:1]])
    return np.stack([np.interp(t, s, Q[:, k]) for k in range(P.shape[1])], 1), L


def frames(P):
    T = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    T /= np.linalg.norm(T, axis=1)[:, None]
    return T, np.stack([-T[:, 1], T[:, 0]], 1)  # R = direita de quem corre (x leste, z sul), igual ao Track


def length(P):
    return float(np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1).sum())


class Linha:
    """polilinha fechada; projeta pontos → (s, d) com d > 0 à direita."""

    def __init__(self, P):
        self.P = np.asarray(P, float)
        self.seg = np.roll(self.P, -1, 0) - self.P
        self.sl = np.linalg.norm(self.seg, axis=1)
        self.s = np.concatenate([[0], np.cumsum(self.sl)[:-1]])
        self.L = float(self.sl.sum())
        self.tree = cKDTree(self.P)
        self.n = len(self.P)

    def proj(self, Q):
        Q = np.asarray(Q, float)
        _, k = self.tree.query(Q)
        best = None
        for j in ((k - 1) % self.n, k):
            a = self.P[j]
            sg = self.seg[j]
            t = np.clip(((Q - a) * sg).sum(1) / self.sl[j] ** 2, 0, 1)
            f = a + sg * t[:, None]
            dist = np.linalg.norm(Q - f, axis=1)
            s = self.s[j] + t * self.sl[j]
            # d com sinal: (-sz, sx) é a direita
            d = ((Q - f) * np.stack([-sg[:, 1], sg[:, 0]], 1)).sum(1) / self.sl[j]
            if best is None:
                best = [dist, s, d]
            else:
                m = dist < best[0]
                best = [np.where(m, dist, best[0]), np.where(m, s, best[1]), np.where(m, d, best[2])]
        return best[1] % self.L, best[2]


def interp_c(arr, s, step, L):
    """valor de uma série periódica (amostras a cada `step`) em s (m)."""
    arr = np.asarray(arr, float)
    u = (np.asarray(s) % L) / step
    i0 = np.floor(u).astype(int) % len(arr)
    i1 = (i0 + 1) % len(arr)
    f = u - np.floor(u)
    return arr[i0] * (1 - f) + arr[i1] * f


def circ_gauss(a, sigma):
    return gaussian_filter1d(a, sigma, axis=0, mode='wrap')


def fill_circ(a, ok):
    n = len(a)
    g = np.where(ok)[0]
    if len(g) == 0:
        return a.copy()
    return np.interp(np.arange(n), g, a[g], period=n)


def runs(mask):
    """trechos (i0, i1) inclusivos de True num vetor circular (o que passa pelo fim vira i1 >= n)."""
    n = len(mask)
    out, j = [], 0
    while j < n:
        if mask[j]:
            k = j
            while k + 1 < n and mask[k + 1]:
                k += 1
            out.append([j, k])
            j = k + 1
        else:
            j += 1
    if len(out) > 1 and out[0][0] == 0 and out[-1][1] == n - 1:
        a = out.pop()
        b = out.pop(0)
        out.append([a[0], b[1] + n])
    return out


def curvatura(P, k=5):
    T, _ = frames(P)
    a = np.roll(T, k, 0)
    b = np.roll(T, -k, 0)
    cross = a[:, 0] * b[:, 1] - a[:, 1] * b[:, 0]  # > 0 = direita (igual ao Track)
    return np.arcsin(np.clip(cross, -1, 1)) / (2 * k * DS)


# ================================================================ entradas
# A linha "atual" (referencial do mundo, altitude, zebras/muros da física de antes) é a do track.json que o jogo
# usava ATÉ a etapa E da 2B (exportado do web, 4.294 m). Depois da etapa E o data/track/track.json passa a ser o
# desta pista; a cópia antiga fica em build/interlagos/track_antigo.json (recriar com
# `git show f92abf5:data/track/track.json > build/interlagos/track_antigo.json`).
TRACK_ANTIGO = os.path.join(RAW, 'track_antigo.json')
if not os.path.exists(TRACK_ANTIGO):
    _cand = json.load(open(os.path.join(ROOT, 'data', 'track', 'track.json'), encoding='utf-8'))
    if _cand.get('n') != 2147:
        raise SystemExit('falta build/interlagos/track_antigo.json (o data/track/track.json já é o novo): '
                         'git show f92abf5:data/track/track.json > build/interlagos/track_antigo.json')
    os.makedirs(RAW, exist_ok=True)
    json.dump(_cand, open(TRACK_ANTIGO, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
t0 = json.load(open(TRACK_ANTIGO, encoding='utf-8'))
A0 = np.array(t0['s'], float).reshape(t0['n'], t0['stride'])
L0 = float(t0['length'])
N0 = t0['n']
P0 = A0[:, [0, 2]]
Y0 = A0[:, 1]
_, R0 = frames(P0)
WL0, WR0, KL0, KR0, WAL0, WAR0 = (A0[:, c] for c in (8, 9, 10, 11, 14, 15))
lin0 = Linha(P0)
s0_old = np.arange(N0) * 2.0

osm = json.load(open(os.path.join(HERE, 'interlagos-osm.json'), encoding='utf-8'))
O1 = np.array(osm['raceway'])
psat = json.load(open(os.path.join(HERE, 'interlagos-perfil-sat.json'), encoding='utf-8'))
meta = json.load(open(os.path.join(RAW, 'sat19.json')))
sat = np.load(os.path.join(RAW, 'sat19.npy'))
CH = [sat[..., k].astype(np.float32) for k in range(3)]


def pix(x, z):
    lat = LAT0 - np.asarray(z) / ML
    lon = LON0 + np.asarray(x) / MO
    tx = (lon + 180.0) / 360.0 * NT
    lr = np.radians(lat)
    ty = (1.0 - np.log(np.tan(lr) + 1.0 / np.cos(lr)) / math.pi) / 2.0 * NT
    return (ty - meta['ty0']) * 256.0 - 0.5, (tx - meta['tx0']) * 256.0 - 0.5


def rgb(x, z):
    r, c = pix(np.ravel(x), np.ravel(z))
    return np.stack([map_coordinates(ch, [r, c], order=1, mode='constant') for ch in CH], -1).reshape(np.shape(x) + (3,))


# voltas do Garage 61 (mesma leitura de tools/ref/ref_garage61.py)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'ref'))
import ref_garage61 as G61  # noqa: E402

ARQS = sorted(glob.glob(os.path.join(ROOT, 'garage61', '*Carlos Pace*.csv')))
VOLTAS = []
for a in ARQS:
    v = G61.le_volta(a)
    nome = G61.slug(os.path.basename(a))[0]
    with open(a, encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    v['lat_g'] = np.array([float(r['LatAccel']) for r in rows])
    v['nome'] = nome
    VOLTAS.append(v)
say(f'{len(VOLTAS)} voltas do Garage 61')
AJ0 = json.load(open(os.path.join(ROOT, 'build', 'ref', 'interlagos', 'ajuste_gps.json')))['ajuste']


def sim(f, x, z):
    c, s = math.cos(f[2]), math.sin(f[2])
    X, Z = (x - AJ0['cx']) * f[3], (z - AJ0['cz']) * f[3]
    return np.stack([AJ0['cx'] + c * X - s * Z + f[0], AJ0['cz'] + s * X + c * Z + f[1]], 1)


def fit_gps(lin, lim_fn, f0, livre=(0, 1, 2, 3), sub=6):
    """ajuste (dx, dz, θ, escala) único das 6 voltas (mesmo sistema de coordenadas do iRacing) que minimiza o
    quanto o carro sai de [−lim, +lim] da linha (lim_fn(s, d) → limite daquele lado)."""
    x = np.concatenate([v['x'][::sub] for v in VOLTAS])
    z = np.concatenate([v['z'][::sub] for v in VOLTAS])
    f0 = np.array(f0, float)

    def loss(p):
        f = f0.copy()
        f[list(livre)] = p
        s, d = lin.proj(sim(f, x, z))
        o = np.abs(d) - lim_fn(s, d)
        return float(np.mean(np.where(o > 0, o * o, 0.0)))

    r = minimize(loss, f0[list(livre)], method='Nelder-Mead',
                 options={'xatol': 1e-4, 'fatol': 1e-6, 'maxiter': 2000})
    f = f0.copy()
    f[list(livre)] = r.x
    return f, r.fun


# ================================================================ 1) referencial
def lsq_transl(R, c, cuts=(99, 3.0, 1.5)):
    """c ≈ R·v (deslocamento lateral explicado por uma translação global v), robusto."""
    v = np.zeros(2)
    for cut in cuts:
        m = np.abs(c - R @ v) < cut
        v = np.linalg.lstsq(R[m], c[m], rcond=None)[0]
    m = np.abs(c - R @ v) < cuts[-1]
    return v, float(np.median(np.abs(c[m] - R[m] @ v)))


# meio do asfalto da linha atual (wl ≠ wr): é o que o satélite e o OSM representam
M0 = P0 + R0 * ((WR0 - WL0) / 2)[:, None]
s_o, d_o = Linha(M0).proj(O1)
_, k_o = Linha(M0).tree.query(O1)
v_osm, r_osm = lsq_transl(R0[k_o], d_o)
say(f'OSM × linha atual: OSM = atual + ({v_osm[0]:+.2f}, {v_osm[1]:+.2f}) m; |d| mediana {np.median(np.abs(d_o)):.2f}, '
    f'p95 {np.percentile(np.abs(d_o), 95):.2f}; OSM {length(O1):.1f} m')
DIAG['referencial'] = {'osm_menos_atual': v_osm.round(2).tolist(), 'osm_d_mediana': round(float(np.median(np.abs(d_o))), 2),
                       'osm_d_p95': round(float(np.percentile(np.abs(d_o), 95)), 2), 'osm_comprimento': round(length(O1), 1)}

# GPS cru: só translação (θ = 0, escala 1) e ajuste completo, contra a linha atual com as larguras de hoje
lim0 = lambda s, d: np.where(d > 0, interp_c(WR0, s, 2, L0), interp_c(WL0, s, 2, L0))
f_tr, _ = fit_gps(lin0, lim0, [0, 0, 0, 1], livre=(0, 1))
gps_cru_menos_atual = -np.array(f_tr[:2])
say(f'GPS cru × linha atual (só translação): GPS = atual + ({gps_cru_menos_atual[0]:+.2f}, {gps_cru_menos_atual[1]:+.2f}) m')
# rotação e escala do ajuste da Fase 0 levam a quanto no meio da pista?
DIAG['referencial']['gps_cru_menos_atual_translacao'] = gps_cru_menos_atual.round(2).tolist()
DIAG['referencial']['ajuste_fase0'] = AJ0


# ================================================================ 2) bordas no satélite
D = np.arange(-18.0, 18.001, 0.25)
I0 = int(np.argmin(np.abs(D)))
pit = [np.array(p) for p in osm['pitLaneOsm']]


def dist_pit(X, Z):
    out = np.full(X.shape, np.inf)
    for pl in pit:
        for a, b in zip(pl[:-1], pl[1:]):
            dd = b - a
            den = float(dd @ dd)
            if den < 1e-6:
                continue
            t = np.clip(((X - a[0]) * dd[0] + (Z - a[1]) * dd[1]) / den, 0, 1)
            out = np.minimum(out, np.hypot(X - a[0] - dd[0] * t, Z - a[1] - dd[1] * t))
    return out


def unroll(P, off):
    T, R = frames(P)
    acc = []
    for a in (-0.4, 0.0, 0.4):
        X = P[:, 0, None] + T[:, 0, None] * a + R[:, 0, None] * D[None] + off[0]
        Z = P[:, 1, None] + T[:, 1, None] * a + R[:, 1, None] * D[None] + off[1]
        acc.append(rgb(X, Z))
    X = P[:, 0, None] + R[:, 0, None] * D[None]
    Z = P[:, 1, None] + R[:, 1, None] * D[None]
    return np.median(np.stack(acc), 0), dist_pit(X, Z)


def mede(P, off):
    """bordas do asfalto (distância do centro P ao fim do asfalto / começo da linha branca) por amostra e lado,
    + fração de sombra junto da borda. Asfalto = cinza neutro perto da cor de referência local (o mosaico mistura
    fotos: o asfalto vai de quase preto a cinza-claro); fora = branco/zebra/vermelho/verde/grama/bege/pit lane."""
    img, dp = unroll(P, off)
    Rr, Gg, Bb = img[..., 0], img[..., 1], img[..., 2]
    v = img.mean(2)
    st = img.max(2) - img.min(2)
    ref = median_filter(np.median(img[:, np.abs(D) <= 2.0, :], axis=1), size=(21, 1), mode='wrap')
    vref = ref.mean(1)[:, None]
    dist = np.linalg.norm(img - ref[:, None, :], axis=2)
    neutral = st <= 30
    white = (v >= vref + 38) & (st <= 60)
    red = (Rr - Gg >= 35) & (Rr - Bb >= 30) & (Rr >= 90)
    green = ((Gg - Rr >= 4) & (Gg - Bb >= 12) & (v >= 35)) | ((Gg - Rr >= 15) & (Bb - Rr >= 5))
    beige = (Rr - Bb >= 25) & (v >= 85) & ~neutral
    pitm = (dp < 3.5) & (np.abs(D)[None] > 3.0) & (dp < np.abs(D)[None] - 2.0)
    thr = np.maximum(32, 0.28 * np.linalg.norm(ref, axis=1))[:, None]
    # cor (verde/grama/bege) só conta como "fora" se também for longe da cor do asfalto local (fotos amarronzadas)
    off_ = white | red | ((green | beige) & (dist > thr)) | pitm
    asph = ((neutral & (v < vref + 38)) | (dist <= thr)) & ~off_
    lo = np.minimum(np.roll(v, 4, 1), np.roll(v, -4, 1))
    peak = (v - lo >= 22) & (v >= vref + 25)
    dark = (v < 70) & (Bb < np.minimum(Rr, Gg) - 4) & (dist > thr)   # copa/sombra esverdeada (não o asfalto escuro)
    E, SH, PIT = [], [], []
    for sg in (-1, 1):
        idx = I0 + sg * np.arange(int(3.0 / 0.25), int(17.0 / 0.25))
        na = ~asph[:, idx]
        pk = peak[:, idx] & (np.abs(D[idx]) >= 4.5)[None]
        r3 = np.zeros_like(na)
        r3[:, :-2] = na[:, :-2] & na[:, 1:-1] & na[:, 2:]
        stop = r3 | pk
        has = stop.any(1)
        k0 = stop.argmax(1)
        e = np.where(has, np.abs(D[idx][k0]), np.nan)
        # sombra: fração escura na faixa ±1,5 m em volta da borda medida (ou de 5–8 m sem borda)
        kk = np.where(has, k0, int(2.5 / 0.25))
        rows = np.clip(kk[:, None] + np.arange(-6, 7)[None], 0, len(idx) - 1)
        SH.append(dark[:, idx][np.arange(len(P))[:, None], rows].mean(1))
        PIT.append(pitm[:, idx][np.arange(len(P))[:, None], rows].mean(1) > 0.2)
        E.append(e)
    return E[0], E[1], SH[0], SH[1], PIT[0], PIT[1], img


def dois_tons(img, W, lados, largura_max=11.5):
    """asfalto em dois tons (faixa recapeada preta ao lado do asfalto velho cinza, comum no mosaico): onde a pista
    medida ficou estreita (< largura_max), se da borda medida para fora só há cinza neutro (sem grama, pintura,
    zebra) até uma linha branca a 1–7 m, a borda é essa linha. Devolve as bordas novas e a máscara do que mudou."""
    Rr, Gg, Bb = img[..., 0], img[..., 1], img[..., 2]
    v = img.mean(2)
    st = img.max(2) - img.min(2)
    cor = ((Gg - Rr >= 4) & (Gg - Bb >= 12)) | ((Gg - Rr >= 15) & (Bb - Rr >= 5)) | (Rr - Bb >= 25) | (Rr - Gg >= 35)
    cinza = (st <= 32) & ~cor & (v <= 185)
    lo = np.minimum(np.roll(v, 4, 1), np.roll(v, -4, 1))
    linha = (v - lo >= 18) & (v >= 80) & (st <= 60)
    out, mud = [], []
    estreita = (W[0] + W[1]) < largura_max
    for (sg, e) in zip((-1, 1), W):
        e2 = e.copy()
        m = np.zeros(len(e), bool)
        for j in np.where(estreita)[0]:
            k0 = I0 + sg * int(round(e[j] / 0.25))
            for k in range(1, 29):   # até 7 m
                i = k0 + sg * k
                if i < 0 or i >= len(D):
                    break
                if linha[j, i]:
                    if k * 0.25 >= 1.0:
                        e2[j] = abs(D[i])
                        m[j] = True
                    break
                if not cinza[j, i]:
                    break
        # só trechos contínuos (≥ 8 m) e sem degrau: mediana
        for a, b in runs(m):
            if b - a + 1 < 8:
                ii = np.arange(a, b + 1) % len(e)
                m[ii] = False
                e2[ii] = e[ii]
        e2 = np.where(m, median_filter(e2, size=9, mode='wrap'), e)
        out.append(np.maximum(e2, e))
        mud.append(m)
    return out, mud


def conf_fase2(s_old):
    """confiança da borda medida na Fase 2 (0/1/2 por metro do s antigo) levada para estas amostras."""
    j = np.round(s_old).astype(int) % psat['n']
    return [np.array([int(psat[l]['conf'][i]) for i in j]) for l in ('esq', 'dir')]


def limpa(e, sh, pitf, c2):
    """borda confiável: dentro da faixa plausível, perto da mediana móvel (±0,8 m em 25 m), sem sombra/estrutura.
    devolve (borda preenchida, confiança 0/1/2)."""
    ok = np.isfinite(e) & (e > 3.8) & (e < 10.5)
    med = median_filter(fill_circ(np.nan_to_num(e), ok), size=25, mode='wrap')
    good = ok & (np.abs(e - med) < 0.8) & (sh < 0.5) & (c2 > 0) & ~pitf
    conf = np.where(good, np.where((c2 == 2) & (sh < 0.25), 2, 1), 0)
    return fill_circ(np.where(good, e, 0), good), conf


# ---- deslocamento global do mosaico × linha atual (registro do satélite no referencial do mundo)
P = resample_loop(P0, DS)[0]
s_old_P, _ = lin0.proj(P)
c2L, c2R = conf_fase2(s_old_P)
_, Rp = frames(P)
wl_m = interp_c(WL0, s_old_P, 2, L0)
wr_m = interp_c(WR0, s_old_P, 2, L0)
OFF = np.zeros(2)
for it in range(3):
    eL, eR, shL, shR, pL, pR, _ = mede(P, OFF)
    fL, cfL = limpa(eL, shL, pL, c2L)
    fR, cfR = limpa(eR, shR, pR, c2R)
    both = (cfL > 0) & (cfR > 0)
    c = (fR - fL) / 2 - (wr_m - wl_m) / 2
    dv, res = lsq_transl(Rp[both], c[both], cuts=(99, 1.5, 1.0))
    say(f'  registro satélite it{it}: offset ({OFF[0]:+.2f}, {OFF[1]:+.2f}) → resíduo ({dv[0]:+.2f}, {dv[1]:+.2f}), '
        f'bordas válidas L {np.mean(cfL > 0) * 100:.0f}% R {np.mean(cfR > 0) * 100:.0f}%')
    OFF = OFF + dv
    if np.hypot(*dv) < 0.05:
        break
sat_menos_atual = OFF.copy()
# "antes" com o detector próprio (para comparar com a conferência independente da linha nova)
_dl = (fL - wl_m)[cfL == 2]
_dr = (fR - wr_m)[cfR == 2]
DIAG['antes_detector_proprio'] = {'mediana_abs': [round(float(np.median(np.abs(_dl))), 2), round(float(np.median(np.abs(_dr))), 2)],
                                  'p95_abs': [round(float(np.percentile(np.abs(_dl), 95)), 2), round(float(np.percentile(np.abs(_dr), 95)), 2)]}
say(f'antes (linha atual × detector próprio, conf alta): {DIAG["antes_detector_proprio"]}')
say(f'satélite × linha atual: satélite = atual + ({OFF[0]:+.2f}, {OFF[1]:+.2f}) m (Fase 2: +2,32, −1,96)')
DIAG['referencial']['sat_menos_atual'] = OFF.round(2).tolist()

# bordas medidas pela Fase 2 (build_perfil.py: mesmo mosaico, registrado com o offset dela) como pontos do mundo:
# é a medida principal (trata asfalto em dois tons, linha branca fraca e escape da mesma cor, conferida nas
# imagens da Fase 2). O detector acima (mede) fica como conferência independente.
OFF_F2 = np.array([psat['offset']['dx'], psat['offset']['dz']])
EDGE = {}
for lado, sg in (('esq', -1), ('dir', 1)):
    bo = np.array([np.nan if x is None else x for x in psat[lado]['borda']], float)
    cf = np.array([int(c) for c in psat[lado]['conf']])
    sa = np.arange(psat['n'], dtype=float)
    ok = np.isfinite(bo) & (cf >= 1)
    EDGE[lado] = (None, cf[ok], sa[ok], bo[ok])


def world_from_old(s_a, lat):
    """ponto do mundo a `lat` m (com sinal, > 0 à direita) da linha ANTIGA em s antigo."""
    p = np.stack([interp_c(P0[:, 0], s_a, 2, L0), interp_c(P0[:, 1], s_a, 2, L0)], 1)
    r = np.stack([interp_c(R0[:, 0], s_a, 2, L0), interp_c(R0[:, 1], s_a, 2, L0)], 1)
    r /= np.linalg.norm(r, axis=1)[:, None]
    return p + r * np.asarray(lat)[:, None]


for lado, sg in (('esq', -1), ('dir', 1)):
    _, cf, sa, bo = EDGE[lado]
    EDGE[lado] = (world_from_old(sa, sg * bo), cf, sa, bo)


def bordas_fase2(Pc):
    """bordas da Fase 2 projetadas na linha Pc → por amostra e lado: (borda, conf 0/1/2). Sem ponto medido a
    ≤ 3 m em s: conf 0 e borda interpolada da vizinhança."""
    lc = Linha(Pc)
    n = len(Pc)
    stp = lc.L / n
    Sx = np.arange(n) * stp
    out = []
    for lado, sg in (('esq', -1), ('dir', 1)):
        pts, cf, _, _ = EDGE[lado]
        s, d = lc.proj(pts)
        e = sg * d
        m = e > 2.0
        s, e, cf_ = s[m], e[m], cf[m]
        o = np.argsort(s)
        s, e, cf_ = s[o], e[o], cf_[o]
        ee = np.interp(Sx, s, e, period=lc.L)
        k = np.searchsorted(s, Sx) % len(s)
        km = (k - 1) % len(s)
        gap_r = (s[k] - Sx) % lc.L
        gap_l = (Sx - s[km]) % lc.L
        near = np.where(gap_r < gap_l, k, km)
        conf = np.where(np.minimum(gap_r, gap_l) <= 3.0, cf_[near], 0)
        out += [ee, conf]
    return out


fL, cfL, fR, cfR = bordas_fase2(P)
devL0 = (fL - wl_m)[cfL == 2]
devR0 = (fR - wr_m)[cfR == 2]
DIAG['antes'] = {'borda_menos_w_mediana_abs': [round(float(np.median(np.abs(devL0))), 2), round(float(np.median(np.abs(devR0))), 2)],
                 'p95_abs': [round(float(np.percentile(np.abs(devL0), 95)), 2), round(float(np.percentile(np.abs(devR0), 95)), 2)],
                 'largura_medida_mediana': round(float(np.median((fL + fR)[(cfL == 2) & (cfR == 2)])), 2),
                 'largura_modelo_mediana': round(float(np.median(wl_m + wr_m)), 2)}
say(f'antes (linha atual × bordas da Fase 2, conf alta): |borda − w| mediana {DIAG["antes"]["borda_menos_w_mediana_abs"]}, '
    f'p95 {DIAG["antes"]["p95_abs"]}; largura medida {DIAG["antes"]["largura_medida_mediana"]} × modelo '
    f'{DIAG["antes"]["largura_modelo_mediana"]} m')


# ================================================================ 3) linha central recentralizada
# A linha nova = linha atual + R·δ(s), com δ (deslocamento lateral) suave: os erros da linha atual são suaves
# (2–5 m ao longo de 50–150 m) e as bordas medidas têm ruído local (escape da mesma cor, dois tons, sombra) que,
# seguido metro a metro, cria "cotovelos" (raio de 15–30 m onde o carro passa a 200 km/h). δ é a mediana (31 m)
# do meio das bordas, suavizada com σ = SIGMA_DELTA.
SIGMA_DELTA = float(os.environ.get('SIGMA_DELTA', 15.0))
P1, _ = resample_loop(P0, DS)
_, R1 = frames(P1)
delta = np.zeros(len(P1))
for it in range(8):
    P = P1 + R1 * delta[:, None]
    fL, cfL, fR, cfR = bordas_fase2(P)
    both = (cfL > 0) & (cfR > 0)
    onlyL = (cfL > 0) & ~both
    onlyR = (cfR > 0) & ~both
    # meia-largura de referência (onde só um lado mede): mediana móvel de 81 m dos trechos com os dois lados
    hw = np.where(both, (fL + fR) / 2, np.nan)
    hw = median_filter(fill_circ(np.nan_to_num(hw), both), size=81, mode='wrap')
    c = np.full(len(P), np.nan)
    c[both] = (fR - fL)[both] / 2
    c[onlyL] = (hw - fL)[onlyL]
    c[onlyR] = (fR - hw)[onlyR]
    okc = np.isfinite(c)
    alvo = delta + fill_circ(np.nan_to_num(c), okc)        # buracos: vizinhança (interpolação), marcados
    alvo = circ_gauss(median_filter(alvo, size=31, mode='wrap'), SIGMA_DELTA)
    alvo = np.clip(alvo, -6.0, 6.0)                         # nunca mais de 6 m da linha atual
    mud = alvo - delta
    delta = alvo
    say(f'  centro it{it}: mudou {np.median(np.abs(mud)):.2f} m (mediana), {np.percentile(np.abs(mud), 95):.2f} (p95), '
        f'máx {np.abs(mud).max():.2f}; δ total p95 {np.percentile(np.abs(delta), 95):.2f}, máx {np.abs(delta).max():.2f}; '
        f'dois lados {both.mean() * 100:.0f}%, um lado {(onlyL | onlyR).mean() * 100:.0f}%, vizinhança {(~okc).mean() * 100:.0f}%')
    if np.percentile(np.abs(mud), 95) < 0.05:
        break
P = P1 + R1 * delta[:, None]
FONTE_CENTRO_ANTES = np.where(both, 2, np.where(onlyL | onlyR, 1, 0))
P_ANTES_SUAVE = P.copy()

# suavização final leve (o δ já é suave; σ SIGMA_FINAL tira o resto de serrilhado) e s = 0 no ponto do mundo do
# s = 0 de hoje
SIGMA_FINAL = 2.0
P = circ_gauss(P, SIGMA_FINAL)
linP = Linha(P)
s_start, d_start = linP.proj(P0[:1])
L = length(P)
n_out = K_OUT * int(round(L / K_OUT))
P, L = resample_loop(P, L / n_out, start=float(s_start[0]))
assert len(P) == n_out
lin = Linha(P)
T, R = frames(P)
step = L / len(P)
_la = Linha(P_ANTES_SUAVE)
_nf = len(FONTE_CENTRO_ANTES)
FONTE_CENTRO = FONTE_CENTRO_ANTES[np.round(_la.proj(P)[0] / _la.L * _nf).astype(int) % _nf]
say(f'linha nova: {L:.1f} m ({len(P)} amostras de {step:.4f} m); s = 0 a {abs(d_start[0]):.2f} m (lateral) do s = 0 de hoje')

# ================================================================ 4) larguras
s_old, d_old = lin0.proj(P)          # s antigo de cada amostra nova e onde a linha antiga está (d > 0: à direita)
fL, cfL, fR, cfR = bordas_fase2(P)
both = (cfL > 0) & (cfR > 0)
fonte_centro = FONTE_CENTRO
# conferência independente: detector próprio (mede) na linha nova, com o offset estimado aqui
c2L, c2R = conf_fase2(s_old)
eL2, eR2, shL, shR, pL, pR, IMG_U = mede(P, OFF_F2)
gL2, cgL2 = limpa(eL2, shL, pL, c2L)
gR2, cgR2 = limpa(eR2, shR, pR, c2R)


def largura(f, conf):
    """mediana robusta em janela (percentil 40 em ±7 m: escape da mesma cor e sombra só alargam), σ 2 m."""
    w = fill_circ(np.where(conf > 0, f, 0), conf > 0)
    w = percentile_filter(w, 40, size=15, mode='wrap')
    return np.clip(circ_gauss(w, 2.0), 3.8, 10.5)


WLn = largura(fL, cfL)
WRn = largura(fR, cfR)
(WLn2, WRn2), DOIS_TONS = dois_tons(IMG_U, (WLn, WRn), None)
WLn = np.clip(circ_gauss(WLn2, 1.5), 3.8, 10.5)
WRn = np.clip(circ_gauss(WRn2, 1.5), 3.8, 10.5)
say(f'asfalto em dois tons (borda levada até a linha branca): esq {DOIS_TONS[0].sum()} m, dir {DOIS_TONS[1].sum()} m')
# rede de segurança contra borda presa num degrau de tom (asfalto recapeado ao lado do velho): a largura crua do
# TUMFTM (outra medida de satélite, independente; mediana 11,7 m, em geral MAIS estreita que a nossa) é um piso.
# Onde a nossa ficou > 1,5 m abaixo dela, sobe até ela pelo lado mais estreito, e marca.
_web = json.load(open(os.path.join(ROOT, '..', 'gt3-time-attack', 'data', 'tracks', 'interlagos.json')))
_tw = np.array(_web['widthLeft']) + np.array(_web['widthRight'])
TUM = interp_c(_tw, s_old / L0 * len(_tw), 1.0, len(_tw))
falta = TUM - (WLn + WRn)
PISO_TUM = np.zeros((len(P), 2), bool)
m = falta > 1.5
for a, b in runs(m):
    if b - a + 1 < 5:
        m[np.arange(a, b + 1) % len(P)] = False
lado_estreito = WLn < WRn
for col, W in ((0, WLn), (1, WRn)):
    mm = m & (lado_estreito if col == 0 else ~lado_estreito)
    W[mm] += falta[mm]
    PISO_TUM[:, col] = mm
WLn = np.clip(circ_gauss(WLn, 2.0), 3.8, 10.5)
WRn = np.clip(circ_gauss(WRn, 2.0), 3.8, 10.5)
say(f'piso de largura do TUMFTM (nossa medida > 1,5 m mais estreita): esq {PISO_TUM[:, 0].sum()} m, dir {PISO_TUM[:, 1].sum()} m')

# ================================================================ GPS: ajuste das voltas na linha nova
# zebras primeiro (precisa do mapa s antigo → s novo)


def s_novo_de_antigo(s_a):
    """s antigo (track.json atual) → s novo, pela projeção da linha antiga na nova (monotônico)."""
    return np.interp(np.asarray(s_a) % L0, SMAP_A, SMAP_N)


# mapa: cada amostra antiga (2 m) projetada na linha nova
sm_n, sm_d = lin.proj(P0)
sm_n = np.unwrap(sm_n * 2 * np.pi / L) * L / (2 * np.pi)
sm_n = sm_n - sm_n[0]
if sm_n[-1] < 0:
    raise SystemExit('sentido invertido no mapa de s')
sm_n = np.maximum.accumulate(sm_n)
SMAP_A = np.append(s0_old, L0)
SMAP_N = np.append(sm_n, L)
mono_viol = int(np.sum(np.diff(lin.proj(P0)[0]) < -L / 2) - 1)

# ---- zebras (tabela decidida na Fase 2, não redetectar)
KL = np.zeros(len(P))
KR = np.zeros(len(P))
KCLS = {}
for z in PZ.ZEBRAS:
    a, b = s_novo_de_antigo(z['s0']), s_novo_de_antigo(z['s1'])
    i0, i1 = int(math.ceil(a / step)), int(math.floor(b / step))
    idx = np.arange(i0, i1 + 1) % len(P)
    col = 0 if z['lado'] == 'esq' else 1
    kold = interp_c(KL0 if col == 0 else KR0, s_old[idx], 2, L0)
    if z['classe'] == 'normal':
        w = np.full(len(idx), KERB_N)
    elif z['classe'] == 'saida':
        w = np.full(len(idx), KERB_S)
    else:
        # 'fisica': a classe que a física de hoje tem ali (1,2 normal / 2,2 saída, com a rampa do Track);
        # nas pontas sem zebra na física, a classe dominante do trecho
        ks = np.sort(kold[kold > 0])
        dom = KERB_S if len(ks) and ks[len(ks) // 2] >= 1.7 else KERB_N
        w = np.where(kold > 0, np.clip(kold, KERB_N, KERB_S), dom)
    (KL if col == 0 else KR)[idx] = np.maximum((KL if col == 0 else KR)[idx], w)
    KCLS[(z['lado'], z['s0'])] = (round(float(a), 1), round(float(b), 1), round(float(np.median(w)), 2))


def lim_fn_factory(Wl, Wr, Kl, Kr, extra):
    def f(s, d):
        i = s / step
        wl = interp_c(Wl + Kl, s, step, L)
        wr = interp_c(Wr + Kr, s, step, L)
        return np.where(d > 0, wr, wl) + extra
    return f


f_new, _ = fit_gps(lin, lim_fn_factory(WLn, WRn, np.zeros(len(P)), np.zeros(len(P)), 0.0),
                   [AJ0['dx'], AJ0['dz'], AJ0['th'], AJ0['s']])
f_new_tr, _ = fit_gps(lin, lim_fn_factory(WLn, WRn, np.zeros(len(P)), np.zeros(len(P)), 0.0), [0, 0, 0, 1], livre=(0, 1))
say(f'GPS → linha nova: completo dx {f_new[0]:+.2f} dz {f_new[1]:+.2f} θ {math.degrees(f_new[2]):+.3f}° esc '
    f'{f_new[3]:.4f}; só translação: GPS = nova + ({-f_new_tr[0]:+.2f}, {-f_new_tr[1]:+.2f})')
DIAG['referencial']['gps_ajuste_linha_nova'] = {'dx': round(f_new[0], 3), 'dz': round(f_new[1], 3),
                                                'th_graus': round(math.degrees(f_new[2]), 4), 'escala': round(f_new[3], 5)}
DIAG['referencial']['gps_cru_menos_nova_translacao'] = [round(-f_new_tr[0], 2), round(-f_new_tr[1], 2)]

LAPS = []
for v in VOLTAS:
    xz = sim(f_new, v['x'], v['z'])
    s, d = lin.proj(xz)
    LAPS.append({'nome': v['nome'], 'xz': xz, 's': s, 'd': d, 'v': v['v'], 'lat_g': v['lat_g'], 'pct': v['pct']})

# ---- onde a borda não tem confiança alta: o GPS das voltas manda abrir a borda se o carro passa além (meio carro)
env = np.zeros((len(P), 2))
for lp in LAPS:
    j = np.round(lp['s'] / step).astype(int) % len(P)
    np.maximum.at(env[:, 0], j, -lp['d'])
    np.maximum.at(env[:, 1], j, lp['d'])
env = np.maximum(median_filter(env, size=(5, 1), mode='wrap'), 0)
GPS_FIX = np.zeros((len(P), 2), bool)
for col, W, K, cf in ((0, WLn, KL, cfL), (1, WRn, KR, cfR)):
    lowc = median_filter((cf <= 1).astype(np.uint8), size=9, mode='wrap') > 0   # confiança baixa ou média
    need = env[:, col] - 1.0 - K       # carro (meia largura ~1 m) por cima da zebra no máximo
    fix = lowc & (need > W)
    W[fix] = need[fix]
    GPS_FIX[:, col] = fix
WLn = np.clip(circ_gauss(WLn, 1.5), 3.8, 10.5)
WRn = np.clip(circ_gauss(WRn, 1.5), 3.8, 10.5)

# ---- etapa E: trechos onde a borda medida é artefato → reta entre as pontas (s antigo, como as zebras)
#   dir 1472–1498 e 3644–3664: "calombos" de ~3 m para dentro do escape turquesa (borda presa no escape da mesma
#     cor / piso do TUMFTM); nas faixas desenroladas (faixa_1200/3600) a linha branca segue reta.
#   esq 834–932: saída dos boxes; a borda pula entre a linha branca e a faixa de aceleração (5,0 ↔ 8,2 m).
#   esq 3641–3666 (Subida dos Boxes): fim do piso do TUMFTM (9,4 m) + borda de confiança média que entra 1,5 m
#     (7,4 m) por 15 m; as 6 voltas passam a 8,6–9,2 m (RefBot com a volta da Ferrari freava ali: 170 × 191 km/h).
ALISAR = [('dir', 1472, 1498), ('dir', 3644, 3664), ('esq', 834, 932), ('esq', 3641, 3666)]
ALISADO = np.zeros((len(P), 2), bool)
for lado, a_old, b_old in ALISAR:
    W = WLn if lado == 'esq' else WRn
    ia = int(math.floor(s_novo_de_antigo(a_old) / step))
    ib = int(math.ceil(s_novo_de_antigo(b_old) / step))
    idx = np.arange(ia, ib + 1) % len(P)
    W[idx] = np.interp(np.arange(ia, ib + 1), [ia, ib], [W[ia % len(P)], W[ib % len(P)]])
    ALISADO[idx, 0 if lado == 'esq' else 1] = True
say(f'bordas alisadas (artefatos): esq {ALISADO[:, 0].sum()} m, dir {ALISADO[:, 1].sum()} m')
# ---- etapa E: borda que pegou o asfalto de outra via. Bico de Pato (s antigo 2676–2742, esq.): a borda medida
# (6,7–7,7 m) passa por cima de um muro baixo (linha cinza clara no satélite, cima_bico_mergulho.jpg) e vai até o
# asfalto do traçado antigo do outro lado; o LiDAR 2017 mostra o muro (classe 19) e um degrau de 0,9 m a ~4 m do
# centro. As 6 voltas passam até 2,9 m à esquerda (lado do carro a ~3,9 m). Borda = wmax (4,2 m), nunca a menos de
# meio carro além do GPS das voltas; rampa de 10 m nas pontas.
LIMITAR = [('esq', 2676, 2742, 4.2)]
for lado, a_old, b_old, wmax in LIMITAR:
    col = 0 if lado == 'esq' else 1
    W = WLn if col == 0 else WRn
    ia = int(math.floor(s_novo_de_antigo(a_old) / step))
    ib = int(math.ceil(s_novo_de_antigo(b_old) / step))
    k = np.arange(ia - 10, ib + 11)
    idx = k % len(P)
    peso = np.clip(np.minimum(k - (ia - 10), (ib + 10) - k) / 10.0, 0.0, 1.0)
    alvo = np.maximum(wmax, env[idx, col] + 1.0)
    W[idx] = np.minimum(W[idx], W[idx] * (1 - peso) + alvo * peso)
    ALISADO[idx, col] |= peso > 0
say(f'borda limitada (outra via além do muro): {LIMITAR}')
say(f'larguras: total mediana {np.median(WLn + WRn):.2f} m (p5 {np.percentile(WLn + WRn, 5):.2f}, p95 '
    f'{np.percentile(WLn + WRn, 95):.2f}, min {np.min(WLn + WRn):.2f}, max {np.max(WLn + WRn):.2f}); confiança alta '
    f'L {np.mean(cfL == 2) * 100:.0f}% R {np.mean(cfR == 2) * 100:.0f}%, baixa L {np.mean(cfL == 0) * 100:.0f}% R '
    f'{np.mean(cfR == 0) * 100:.0f}%; aberta pelo GPS L {GPS_FIX[:, 0].sum()} R {GPS_FIX[:, 1].sum()} m')


# ================================================================ 5) muros
def to_new_side(pts, sg, W):
    """projeta pontos do mundo na linha nova → (índice, distância do centro naquele lado); descarta o outro lado."""
    s, d = lin.proj(pts)
    j = np.round(s / step).astype(int) % len(P)
    ok = (np.sign(d) == sg) & (np.abs(d) > W[j] + 0.5)
    return j[ok], np.abs(d[ok])


def bin_min(j, val, n):
    out = np.full(n, np.nan)
    for a, b in zip(j, val):
        if np.isnan(out[a]) or b < out[a]:
            out[a] = b
    return out


# (a) perfil visual de hoje (muro desenhado): `wall` por amostra antiga, medido do centro antigo
# o perfil é o da pista ANTIGA (s antigo, muros desenhados à mão): desde a etapa F o data/track/visual_profile.json
# está no s novo e usa dist "fisica" (este muro), então a cópia antiga fica congelada em build/interlagos/
# (recriar com `git show 76624e4:data/track/visual_profile.json > build/interlagos/visual_profile_antigo.json`)
PERF = json.load(open(os.path.join(RAW, 'visual_profile_antigo.json'), encoding='utf-8'))
assert PERF.get('n') == N0, 'visual_profile_antigo.json não é o da pista antiga'
perf_wall = {}
for lado, sg, col in (('esq', -1, 0), ('dir', 1, 1)):
    A = PZ.avalia(PERF, t0, lado)
    sa = np.arange(N0) * 2.0
    # amostra a cada 0,5 m (interpolada) para cobrir a linha nova sem buracos
    sf = np.arange(0, L0, 0.5)
    wv = interp_c(np.array([a['wall'] for a in A]), sf, 2, L0)
    j, dist = to_new_side(world_from_old(sf, sg * wv), sg, WLn if col == 0 else WRn)
    pw = bin_min(j, dist, len(P))
    perf_wall[lado] = fill_circ(np.nan_to_num(pw), np.isfinite(pw))
    perf_wall[lado + '_tipo'] = [A[int(round(sv / 2.0)) % N0]['tipo'] for sv in s_old]

# (b) OSM barrier=wall/fence a até 30 m, só se contínuo (≥ 10 m) e coerente
def densify(lines, stepm=0.5):
    pts = []
    for line in lines:
        for a, b in zip(line[:-1], line[1:]):
            a, b = np.array(a), np.array(b)
            k = max(1, int(np.ceil(np.linalg.norm(b - a) / stepm)))
            for u in np.linspace(0, 1, k + 1):
                pts.append(a + (b - a) * u)
    return np.array(pts) if pts else np.zeros((0, 2))


wpts = densify(osm['walls'] + osm['fences'])
osm_wall = {}
for lado, sg, col in (('esq', -1, 0), ('dir', 1, 1)):
    W = WLn if col == 0 else WRn
    j, dist = to_new_side(wpts, sg, W)
    keep = dist < W[j] + 30
    ow = bin_min(j[keep], dist[keep], len(P))
    m = np.isfinite(ow)
    for a, b in runs(m):
        if b - a + 1 < 10:
            m[np.arange(a, b + 1) % len(P)] = False
    osm_wall[lado] = np.where(m, ow, np.nan)

# (c) candidatos do satélite (Fase 2: linha estreita contínua; distância da borda medida) só com conf. alta
sat_wall = {}
for lado, sg, col in (('esq', -1, 0), ('dir', 1, 1)):
    mu = np.array([np.nan if x is None else x for x in psat[lado]['muro']], float)
    bo = np.array([np.nan if x is None else x for x in psat[lado]['borda']], float)
    cf = np.array([int(c) for c in psat[lado]['conf']])
    sa = np.arange(psat['n'], dtype=float)
    ok = np.isfinite(mu) & np.isfinite(bo) & (cf == 2)
    # a medida da Fase 2 é no mosaico registrado pelo offset dela; o mundo é o mesmo (linha atual)
    pts = world_from_old(sa[ok], sg * (bo[ok] + mu[ok]))
    j, dist = to_new_side(pts, sg, WLn if col == 0 else WRn)
    sw = bin_min(j, dist, len(P))
    sat_wall[lado] = sw

WALL_MIN_GAP = 1.5    # m da borda (o applyWalls padrão força 2,5; aqui vai como `wallMinGap` no interlagos.json)
PIT_EXIT_GAP = 5.5    # m da borda + zebra até o guard-rail na saída dos boxes
# saída dos boxes: s antigo 800–1000 (do fim da mureta até a última faixa de convergência, vídeo s0860–s1000),
# rampa de 20 m nas pontas. Fase 5: a ponta do separador (fim da ilha e começo do hachurado diagonal) fica em s novo
# ~835–837 no satélite (build/interlagos/fase5/esq_par.jpg; OSM: ponta do muro em s antigo 825) e no LMU (chase
# s 820/840): a rampa de abertura passou de s antigo 800–820 para 824–830 (s novo 831–837; a ponta é curta).
_sa = np.asarray(s_old) % L0
PIT_EXIT = np.clip(np.minimum((_sa - 824.0) / 6.0, (1000.0 - _sa) / 20.0), 0.0, 1.0)
WALL = np.zeros((len(P), 2))
EMPURRADO = {}
WSRC = np.zeros((len(P), 2), int)    # 3 osm · 2 satélite (confirmado pelo perfil) · 1 perfil, sat. diverge · 0 perfil, não medido
for lado, col in (('esq', 0), ('dir', 1)):
    pw = perf_wall[lado]
    ow = osm_wall[lado]
    sw = sat_wall[lado]
    w = pw.copy()
    src = np.zeros(len(P), int)
    sat_ok = np.isfinite(sw) & (np.abs(sw - pw) <= 1.5)
    w[sat_ok] = sw[sat_ok]
    src[sat_ok] = 2
    src[np.isfinite(sw) & ~sat_ok] = 1
    osm_ok = np.isfinite(ow) & (ow <= pw + 3.0)   # muro do OSM atrás do muro desenhado é outro muro (externo)
    w[osm_ok] = ow[osm_ok]
    src[osm_ok] = 3
    # segmentos de fonte medida curtos (< 8 m) voltam ao perfil (evita serrilhado)
    for code in (2, 3):
        m = src == code
        for a, b in runs(m):
            if b - a + 1 < 8:
                ii = np.arange(a, b + 1) % len(P)
                w[ii] = pw[ii]
                src[ii] = 0
    w = median_filter(w, size=5, mode='wrap')
    # nunca dentro da zebra nova (o muro do perfil foi medido da borda antiga; onde a borda abriu, empurra) e
    # (etapa E) nunca a menos de WALL_MIN_GAP da borda nem de meio carro + 0,5 m além do GPS das 6 voltas: a física
    # do muro é só um limite lateral (track.gd wall_penetration), então muro colado não quebra nada, mas a linha
    # real (RefBot) não pode encostar nele
    Wn, Kn = (WLn, KL) if col == 0 else (WRn, KR)
    piso = np.maximum.reduce([Wn + Kn + 0.5, Wn + WALL_MIN_GAP, env[:, col] + 1.5])
    # saída dos boxes (esquerda): a faixa de aceleração (~4–5 m de asfalto, vídeo s0860/s0940) fica antes do
    # guard-rail; o muro do OSM/perfil ali (2,5 m, e 1,0 m na ponta do muro em s antigo 825) cortaria a faixa
    if col == 0:
        piso = np.where(PIT_EXIT > 0, np.maximum(piso, Wn + Kn + PIT_EXIT_GAP * PIT_EXIT), piso)
    EMPURRADO[lado] = int(np.sum(w < piso))
    WALL[:, col] = np.maximum(w, piso)
    WSRC[:, col] = src
say('muros (m do centro): ' + '; '.join(
    f'{l}: mediana {np.median(WALL[:, c]):.1f}, OSM {np.mean(WSRC[:, c] == 3) * 100:.0f}%, satélite '
    f'{np.mean(WSRC[:, c] == 2) * 100:.0f}%, perfil c/ satélite divergente {np.mean(WSRC[:, c] == 1) * 100:.0f}%, '
    f'perfil (não medido) {np.mean(WSRC[:, c] == 0) * 100:.0f}%' for l, c in (('esq', 0), ('dir', 1))))


# ================================================================ 6) altitude (ponto único do LiDAR)
def altitude_e_camber(P, s_old):
    """altitude por amostra (m, mínimo 0) e camber (rad, + = direita mais alta) ou None.
    Hoje: a altitude do track.json atual levada para a linha nova pela projeção (mesmo perfil), sem camber.
    Com --lidar: tools/tracks/interlagos/lidar.py → altura(x, z) do terreno nu, como em Imola (mediana contra
    pontes/galerias, σ 4 m; camber a ±3,5 m, σ 10 m). Conferir VertAccel × v²·curvatura vertical antes de usar."""
    if '--lidar' not in sys.argv:
        y = interp_c(Y0, s_old, 2, L0)
        return y - y.min(), None
    import lidar  # noqa: E402  (tools/tracks/interlagos/lidar.py, do agente do LiDAR)
    # piso real (classes 2 + 20, registro LiDAR × mundo aplicado em lidar.jogo_para_utm); perfil(): mediana de 65 m
    # contra pontes/passarelas, altitude σ 6 m; camber = reta robusta entre ±3,5 m (camber_bruto, ignora degrau/muro
    # num dos lados) + mediana curta + σ 10 m. Conferido contra o VertAccel das 6 voltas (LEIA-ME, seção LiDAR).
    # bank + = lado direito mais alto (mesma convenção de tools/tracks/bank.ts e scripts/track/track.gd).
    pf = lidar.perfil(P, L / len(P), [], sig_y=6.0, sig_b=10.0)
    y = pf['y']
    return y - y.min(), pf['bank']


Yn, BANK = altitude_e_camber(P, s_old)

# ================================================================ 7) saída
sections = []
for c in t0['sections']:
    a, b = float(s_novo_de_antigo(c['s0'])), float(s_novo_de_antigo(c['s1']))
    sections.append({'name': c['name'], 's0': round(a, 1), 's1': round(b, 1)})


def spans(code_arr, names):
    out = []
    for code, nm in names.items():
        for a, b in runs(code_arr == code):
            e = (b + 1) * step
            out.append([round(a * step, 1), round(e - L if e > L else e, 1), nm])
    return sorted(out)


# ---- etapa F (conferência do GLB, build/interlagos/perfil_2b/conferencia_glb.json): trechos em que o muro da
# física não batia com a barreira real/desenhada. Janelas em s antigo (como as zebras), rampa nas pontas.
#   1. separador da saída dos boxes (esq, s antigo 564–734; trackDetails.ts buildPitExit: guard-rail a borda + 4,4 m)
#   2. (até a Fase 6) barreira Goodyear do Lago (esq, 1385–1580: borda + 1,35 m, colada na zebra). Substituída pelos
#      muros da Fase 6 abaixo (MURO_F6): a Goodyear real começa em s novo ~1490, e antes dela há um guard-rail longe.
#   3. S do Senna (esq, 333–428): o muro é o guard-rail ao longo da saída dos boxes, 13–27 m do centro, com grama
#      larga antes (LMU folha_01 s=0382). A cerca do OSM (barrier=fence) bate com a faixa clara no satélite a ±1 m;
#      não entrava porque passava 3 m do muro desenhado antes ("muro externo").
#   4. Bico de Pato (dir, 2713–2796, lado de dentro do grampo, raio 21–25 m): sem barreira a 30 m no satélite (só
#      grama); 23 m de muro dobrava sobre o centro da curva. Limite de 14 m (raio do muro ≥ ~7,5 m).
# Piso de segurança em todos: meio carro (1,0 m) além do GPS das 6 voltas.
def janela_antigo(a, b, rampa):
    sa = np.asarray(s_old) % L0
    return np.clip(np.minimum((sa - (a - rampa)) / rampa, ((b + rampa) - sa) / rampa), 0.0, 1.0)


# Fase 4 (setor 4): o separador da saída dos boxes estava a borda + 4,4 m (o guard-rail desenhado no buildPitExit,
# não medido). No satélite Esri z19 desenrolado (build/interlagos/fase4/sat_510_800_cru.png, registro +2,2/−2,1 m) a
# grama entre a linha branca e a pista dos boxes vai até borda + 8,9 m (s novo 556–600), 8,0–8,3 (600–640), 7,2–6,4
# (640–700), 5,9–7,7 (700–742; ali há também uma linha clara, o trilho, a borda + 6,5–8,2); o LMU (s 580–700) mostra
# grama larga antes do guard-rail. Muro ≈ fim da grama (±0,3 m), em s antigo (s novo 560/590/610/630/650/670/690/710/735/742 → antigo pelo s_antigo_novo.json).
# Fase 4: saída da Curva do Sol (dir, s novo ~723–779): o muro da física ficava a borda + 5–8 m (perfil antigo, não
# medido) e o LMU (s 750/780) mostra zebra + escape vermelho largo + faixa verde antes do muro MOTUL. No satélite
# desenrolado a pintura vai até borda + ~10 m, segue uma faixa escura de ~3 m e há uma linha clara (topo do muro) a
# borda + 15,5–17 m em s novo 730–770. Muro a borda + 15 m nessa janela (s antigo 722–766, rampa de 6 m).
# Fase 5 (setor 5): a janela segue até s antigo 906 (s novo 913). Antes o muro voltava a borda + 5,6 m em s novo 780 e
# o vermelho estreitava na emenda com a Reta Oposta (ficha setor-4 D8). Satélite (build/interlagos/fase5/c1.jpg,
# c2.jpg) e Fase 2 (diferencas.md, setor 5: pintura 12–13,5 m em s antigo 798–906, escape 15,5 m em 867–911): a
# pintura vai até borda + ~13–15 m; LMU chase s 790–870: zebra + vermelho largo + faixa verde até o muro MOTUL.
SEPARADOR_F4 = (np.array([551.1, 580.8, 600.9, 621.2, 641.5, 661.9, 682.2, 702.5, 727.7, 734.7]),
                np.array([9.0, 9.0, 8.6, 8.3, 7.6, 7.1, 6.7, 6.5, 7.3, 7.3]))
_osm_esq = osm_wall['esq']
MURO_F = []
for lado, a, b, rampa, alvo_fn, desc in [
        ('esq', 564.2, 734.0, 6.0, lambda: WLn + np.interp(np.asarray(s_old) % L0, *SEPARADOR_F4),
         'separador da saída dos boxes: fim da grama no satélite (Fase 4)'),
        ('esq', 333.0, 428.0, 6.0, lambda: fill_circ(np.nan_to_num(_osm_esq), np.isfinite(_osm_esq)),
         'S do Senna: cerca do OSM (= guard-rail no satélite)'),
        ('dir', 2713.0, 2796.0, 10.0, lambda: np.minimum(WALL[:, 1], 14.0), 'Bico de Pato: no máx. 14 m'),
        ('dir', 722.0, 906.0, 6.0, lambda: WRn + 15.0,
         'saída da Curva do Sol e começo da Reta Oposta: muro MOTUL a borda + 15 m (Fase 4: s antigo 722–766; '
         'Fase 5: até 906)'),
]:
    col = 0 if lado == 'esq' else 1
    w = janela_antigo(a, b, rampa)
    m = w > 0
    antes = WALL[m, col].copy()
    alvo = np.maximum(alvo_fn(), env[:, col] + 1.0)
    WALL[m, col] = WALL[m, col] * (1 - w[m]) + alvo[m] * w[m]
    WSRC[m, col] = np.where(w[m] >= 1, 4, WSRC[m, col])
    dentro = w >= 1
    MURO_F.append({'lado': lado, 's_antigo': [a, b], 'desc': desc,
                   'antes_m': [round(float(antes.min()), 2), round(float(antes.max()), 2)],
                   'depois_m': [round(float(WALL[dentro, col].min()), 2), round(float(WALL[dentro, col].max()), 2)],
                   'gps_mais_1m_venceu': int(np.sum(dentro & (alvo_fn() < env[:, col] + 1.0)))})
    say(f'muro etapa F {lado} {a:.0f}–{b:.0f}: {desc}; antes {MURO_F[-1]["antes_m"]} → {MURO_F[-1]["depois_m"]} m '
        f'(GPS + 1 m venceu em {MURO_F[-1]["gps_mais_1m_venceu"]} amostras)')

# Fase 6 (setor 6, Descida do Lago + subida; janelas em s NOVO, gap = m da borda do asfalto; rampa nas pontas).
# Medido no satélite Esri z19 desenrolado (build/interlagos/fase6/sat_setor6.jpg, agua.py/azul.py: cor por faixa de
# d a cada 10 m) e conferido nos quadros do LMU (build/ref/interlagos/folhas/fase6_ini_*):
#   esq 1380–1446: guard-rail baixo a borda + ~9 m (linha clara no satélite a +8..9 m; LMU s 1410/1430: grama larga
#                  e guard-rail longe, sem barreira azul). Depois de ~1450 o guard-rail se afasta (vai para o lago).
#   esq 1490–1640: barreira azul dupla GOODYEAR (LMU chase s 1490–1640: começa ao lado do carro em s 1490, zebra +
#                  ~1 m de verde antes dela; onboard s 1580); satélite: claro até borda + 2,5–3,5 m e copa escura
#                  depois (s 1530–1610). Face a borda + 2,6 m. Antes: borda + 1,35 m de s 1394 a 1582.
#   esq 1640–1665: volta ao muro de antes (barreira simples a borda + 3,4–4,4 m, LMU s 1670).
#   dir 1446–1690: escape verde/verde-água largo até a barreira GOODYEAR de fora, na beira do lago (satélite: pintura
#                  até borda + 19–33 m e água/sombra escura a +23–31 m; LMU s 1460–1640 com escape até o fundo).
#                  Antes: borda + 5–13 m (perfil antigo, não medido).
MURO_F6 = [
    ('esq', 1382.0, 1666.0, 12.0, ([1380, 1446, 1478, 1490, 1640, 1652], [9.0, 9.0, 9.0, 2.6, 2.6, 3.4]),
     'Fase 6: guard-rail do Lago a borda + 9 m e Goodyear dupla a borda + 2,6 m'),
    ('dir', 1432.0, 1692.0, 14.0, ([1446, 1460, 1470, 1490, 1500, 1520, 1540, 1560, 1580, 1600, 1640, 1652, 1680],
                                   [15.0, 22.0, 27.0, 27.0, 26.0, 23.0, 21.0, 21.0, 23.0, 25.0, 25.0, 20.0, 20.0]),
     'Fase 6: barreira de fora da Descida do Lago (beira do lago)'),
]
S_NOVO = np.arange(len(P)) * step
for lado, a, b, rampa, (xs, gs), desc in MURO_F6:
    col = 0 if lado == 'esq' else 1
    w = np.clip(np.minimum((S_NOVO - (a - rampa)) / rampa, ((b + rampa) - S_NOVO) / rampa), 0.0, 1.0)
    m = w > 0
    antes = WALL[m, col].copy()
    Wn = WLn if col == 0 else WRn
    alvo_sem = Wn + np.interp(S_NOVO, xs, gs)
    alvo = np.maximum.reduce([alvo_sem, Wn + (KL if col == 0 else KR) + 0.5, env[:, col] + 1.0])
    WALL[m, col] = WALL[m, col] * (1 - w[m]) + alvo[m] * w[m]
    WSRC[m, col] = np.where(w[m] >= 1, 4, WSRC[m, col])
    dentro = w >= 1
    MURO_F.append({'lado': lado, 's_novo': [a, b], 'desc': desc,
                   'antes_m': [round(float(antes.min()), 2), round(float(antes.max()), 2)],
                   'depois_m': [round(float(WALL[dentro, col].min()), 2), round(float(WALL[dentro, col].max()), 2)],
                   'gps_mais_1m_venceu': int(np.sum(dentro & (alvo_sem < env[:, col] + 1.0)))})
    say(f'muro Fase 6 {lado} {a:.0f}–{b:.0f} (s novo): {desc}; antes {MURO_F[-1]["antes_m"]} → {MURO_F[-1]["depois_m"]} m '
        f'(GPS + 1 m venceu em {MURO_F[-1]["gps_mais_1m_venceu"]} amostras)')
# Fase 3 (setor 3, reta dos boxes; janelas em s NOVO, gap = m da borda do asfalto; ficha
# build/ref/interlagos/fichas/setor-3.md). Satélite Esri z19 desenrolado (build/interlagos/fase3/sat_esq_d2.jpg,
# sat_reta.jpg; perfil de brilho por faixa de d) conferido no LMU (folhas build/ref/interlagos/folhas/fase3_ini_*):
#   esq 3940–4098: entrada dos boxes. A pista dos boxes sai colada na pista (LMU s 3940/3970: linha tracejada e asfalto
#                  até o guard-rail) e se afasta; a ilha verde com divisas (>>>) fica entre as duas (satélite s 3985–4020)
#                  e cresce até o bico do muro dos boxes em s ~4104 (satélite: ponta arredondada em 4103–4108; LMU s
#                  4030–4090: ilha verde larga com letras ROLEX, sem barreira, e o bico com a barreira <<O>> à frente).
#                  O muro da física ficava na ilha (borda + 1,5–6 m), com um guard-rail desenhado em cima dela; passa
#                  para o muro de fora da pista dos boxes (linha clara do satélite: borda + 7,5 → 28 m).
#   esq 4106–4296: muro dos boxes. Face a borda + 4,0 m (satélite: pintura verde 4,0 m na Fase 2, topo claro do muro a
#                  borda + 4,5–5 m; LMU s 4150–4300: faixa verde larga até o muro). Antes borda + 1,5 m.
MURO_F3 = [
    ('esq', 3940.0, 4296.0, 6.0, ([3940, 3960, 3980, 4000, 4020, 4040, 4060, 4098, 4106, 4296],
                                  [7.5, 9.4, 12.4, 15.6, 21.0, 26.0, 28.0, 28.0, 4.0, 4.0]),
     'Fase 3: entrada dos boxes (muro de fora da pista dos boxes) e muro dos boxes a borda + 4 m'),
]
for lado, a, b, rampa, (xs, gs), desc in MURO_F3:
    col = 0 if lado == 'esq' else 1
    w = np.clip(np.minimum((S_NOVO - (a - rampa)) / rampa, ((b + rampa) - S_NOVO) / rampa), 0.0, 1.0)
    m = w > 0
    antes = WALL[m, col].copy()
    Wn = WLn if col == 0 else WRn
    alvo_sem = Wn + np.interp(S_NOVO, xs, gs)
    alvo = np.maximum.reduce([alvo_sem, Wn + (KL if col == 0 else KR) + 0.5, env[:, col] + 1.0])
    WALL[m, col] = WALL[m, col] * (1 - w[m]) + alvo[m] * w[m]
    WSRC[m, col] = np.where(w[m] >= 1, 4, WSRC[m, col])
    dentro = w >= 1
    MURO_F.append({'lado': lado, 's_novo': [a, b], 'desc': desc,
                   'antes_m': [round(float(antes.min()), 2), round(float(antes.max()), 2)],
                   'depois_m': [round(float(WALL[dentro, col].min()), 2), round(float(WALL[dentro, col].max()), 2)],
                   'gps_mais_1m_venceu': int(np.sum(dentro & (alvo_sem < env[:, col] + 1.0)))})
    say(f'muro Fase 3 {lado} {a:.0f}–{b:.0f} (s novo): {desc}; antes {MURO_F[-1]["antes_m"]} → {MURO_F[-1]["depois_m"]} m '
        f'(GPS + 1 m venceu em {MURO_F[-1]["gps_mais_1m_venceu"]} amostras)')
WALL_MIN_GAP_JSON = 1.5   # (1,3 até a Fase 6, só pela Goodyear do Lago colada na zebra)

ko = np.arange(0, len(P), K_OUT)
ARC_DIV = 20000
# faixa de aceleração da saída dos boxes = escape asfaltado até 0,5 m do guard-rail (bank.ts applyRunoffMin)
RUN_L = PIT_EXIT * np.maximum(0.0, WALL[:, 0] - WLn - KL - 0.5)
medicao = {
    'obs': 's em m da linha de 1 m (= s do Track, exceto a escala do Catmull-Rom); [s0, s1, fonte]',
    'centro': spans(fonte_centro, {0: 'vizinhança (sem borda confiável)', 1: 'uma borda + largura vizinha'}),
    'bordaEsq': spans(np.where(GPS_FIX[:, 0], 9, np.where(PISO_TUM[:, 0], 7, np.where(DOIS_TONS[0], 8, cfL))),
                      {0: 'vizinhança', 9: 'GPS das voltas', 8: 'dois tons: até a linha branca', 7: 'piso TUMFTM'}),
    'bordaDir': spans(np.where(GPS_FIX[:, 1], 9, np.where(PISO_TUM[:, 1], 7, np.where(DOIS_TONS[1], 8, cfR))),
                      {0: 'vizinhança', 9: 'GPS das voltas', 8: 'dois tons: até a linha branca', 7: 'piso TUMFTM'}),
    'muroEsq': spans(np.where(WSRC[:, 0] >= 2, WSRC[:, 0], 0), {4: 'etapa F (ver muroEtapaF)', 3: 'osm', 2: 'satélite', 0: 'não medido (perfil atual)'}),
    'muroDir': spans(np.where(WSRC[:, 1] >= 2, WSRC[:, 1], 0), {4: 'etapa F (ver muroEtapaF)', 3: 'osm', 2: 'satélite', 0: 'não medido (perfil atual)'}),
    'muroEtapaF': MURO_F,
    'altitude': 'track.json atual por projeção' if BANK is None else 'LiDAR GeoSampa (lidar.py)',
    'bordaAlisada': [[round(float(s_novo_de_antigo(a)), 1), round(float(s_novo_de_antigo(b)), 1), l]
                     for l, a, b in ALISAR],
    'bordaLimitada': [[round(float(s_novo_de_antigo(a)), 1), round(float(s_novo_de_antigo(b)), 1), l, w]
                      for l, a, b, w in LIMITAR],
    'saidaBoxes': [round(float(s_novo_de_antigo(800.0)), 1), round(float(s_novo_de_antigo(1000.0)), 1),
                   'esq: escape asfaltado até o guard-rail, muro ≥ borda + zebra + 5,5 m'],
}
out = {
    # NÃO usar 'Interlagos': a classe Track do web reescala as larguras (realWidth) e põe muros da reta por nome
    'name': 'Interlagos (Fase 2B)',
    'source': 'linha atual (TUMFTM/OSM, referencial do mundo) recentralizada pelas bordas do asfalto no Esri World '
              'Imagery z19; larguras do satélite; zebras do perfil (satélite + vídeo LMU); muros OSM/satélite/perfil; '
              'altitude ' + ('LiDAR GeoSampa' if BANK is not None else 'do track.json atual (sem LiDAR)'),
    'origin': {'lat': LAT0, 'lon': LON0},
    'points': [[round(float(P[i, 0]), 3), round(float(Yn[i]), 3), round(float(P[i, 1]), 3)] for i in ko],
    'widthLeft': [round(float(WLn[i]), 2) for i in ko],
    'widthRight': [round(float(WRn[i]), 2) for i in ko],
    'kerbLeft': [round(float(KL[i]), 2) for i in ko],
    'kerbRight': [round(float(KR[i]), 2) for i in ko],
    'wallLeft': [round(float(WALL[i, 0]), 2) for i in ko],
    'wallRight': [round(float(WALL[i, 1]), 2) for i in ko],
    # etapa E (tools/tracks/fonte.ts): muro a ≥ 1,5 m da borda (não 2,5), escape asfaltado da saída dos boxes,
    # comprimento e espaçamento das amostras medidos com 20.000 cordas (o Track usaria 200: 4.300 m, 2,00–2,07 m)
    'wallMinGap': WALL_MIN_GAP_JSON,
    'runLeft': [round(float(RUN_L[i]), 2) for i in ko],
    'runRight': [0.0 for i in ko],
    'arcLengthDivisions': ARC_DIV,
    'sections': sections,
    'medicao': medicao,
}
if BANK is not None:
    out['bank'] = [round(float(BANK[i]), 4) for i in ko]
json.dump(out, open(os.path.join(HERE, 'interlagos.json'), 'w', encoding='utf-8'), ensure_ascii=False)

smap = {
    'descricao': 's do data/track/track.json atual (amostra i, s = 2·i) → s da linha nova (interlagos.json, linha de '
                 '1 m), pela projeção do ponto antigo na linha nova; d = posição lateral do centro antigo em relação '
                 'ao novo (m, > 0 à direita de quem corre). Monotônico. Para o s do Track novo (Catmull-Rom a cada '
                 '2 m) multiplicar por comprimentoTrack/comprimentoNovo (≈ 1).',
    'passoAntigo': 2, 'n': N0, 'comprimentoAntigo': L0, 'comprimentoNovo': round(L, 2),
    's_antigo': [round(float(x), 1) for x in s0_old],
    's_novo': [round(float(x), 2) for x in sm_n],
    'd': [round(float(x), 2) for x in sm_d],
}
# mapa provisório (unidades da linha de 1 m), só para conferência: o definitivo, em unidades do track.json
# exportado, é o tools/tracks/interlagos/s_antigo_novo.json gravado pelo mapa_s.py depois do pista.ts
json.dump(smap, open(os.path.join(IMG, 's_antigo_novo_linha.json'), 'w', encoding='utf-8'), ensure_ascii=False)
say(f'gravado interlagos.json ({len(ko)} pontos) e build/interlagos/tracado/s_antigo_novo_linha.json')

# ================================================================ 8) validação
V = {}
V['comprimento'] = {'linha_1m': round(L, 1), 'oficial': OFICIAL, 'erro_pct': round((L - OFICIAL) / OFICIAL * 100, 3),
                    'antigo': L0, 'osm': round(length(O1), 1)}
def catmull_three(pts, ts):
    """CatmullRomCurve3(pts, closed=true, 'centripetal').getPoint(t) do three.js (mesma conta, vetorizada)."""
    pts = np.asarray(pts, float)
    n = len(pts)
    p = n * np.asarray(ts)
    ip = np.floor(p).astype(int)
    w = p - ip
    ip = ip % n
    q0, q1, q2, q3 = pts[(ip - 1) % n], pts[ip], pts[(ip + 1) % n], pts[(ip + 2) % n]
    d0 = np.linalg.norm(q1 - q0, axis=1) ** 0.5
    d1 = np.linalg.norm(q2 - q1, axis=1) ** 0.5
    d2 = np.linalg.norm(q3 - q2, axis=1) ** 0.5
    d1 = np.where(d1 < 1e-4, 1.0, d1)
    d0 = np.where(d0 < 1e-4, d1, d0)
    d2 = np.where(d2 < 1e-4, d1, d2)
    d0, d1, d2 = d0[:, None], d1[:, None], d2[:, None]
    t1 = ((q1 - q0) / d0 - (q2 - q0) / (d0 + d1) + (q2 - q1) / d1) * d1
    t2 = ((q2 - q1) / d1 - (q3 - q1) / (d1 + d2) + (q3 - q2) / d2) * d1
    c0, c1, c2, c3 = q1, t1, -3 * q1 + 3 * q2 - 2 * t1 - t2, 2 * q1 - 2 * q2 + t1 + t2
    w = w[:, None]
    return c0 + c1 * w + c2 * w * w + c3 * w * w * w


def track_length(pts, div=200):
    """o que o Track do web calcula: curve.getLength() com arcLengthDivisions = 200 (cordas de ~21 m), N =
    round(L/2), length = 2N. Também o comprimento "verdadeiro" da curva (20.000 divisões)."""
    a = catmull_three(pts, np.arange(div + 1) / div)
    lt = float(np.linalg.norm(np.diff(a, axis=0), axis=1).sum())
    b = catmull_three(pts, np.arange(20001) / 20000)
    return 2 * round(lt / 2), float(np.linalg.norm(np.diff(b, axis=0), axis=1).sum())


pts3 = np.array(out['points'])
web_pts = np.array(json.load(open(os.path.join(ROOT, '..', 'gt3-time-attack', 'data', 'tracks', 'interlagos.json')))['points'])
V['comprimento']['track_web_novo'], V['comprimento']['curva_3d_novo'] = track_length(pts3)
V['comprimento']['track_web_atual'], V['comprimento']['curva_3d_atual'] = track_length(web_pts)
V['comprimento']['track_godot_novo'] = 2 * round(V['comprimento']['curva_3d_novo'] / 2)   # com arcLengthDivisions
V['comprimento']['curva_3d_novo'] = round(V['comprimento']['curva_3d_novo'], 1)
V['comprimento']['curva_3d_atual'] = round(V['comprimento']['curva_3d_atual'], 1)
say(f'comprimento: {L:.1f} m na linha de 1 m (plano), {V["comprimento"]["curva_3d_novo"]} m na curva 3D; o Track do web '
    f'(getLength com 200 cordas) daria {V["comprimento"]["track_web_novo"]} m (hoje: {V["comprimento"]["track_web_atual"]} '
    f'para uma curva de {V["comprimento"]["curva_3d_atual"]} m); com {ARC_DIV} cordas (pista.ts): '
    f'{V["comprimento"]["track_godot_novo"]} m; oficial {OFICIAL:.0f} ({V["comprimento"]["erro_pct"]:+.2f}% na linha plana)')

# ---- voltas entre as bordas
dentro = {}
fora_mask = np.zeros(len(P), bool)
for lp in LAPS:
    j = np.round(lp['s'] / step).astype(int) % len(P)
    lim = np.where(lp['d'] > 0, WRn[j] + KR[j], WLn[j] + KL[j])
    o = np.abs(lp['d']) - lim
    dentro[lp['nome']] = {'estrito_pct': round(float(np.mean(o <= 0) * 100), 2),
                          'meio_carro_pct': round(float(np.mean(o <= 1.0) * 100), 2),
                          'pior_m': round(float(o.max()), 2), 'pior_s': round(float(lp['s'][np.argmax(o)]), 0)}
    fora_mask[j[o > 1.0]] = True
V['voltas_dentro'] = dentro
tre = []
for a, b in runs(median_filter(fora_mask.astype(np.uint8), size=5, mode='wrap') > 0):
    tre.append([round(a * step), round((b % len(P)) * step)])
V['trechos_fora'] = tre
for k_, v_ in dentro.items():
    say(f'  {k_:28s}: dentro (borda+zebra) {v_["estrito_pct"]:6.2f}%, (+1 m, meio carro) {v_["meio_carro_pct"]:6.2f}%, '
        f'pior {v_["pior_m"]:+.2f} m em s {v_["pior_s"]:.0f}')
say(f'  trechos com alguma volta > 1 m além da borda+zebra: {tre}')

# ---- raio das curvas × telemetria
kap = curvatura(P)
kap_s = circ_gauss(kap, 2.0)
kap_old = circ_gauss(curvatura(resample_loop(P0, DS)[0]), 2.0)
L0r = length(resample_loop(P0, DS)[0])
nomes = osm.get('raceName', [])
lin_osm = Linha(O1)


def nome_em(s_new):
    # nome do trecho do OSM mais próximo (projeta o ponto da linha nova na volta do OSM)
    so, _ = lin_osm.proj(P[int(s_new / step) % len(P)][None])
    best = ''
    for c in nomes:
        if c['s0'] <= so[0] <= c['s1']:
            best = c['name']
    return best


peaks = []
absk = np.abs(kap_s)
for i in range(len(P)):
    if absk[i] < 1 / 220:
        continue
    w = absk[(np.arange(i - 20, i + 21)) % len(P)]
    if absk[i] >= w.max():
        peaks.append(i)
curvas = []
for i in peaks:
    sc = i * step
    so_ = float(np.interp(sc, SMAP_N, SMAP_A))
    r_old = 1 / max(abs(interp_c(kap_old, so_, L0r / len(kap_old), L0r)), 1e-6)
    Rt, Vm = [], []
    for lp in LAPS:
        ds_ = (lp['s'] - sc + L / 2) % L - L / 2
        m = np.abs(ds_) < 25
        if m.sum() < 5:
            continue
        vv = lp['v'][m]
        aa = np.abs(lp['lat_g'][m])
        k = np.argmin(vv)
        a_ = np.median(aa[max(0, k - 6):k + 7])
        Rt.append(vv[k] ** 2 / max(a_, 0.5))
        Vm.append(vv[k] * 3.6)
    curvas.append({'s': round(sc), 's_antigo': round(so_), 'nome': nome_em(sc), 'lado': 'dir' if kap_s[i] > 0 else 'esq',
                   'raio_novo': round(1 / absk[i], 1), 'raio_antigo': round(r_old, 1),
                   'raio_tel_v2_a': round(float(np.median(Rt)), 1), 'vmin_kmh': round(float(np.median(Vm)), 1),
                   'v_permitida_kmh_a_lat_tel': None})
A_CAP = 2.6 * 9.81   # aceleração lateral máxima plausível de um GT3 (iRacing: picos de 2,3–2,6 g)
for c in curvas:
    c['v_max_no_raio_kmh'] = round(math.sqrt(A_CAP * c['raio_novo']) * 3.6, 1)
    # o raio da linha central permite a velocidade da telemetria? (o carro ainda pode abrir a trajetória)
    c['ok'] = bool(c['v_max_no_raio_kmh'] >= c['vmin_kmh'])
    c.pop('v_permitida_kmh_a_lat_tel', None)
V['curvas'] = curvas
say('curvas (raio mínimo da linha central × v²/a_lat da telemetria no ponto de v mínima):')
for c in curvas:
    say(f'  s {c["s"]:5d} (antigo {c["s_antigo"]:5d}) {c["nome"]:22s} {c["lado"]}: R novo {c["raio_novo"]:6.1f} m, '
        f'antigo {c["raio_antigo"]:6.1f}, telemetria {c["raio_tel_v2_a"]:6.1f} m a {c["vmin_kmh"]:5.1f} km/h'
        f'; v máx no raio (2,6 g) {c["v_max_no_raio_kmh"]:5.1f}{"" if c["ok"] else "  <-- raio não permite a velocidade"}')

# ---- borda nova × satélite (medida na linha nova, só conf. alta)
devL = (WLn - fL)[cfL == 2]
devR = (WRn - fR)[cfR == 2]
V['borda_vs_satelite'] = {'esq': {'mediana_abs': round(float(np.median(np.abs(devL))), 2), 'p95_abs': round(float(np.percentile(np.abs(devL), 95)), 2),
                                  'mediana': round(float(np.median(devL)), 2), 'n': int(len(devL))},
                          'dir': {'mediana_abs': round(float(np.median(np.abs(devR))), 2), 'p95_abs': round(float(np.percentile(np.abs(devR), 95)), 2),
                                  'mediana': round(float(np.median(devR)), 2), 'n': int(len(devR))},
                          'antes': DIAG['antes']}
# conferência independente: detector próprio (mede) na linha nova, só onde ele e a Fase 2 têm confiança alta
for lado, W, g, cg in (('esq', WLn, gL2, cgL2), ('dir', WRn, gR2, cgR2)):
    m = cg == 2
    dv = (W - g)[m]
    V['borda_vs_satelite'][lado + '_detector_proprio'] = {'mediana_abs': round(float(np.median(np.abs(dv))), 2),
                                                          'p95_abs': round(float(np.percentile(np.abs(dv), 95)), 2),
                                                          'mediana': round(float(np.median(dv)), 2), 'n': int(m.sum())}
say(f'borda nova × detector próprio (independente da Fase 2): {V["borda_vs_satelite"]["esq_detector_proprio"]} | '
    f'{V["borda_vs_satelite"]["dir_detector_proprio"]}')
say(f'borda nova × satélite (conf alta): esq |dev| mediana {V["borda_vs_satelite"]["esq"]["mediana_abs"]}, p95 '
    f'{V["borda_vs_satelite"]["esq"]["p95_abs"]}; dir {V["borda_vs_satelite"]["dir"]["mediana_abs"]}, p95 '
    f'{V["borda_vs_satelite"]["dir"]["p95_abs"]} (antes {DIAG["antes"]["borda_menos_w_mediana_abs"]}, p95 {DIAG["antes"]["p95_abs"]})')

# ---- mapa de s
ds_map = sm_n - s0_old * (L / L0)
V['mapa_s'] = {'max_abs_s_novo_menos_s_antigo': round(float(np.max(np.abs(sm_n - s0_old))), 2),
               'onde_s_antigo': float(s0_old[np.argmax(np.abs(sm_n - s0_old))]),
               'max_abs_menos_escala': round(float(np.max(np.abs(ds_map))), 2),
               'onde_escala_s_antigo': float(s0_old[np.argmax(np.abs(ds_map))]),
               'lateral_max_abs': round(float(np.max(np.abs(sm_d))), 2), 'onde_lateral_s_antigo': float(s0_old[np.argmax(np.abs(sm_d))]),
               'lateral_mediana_abs': round(float(np.median(np.abs(sm_d))), 2),
               'lateral_p95_abs': round(float(np.percentile(np.abs(sm_d), 95)), 2),
               'platos_monotonia': int(np.sum(np.diff(sm_n) <= 1e-6))}
say(f'mapa s antigo → novo: {V["mapa_s"]}')

# ---- s = 0 × voltas do Garage 61: onde começa cada volta (primeira amostra, descontado LapDistPct)
st = []
for lp in LAPS:
    s_first = lp['s'][0] - lp['pct'][0] * L
    st.append(((s_first + L / 2) % L) - L / 2)
fl = np.array(osm['finishLine'])
sfl = ((lin.proj(fl)[0] + L / 2) % L - L / 2) if len(fl) else []
V['linha_chegada'] = {'s_inicio_voltas_g61': [round(float(x), 2) for x in st], 'mediana': round(float(np.median(st)), 2),
                      'osm_finish_line_s': [round(float(x), 1) for x in sfl],
                      'deslocamento_s0_lateral_m': round(float(d_start[0]), 2)}
say(f'linha de chegada: início das voltas do G61 em s {np.round(st, 1)} (mediana {np.median(st):+.1f} m); '
    f'OSM "Finish Line" em s {np.round(sfl, 1)}')

# ---- referencial final: linha nova × OSM e × atual
Mn = P + R * ((WRn - WLn) / 2)[:, None]
s_on, d_on = Linha(Mn).proj(O1)
_, k_on = Linha(Mn).tree.query(O1)
v_on, _ = lsq_transl(R[k_on], d_on)
_, d_an = Linha(Mn).proj(M0)
_, k_an = Linha(Mn).tree.query(M0)
v_an, _ = lsq_transl(R[k_an], d_an)
DIAG['referencial']['osm_menos_nova'] = v_on.round(2).tolist()
DIAG['referencial']['atual_menos_nova'] = v_an.round(2).tolist()
DIAG['referencial']['osm_d_nova_mediana'] = round(float(np.median(np.abs(d_on))), 2)
DIAG['referencial']['osm_d_nova_p95'] = round(float(np.percentile(np.abs(d_on), 95)), 2)
say(f'referencial final: OSM = nova + {v_on.round(2)} (|d| mediana {np.median(np.abs(d_on)):.2f}, p95 '
    f'{np.percentile(np.abs(d_on), 95):.2f}); atual = nova + {v_an.round(2)}')

# zebras em s novo (tabela)
V['zebras'] = [{'lado': z['lado'], 's0_antigo': z['s0'], 's1_antigo': z['s1'], 'classe': z['classe'], 'fonte': z['fonte'],
                's0_novo': KCLS[(z['lado'], z['s0'])][0], 's1_novo': KCLS[(z['lado'], z['s0'])][1],
                'largura_fisica_mediana': KCLS[(z['lado'], z['s0'])][2]} for z in PZ.ZEBRAS]
V['muros'] = {l: {'osm_pct': round(float(np.mean(WSRC[:, c] == 3) * 100), 1), 'satelite_pct': round(float(np.mean(WSRC[:, c] == 2) * 100), 1),
                  'perfil_sat_diverge_pct': round(float(np.mean(WSRC[:, c] == 1) * 100), 1),
                  'nao_medido_pct': round(float(np.mean(WSRC[:, c] <= 1) * 100), 1),
                  'mediana_m': round(float(np.median(WALL[:, c])), 2),
                  'empurrado_para_fora_da_zebra_m': EMPURRADO[l],
                  'abaixo_de_w_mais_2_5_pct': round(float(np.mean(WALL[:, c] < (WLn if c == 0 else WRn) + 2.5) * 100), 1)}
           for l, c in (('esq', 0), ('dir', 1))}
V['larguras'] = {'total_mediana': round(float(np.median(WLn + WRn)), 2), 'total_min': round(float(np.min(WLn + WRn)), 2),
                 'total_max': round(float(np.max(WLn + WRn)), 2), 'total_p5': round(float(np.percentile(WLn + WRn, 5)), 2),
                 'total_p95': round(float(np.percentile(WLn + WRn, 95)), 2),
                 'esq_mediana': round(float(np.median(WLn)), 2), 'dir_mediana': round(float(np.median(WRn)), 2),
                 'conf_alta_pct': [round(float(np.mean(cfL == 2) * 100), 1), round(float(np.mean(cfR == 2) * 100), 1)],
                 'conf_baixa_pct': [round(float(np.mean(cfL == 0) * 100), 1), round(float(np.mean(cfR == 0) * 100), 1)],
                 'gps_m': [int(GPS_FIX[:, 0].sum()), int(GPS_FIX[:, 1].sum())],
                 'dois_tons_m': [int(DOIS_TONS[0].sum()), int(DOIS_TONS[1].sum())],
                 'piso_tumftm_m': [int(PISO_TUM[:, 0].sum()), int(PISO_TUM[:, 1].sum())]}
V['centro_fonte_pct'] = {'duas_bordas': round(float(np.mean(fonte_centro == 2) * 100), 1),
                         'uma_borda': round(float(np.mean(fonte_centro == 1) * 100), 1),
                         'vizinhanca': round(float(np.mean(fonte_centro == 0) * 100), 1)}
V['secoes'] = sections
DIAG['validacao'] = V
json.dump(DIAG, open(os.path.join(IMG, 'diag.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
np.savez_compressed(os.path.join(IMG, 'diag.npz'), P=P, WL=WLn, WR=WRn, KL=KL, KR=KR, WALL=WALL, WSRC=WSRC, fL=fL, fR=fR,
                    cfL=cfL, cfR=cfR, s_old=s_old, d_old=d_old, env=env, OFF=OFF_F2, gL2=gL2, gR2=gR2, cgL2=cgL2, cgR2=cgR2,
                    laps_xz=np.vstack([lp['xz'] for lp in LAPS]), laps_s=np.concatenate([lp['s'] for lp in LAPS]),
                    laps_d=np.concatenate([lp['d'] for lp in LAPS]), GPS_FIX=GPS_FIX, PISO_TUM=PISO_TUM, DOIS_TONS=np.stack(DOIS_TONS, 1))

if '--sem-imagens' in sys.argv:
    sys.exit(0)

# ================================================================ 9) imagens de conferência
PX = 4
COR_MURO = {4: (0, 255, 255), 3: (255, 0, 255), 2: (255, 150, 0), 1: (200, 200, 200), 0: (255, 255, 255)}   # 4 = etapa F


def faixa(a, b):
    """desenrolado na linha nova: s em x (4 px/m), d em y (4 px/m, esquerda em cima), satélite registrado."""
    sub = IMG_U[a:b].transpose(1, 0, 2).astype(np.uint8).repeat(PX, axis=1)
    im = Image.fromarray(sub)
    dr = ImageDraw.Draw(im)
    y = lambda dd: (dd + 18.0) / 0.25
    for j in range(a, b):
        x = (j - a) * PX
        # linha antiga (ciano), centro novo (verde)
        dr.point((x, y(d_old[j])), fill=(0, 255, 255))
        dr.point((x + 2, y(0)), fill=(0, 255, 0))
        for sg, W, K, cf, col, fe in ((-1, WLn, KL, cfL, 0, fL), (1, WRn, KR, cfR, 1, fR)):
            ce = (255, 0, 0) if cf[j] == 2 else (255, 140, 0) if cf[j] == 1 else (160, 0, 255)
            if GPS_FIX[j, col]:
                ce = (0, 120, 255)
            dr.line([(x, y(sg * W[j])), (x + PX - 1, y(sg * W[j]))], fill=ce)
            if cf[j] > 0:
                dr.point((x + 1, y(sg * fe[j])), fill=(255, 255, 255))
            if K[j] > 0:
                dr.line([(x, y(sg * (W[j] + K[j]))), (x + PX - 1, y(sg * (W[j] + K[j])))], fill=(255, 255, 0))
            wv = WALL[j, col]
            if abs(wv) < 18:
                dr.line([(x, y(sg * wv)), (x + PX - 1, y(sg * wv))], fill=COR_MURO[WSRC[j, col]])
        if j % 10 == 0:
            dr.line([(x, 0), (x, 4)], fill=(255, 255, 0))
            if j % 50 == 0:
                dr.text((x + 2, 1), str(int(round(j * step))), fill=(255, 255, 0))
    # voltas (azul claro): uma amostra a cada 3
    for lp in LAPS:
        for s_, d_ in zip(lp['s'][::3], lp['d'][::3]):
            j = s_ / step
            if a <= j < b and abs(d_) < 18:
                im.putpixel((int((j - a) * PX), int(y(d_))), (120, 200, 255))
    return im


for a in range(0, len(P), 400):
    b = min(a + 400, len(P))
    faixa(a, b).save(os.path.join(IMG, f'faixa_{int(round(a * step)):04d}.png'))

H = Image.fromarray(sat)


def to_px(xz):
    r, c = pix(xz[:, 0] + OFF_F2[0], xz[:, 1] + OFF_F2[1])
    return np.stack([c, r], 1)


def cima(nome, s_a, s_b, escala=2.0):
    if s_b <= s_a:
        s_b += L
    ii = np.arange(int(s_a / step), int(s_b / step)) % len(P)
    pts = {}
    pts['c'] = P[ii]
    pts['old'] = world_from_old(s_old[ii], np.zeros(len(ii)))
    pts['L'] = P[ii] - R[ii] * WLn[ii, None]
    pts['R'] = P[ii] + R[ii] * WRn[ii, None]
    pts['kL'] = P[ii] - R[ii] * (WLn + KL)[ii, None]
    pts['kR'] = P[ii] + R[ii] * (WRn + KR)[ii, None]
    pts['wL'] = P[ii] - R[ii] * WALL[ii, 0, None]
    pts['wR'] = P[ii] + R[ii] * WALL[ii, 1, None]
    allp = to_px(np.vstack([pts['wL'], pts['wR'], pts['c']]))
    x0, y0 = np.floor(allp.min(0)) - 20
    x1, y1 = np.ceil(allp.max(0)) + 20
    crop = H.crop((int(x0), int(y0), int(x1), int(y1))).convert('RGB')
    dr = ImageDraw.Draw(crop)
    pl = lambda q: [tuple(p) for p in (to_px(q) - [x0, y0])]
    for lp in LAPS:
        m = np.isin(np.round(lp['s'] / step).astype(int) % len(P), ii)
        for p in pl(lp['xz'][m][::2]):
            dr.point(p, fill=(120, 200, 255))
    dr.line(pl(pts['old']), fill=(0, 255, 255), width=1)
    dr.line(pl(pts['c']), fill=(0, 255, 0), width=1)
    for side, col in (('L', 0), ('R', 1)):
        cf = cfL if col == 0 else cfR
        q = pl(pts[side])
        for k in range(len(q) - 1):
            ce = (255, 0, 0) if cf[ii[k]] == 2 else (255, 140, 0) if cf[ii[k]] == 1 else (160, 0, 255)
            if GPS_FIX[ii[k], col]:
                ce = (0, 120, 255)
            dr.line([q[k], q[k + 1]], fill=ce, width=2)
        K = KL if col == 0 else KR
        qk = pl(pts['k' + side])
        for k in range(len(qk) - 1):
            if K[ii[k]] > 0:
                dr.line([qk[k], qk[k + 1]], fill=(255, 255, 0), width=2)
        qw = pl(pts['w' + side])
        for k in range(len(qw) - 1):
            dr.line([qw[k], qw[k + 1]], fill=COR_MURO[WSRC[ii[k], col]], width=1)
    for k in range(0, len(ii), 50):
        p = pl(pts['c'][k:k + 1])[0]
        dr.text((p[0] + 4, p[1]), str(int(round(ii[k] * step))), fill=(255, 255, 255))
    if escala != 1.0:
        crop = crop.resize((int(crop.width * escala), int(crop.height * escala)), Image.LANCZOS)
    crop.save(os.path.join(IMG, f'cima_{nome}.jpg'), quality=90)


def sn(s_antigo):
    return float(s_novo_de_antigo(s_antigo))


CORTES = [('reta_boxes_a', sn(3880), sn(4294)), ('reta_boxes_b', 0, sn(300)), ('s_do_senna', sn(250), sn(560)),
          ('curva_do_sol', sn(540), sn(900)), ('lago', sn(1340), sn(1780)), ('ferradura', sn(1880), sn(2280)),
          ('pinheirinho', sn(2280), sn(2700)), ('bico_mergulho', sn(2650), sn(3100)), ('juncao', sn(3080), sn(3480)),
          ('subida_boxes', sn(3450), sn(3900))]
for nome, a, b in CORTES:
    cima(nome, a, b)
# volta inteira (1/4 da resolução)
q = to_px(P)
sm = H.resize((H.width // 4, H.height // 4), Image.BILINEAR)
dr = ImageDraw.Draw(sm)
dr.line([tuple(p) for p in to_px(world_from_old(s_old, np.zeros(len(P))))[::2] / 4], fill=(0, 255, 255), width=1)
dr.line([tuple(p) for p in q[::2] / 4], fill=(0, 255, 0), width=1)
for k in range(0, len(P), 200):
    dr.text(tuple(q[k] / 4 + 4), str(int(round(k * step))), fill=(255, 255, 0))
sm.save(os.path.join(IMG, 'volta_cima.jpg'), quality=88)
say('imagens em', IMG)
