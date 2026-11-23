# Perfil lateral de Interlagos medido no satélite Esri World Imagery z19 (~0,27 m/px), perpendicular à pista a
# cada 1 m de s, dos dois lados, da borda do asfalto até ~40 m para fora (PLANO-INTERLAGOS-DETALHES.md, Fase 2A).
#
# Entrada:  data/track/track.json (n, passo 2 m, stride 16: p.xyz, t.xyz, r.xz, wl, wr, kerbL/R, runL/R, wallL/R)
#           build/interlagos/sat19.npy + sat19.json   (python tools/tracks/interlagos/download.py)
# Saída:    tools/tracks/interlagos/interlagos-perfil-sat.json   (processado, versionado)
#           build/interlagos/overlay/*.png                        (conferência, fora do git)
#
# Convenções da saída (todas as distâncias em metros):
#   s      = metro da volta no s do track.json atual (0 = amostra 0; passo 1 m)
#   borda  = distância lateral da linha central do track.json até a borda do asfalto medida (fim do asfalto
#            escuro / começo da linha branca), positiva para fora daquele lado. Comparar com wl/wr.
#   o resto (zebra, pintura, escape, muro) é medido A PARTIR DA BORDA MEDIDA, para fora.
#   conf   = 2 alta, 1 média, 0 baixa (sombra, copa de árvore, ponte/estrutura, borda incerta, sem imagem).
#
# Georreferência (igual ao jogo web, gt3-time-attack/scripts/ref-lib.ts): origem lat -23.7036, lon -46.6997;
#   x = (lon - lon0)·111320·cos(lat0), z = -(lat - lat0)·111320. Tiles z19 Web Mercator. Um deslocamento global do
#   mosaico (OFFSET, metros em x/z) é estimado pelas bordas e aplicado se for significativo.
#
# uso (de REPOS/gt3-godot): python tools/tracks/interlagos/build_perfil.py [--sem-offset]
import json
import math
import os
import sys

import numpy as np
sys.stdout.reconfigure(encoding="utf-8")
from PIL import Image, ImageDraw
from scipy.ndimage import map_coordinates, median_filter, uniform_filter1d

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'interlagos')
OVL = os.path.join(RAW, 'overlay')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'interlagos-perfil-sat.json')
os.makedirs(OVL, exist_ok=True)

LAT0, LON0 = -23.7036, -46.6997
ML = 111320.0
MO = ML * math.cos(math.radians(LAT0))
NT = 2 ** 19
DS = 0.25            # passo de amostragem em s (m)
DD = 0.25            # passo de amostragem em d (m)
DMAX = 52.0          # amostra d em [-DMAX, DMAX)
ALCANCE = 40.0       # escape medido até 40 m da borda

# ---------------------------------------------------------------- pista
t = json.load(open(os.path.join(ROOT, 'data', 'track', 'track.json')))
n = t['n']
L = float(t['length'])
S = np.array(t['s'], float).reshape(n, 16)


def interp(s, cols):
    u = (np.asarray(s) % L) / 2.0
    i0 = np.floor(u).astype(int) % n
    i1 = (i0 + 1) % n
    f = (u - np.floor(u))[..., None]
    return S[i0][:, cols] * (1 - f) + S[i1][:, cols] * f


s4 = np.arange(0.0, L, DS)                 # amostras finas
NS4 = len(s4)
NS1 = int(math.floor(L))                   # metros 0..NS1-1
P4 = interp(s4, [0, 2])
R4 = interp(s4, [6, 7])
R4 /= np.linalg.norm(R4, axis=1)[:, None]
d = np.arange(-DMAX, DMAX, DD)
ND = len(d)
I0 = int(round(DMAX / DD))                 # índice de d = 0
s1 = np.arange(NS1, dtype=float)
M1 = interp(s1, list(range(8, 16)))         # wl wr kL kR rL rR WL WR por metro
R1 = interp(s1, [6, 7])
R1 /= np.linalg.norm(R1, axis=1)[:, None]

# ---------------------------------------------------------------- satélite
meta = json.load(open(os.path.join(RAW, 'sat19.json')))
sat = np.load(os.path.join(RAW, 'sat19.npy'))
CH = [sat[..., k].astype(np.float32) for k in range(3)]
VALID = (sat.max(2) > 0).astype(np.float32)


def pix(x, z):
    lat = LAT0 - np.asarray(z) / ML
    lon = LON0 + np.asarray(x) / MO
    tx = (lon + 180.0) / 360.0 * NT
    lr = np.radians(lat)
    ty = (1.0 - np.log(np.tan(lr) + 1.0 / np.cos(lr)) / math.pi) / 2.0 * NT
    return (ty - meta['ty0']) * 256.0 - 0.5, (tx - meta['tx0']) * 256.0 - 0.5


def desenrola(off):
    """imagem desenrolada (ND linhas de d × NS4 colunas de s) com o mosaico deslocado de off=(ox,oz)."""
    x = P4[:, 0, None] + R4[:, 0, None] * d[None] + off[0]
    z = P4[:, 1, None] + R4[:, 1, None] * d[None] + off[1]
    r, c = pix(x.ravel(), z.ravel())
    img = np.stack([map_coordinates(ch, [r, c], order=1, mode='constant') for ch in CH], -1)
    ok = map_coordinates(VALID, [r, c], order=0, mode='constant')
    return img.reshape(NS4, ND, 3).transpose(1, 0, 2), ok.reshape(NS4, ND).T > 0.5


# ---------------------------------------------------------------- classes por pixel
#  0 asfalto escuro · 1 asfalto claro/concreto · 2 branco · 3 amarelo · 4 verde vivo · 5 verde-água (pintura do
#  escape) · 6 vermelho · 7 grama · 8 terra/brita (bege/alaranjado) · 9 sombra/copa (escuro esverdeado) · 10 outro
NOMES = ['asfalto', 'asfalto claro', 'branco', 'amarelo', 'verde', 'verde-agua', 'vermelho', 'grama', 'terra/brita',
         'sombra/copa', 'outro']
PAL = np.array([[40, 40, 40], [140, 140, 140], [255, 255, 255], [255, 220, 0], [0, 210, 0], [0, 200, 200],
                [230, 0, 0], [120, 165, 60], [215, 160, 95], [70, 0, 100], [255, 0, 255]], np.uint8)


def classifica(img):
    R, G, B = img[..., 0], img[..., 1], img[..., 2]
    v = img.mean(2)
    sat = img.max(2) - img.min(2)
    c = np.full(v.shape, 10, np.uint8)
    c[(sat <= 30) & (v < 100)] = 0
    c[(sat <= 32) & (v >= 100) & (v < 155)] = 1
    c[(G >= R - 2) & (G - B >= 12) & (v >= 45)] = 7
    c[(R - B >= 22) & (R >= G - 4) & (v >= 95)] = 8
    c[(v < 60) & (B < np.minimum(R, G) - 6)] = 9
    c[(G - R >= 20) & (B - R >= 5)] = 5      # verde pintado (verde-água): B acima de R; grama tem B bem abaixo de R
    c[(G - R >= 35) & (G - B >= 25) & (sat >= 45) & (v >= 70)] = 4
    c[(R - G >= 40) & (R - B >= 35) & (R >= 90)] = 6
    c[(R >= 120) & (G >= 105) & (R - B >= 50) & (np.abs(R - G) < 45)] = 3
    c[(v >= 155) & (sat <= 45)] = 2
    return c, v, sat


def periodico(v):
    """amplitude da componente periódica ao longo de s (zebra: ciclo 2,0–3,2 m), janela de 6 m."""
    W = int(round(6.0 / DS))
    vm = v - uniform_filter1d(v, W, axis=1, mode='wrap')
    xs = np.arange(v.shape[1]) * DS
    best = np.zeros_like(v)
    for per in np.arange(2.0, 3.25, 0.1):
        a = uniform_filter1d(vm * np.cos(2 * np.pi * xs / per), W, axis=1, mode='wrap')
        b = uniform_filter1d(vm * np.sin(2 * np.pi * xs / per), W, axis=1, mode='wrap')
        best = np.maximum(best, 2.0 * np.sqrt(a * a + b * b))
    return best


def por_metro(a, fn=np.median):
    """reduz colunas de 0,25 m para 1 m (janela de ±1,5 m centrada em cada metro)."""
    k = int(round(1.0 / DS))
    W = int(round(3.0 / DS)) + 1
    idx = (np.arange(NS1) * k)[:, None] + np.arange(-(W // 2), W // 2 + 1)[None]
    idx %= a.shape[1]
    return fn(a[:, idx], axis=2)


def moda_classes(c):
    cont = np.stack([por_metro((c == k).astype(np.float32), np.mean) for k in range(11)], 0)
    return cont.argmax(0).astype(np.uint8)


# ---------------------------------------------------------------- borda do asfalto
def dist_asfalto(img, centro=None):
    """distância RGB (por metro, ND × NS1) até a cor do asfalto da própria pista naquele trecho. O satélite é um
    mosaico de fotos de datas diferentes: o asfalto vai de quase preto a cinza-claro e marrom, então a referência é
    local (mediana de ±2 m em volta do centro numa janela de ±5 m em s), não um limiar fixo."""
    rgb = np.stack([por_metro(img[..., k]) for k in range(3)], -1)
    k2 = int(2.0 / DD)
    c = np.zeros(NS1, int) if centro is None else np.round(centro / DD).astype(int)
    rows = I0 + c[None, :] + np.arange(-k2, k2 + 1)[:, None]
    banda = rgb[rows, np.arange(NS1)[None, :]]
    ref = np.stack([median_filter(np.median(banda[..., k], 0), size=11, mode='wrap') for k in range(3)], -1)
    dist = np.linalg.norm(rgb - ref[None], axis=2)
    thr = np.maximum(40.0, 0.3 * np.linalg.norm(ref, axis=1))[None]
    return dist, thr, ref


def _anda(asf, pico, j, sg, c0):
    """do centro (índice c0) para fora: para no primeiro trecho não-asfalto de ≥ 0,75 m ou numa linha clara
    estreita a ≥ 4 m do centro. Devolve a distância a partir do centro c0."""
    run = 0
    for k in range(0, int(24 / DD)):
        i = c0 + sg * k
        if i < 0 or i >= ND:
            return np.nan
        if not asf[i, j]:
            run += 1
            if run >= 3:
                return (k - 2) * DD
        else:
            run = 0
        if k * DD >= 4.0 and pico[i, j]:
            return k * DD
    return np.nan


PAV = [None]


def bordas(cls, v, sat):
    """por metro e lado: distância da linha central do track.json até o fim do asfalto (bruta e suavizada) +
    flag de incerteza. Duas passadas: a 2ª recalcula a cor de referência e parte do centro medido na 1ª."""
    vs = por_metro(v)
    ss = por_metro(sat)
    lo = np.minimum(np.roll(vs, 4, axis=0), np.roll(vs, -4, axis=0))
    centro = np.zeros(NS1)
    cls_m = moda_classes(cls)
    for passada in range(2):
        dist, thr, ref = dist_asfalto(IMG_ATUAL[0], centro)
        # pavimento: cinza neutro (qualquer brilho até 175; o asfalto de Interlagos tem faixas claras e escuras
        # lado a lado), faixa neutra bem mais clara/escura que a referência só se for larga (≥ 2 m: asfalto novo/claro, não topo de muro nem linha), ou perto
        # da cor de referência local (asfalto amarronzado de algumas fotos)
        neutro = ss <= 28
        vref = ref.mean(1)[None]
        claro = neutro & (vs - vref > 55)        # só o mais claro quebra (muro, linha); cinza escuro é asfalto/sombra
        largo = np.zeros_like(claro)
        kk = int(2.0 / DD)
        cs = np.cumsum(np.vstack([np.zeros((1, NS1)), claro]), 0)
        for i in range(ND):
            a0, a1 = max(0, i - kk // 2), min(ND, i + kk // 2 + 1)
            largo[i] = (cs[a1] - cs[a0]) >= (a1 - a0) - 1
        asf = (neutro & ~claro) | (claro & largo) | (dist <= thr)
        # zebra (blocos alternados, modulação forte) não é pavimento, mesmo com blocos brancos/cinza; só a ≥ 4 m do
        # centro (no meio da pista a modulação é borracha/remendo)
        longe = np.abs(d)[:, None] >= 4.0
        asf &= ~((PER1[0] >= 1.4 * ZEB_A) & longe)
        PAV[0] = asf
        pico = (vs - lo >= 22) & (vs >= ref.mean(1)[None] + 30)
        out = {}
        c0 = I0 + np.round(centro / DD).astype(int)
        fraco = (vs - lo >= 10) & (vs >= ref.mean(1)[None] + 12)
        for lado, sg, col in (('esq', -1, 0), ('dir', 1, 1)):
            e = np.array([_anda(asf, pico, j, sg, c0[j]) + sg * centro[j] for j in range(NS1)])
            fonte = np.zeros(NS1, int)   # 0 transição medida · 1 linha fraca · 2 sem medida (usa o modelo)
            w = M1[:, col]
            # borda esperada deste lado: a do modelo deslocada pelo centro local medido (geometria do track.json
            # tem erros locais de 2–3 m, então a tolerância é relativa ao centro medido, não ao modelo)
            w = w + sg * centro
            for j in range(NS1):
                if not np.isnan(e[j]) and e[j] < w[j] - 1.0:
                    # parou cedo: pista em dois tons (faixa recapeada mais escura/clara). Se até 3,5 m adiante só
                    # houver cinza (sem grama, pintura ou zebra) e uma linha branca, a borda é essa linha.
                    k0 = int(round(e[j] / DD))
                    for k in range(k0 + 1, k0 + int(3.5 / DD)):
                        i = I0 + sg * k
                        if not (0 <= i < ND) or ss[i, j] > 40 or cls_m[i, j] in (4, 5, 6, 7, 9):
                            break
                        if fraco[i, j] and abs(k * DD - w[j]) <= 2.0:
                            e[j] = k * DD
                            fonte[j] = 1
                            break
                if np.isnan(e[j]) or e[j] > w[j] + 2.0:
                    # asfalto do escape da mesma cor: procura a linha branca (fraca) perto da borda do modelo
                    ks = np.arange(int((w[j] - 2.0) / DD), int((w[j] + 2.0) / DD) + 1)
                    ii = I0 + sg * ks
                    hit = ks[fraco[ii, j]]
                    if len(hit):
                        e[j] = hit[np.argmin(np.abs(hit * DD - w[j]))] * DD
                        fonte[j] = 1
                    else:
                        e[j] = np.nan
                        fonte[j] = 2
            ok = ~np.isnan(e)
            ef = np.where(ok, e, w)
            med = median_filter(ef, size=21, mode='wrap')
            ruim = (~ok) | (np.abs(ef - med) > 1.0)
            final = median_filter(np.where(ruim, med, ef), size=5, mode='wrap')
            out[lado] = (e, final, ruim, fonte)
        # centro medido (suave) para a 2ª passada, limitado a ±4 m: média dos lados medidos com transição clara
        # (cada lado sozinho dá o centro pela largura do modelo)
        cR = np.where(out['dir'][3] == 0, out['dir'][1] - M1[:, 1], np.nan)
        cL = np.where(out['esq'][3] == 0, M1[:, 0] - out['esq'][1], np.nan)
        cm = np.nanmean(np.stack([cR, cL]), 0)
        cm = np.where(np.isnan(cm), np.nanmedian(cm), cm)
        centro = np.clip(median_filter(cm, size=31, mode='wrap'), -4, 4)
    return out


def ajusta_offset(B):
    """c(s) = (eR - eL)/2 - (wr - wl)/2 ≈ v·R(s): mínimos quadrados robustos (2 passadas, corte 1,5 m)."""
    eL, eR = B['esq'][1], B['dir'][1]
    ok = ~(B['esq'][2] | B['dir'][2])
    c = (eR - eL) / 2 - (M1[:, 1] - M1[:, 0]) / 2
    A = R1[ok]
    y = c[ok]
    v = np.zeros(2)
    for corte in (99.0, 1.5, 1.0):
        res = y - A @ v
        m = np.abs(res) < corte
        v = np.linalg.lstsq(A[m], y[m], rcond=None)[0]
    return v, c


def estat(B, nome):
    lin = []
    for lado, col in (('esq', 0), ('dir', 1)):
        e, f, ruim = B[lado][:3]
        dev = (f - M1[:, col])[~ruim]
        lin.append(f'{lado}: mediana {np.median(dev):+.2f} m, |dev| mediana {np.median(np.abs(dev)):.2f}, '
                   f'p95 {np.percentile(np.abs(dev), 95):.2f} m (n={len(dev)})')
    print(f'  [{nome}] ' + ' | '.join(lin))


# ---------------------------------------------------------------- execução
ZEB_A = 25.0          # amplitude mínima da modulação clara/escura (0–255) para ser zebra
PER1 = [None]
off = np.zeros(2)
img, valid = desenrola(off)
IMG_ATUAL = [img]
cls, v, sat_ = classifica(img)
PER1[0] = por_metro(periodico(v), np.max)
B = bordas(cls, v, sat_)
print('georreferência (borda medida × wl/wr do track.json):')
estat(B, 'sem offset')
voff, cc = ajusta_offset(B)
print(f'  offset global estimado: dx {voff[0]:+.2f} m, dz {voff[1]:+.2f} m (|v| = {np.hypot(*voff):.2f} m)')
ok = ~(B['esq'][2] | B['dir'][2])
r_antes = np.median(np.abs(cc[ok]))
r_dep = np.median(np.abs(cc[ok] - R1[ok] @ voff))
print(f'  desvio do centro |c| mediana {r_antes:.2f} → {r_dep:.2f} m com o offset')
aplicado = ('--sem-offset' not in sys.argv) and np.hypot(*voff) >= 0.3 and r_dep < 0.9 * r_antes
if aplicado:
    off = voff.copy()
    img, valid = desenrola(off)
    IMG_ATUAL[0] = img
    cls, v, sat_ = classifica(img)
    PER1[0] = por_metro(periodico(v), np.max)
    B = bordas(cls, v, sat_)
    estat(B, 'com offset')
    v2, _ = ajusta_offset(B)
    print(f'  resíduo do offset após aplicar: dx {v2[0]:+.2f} dz {v2[1]:+.2f}')
    if np.hypot(*v2) >= 0.3:
        off = off + v2
        img, valid = desenrola(off)
        IMG_ATUAL[0] = img
        cls, v, sat_ = classifica(img)
        PER1[0] = por_metro(periodico(v), np.max)
        B = bordas(cls, v, sat_)
        estat(B, f'offset refinado dx {off[0]:+.2f} dz {off[1]:+.2f}')
else:
    print('  offset NÃO aplicado (pequeno ou não melhora)')
B_raw_center = None

# ---------------------------------------------------------------- zebra (periodicidade junto da borda)
A = periodico(v)
A1 = PER1[0]                          # pico de amplitude na janela
cls1 = moda_classes(cls)
ZCOR = por_metro(np.isin(cls, (3, 4, 6, 7, 8, 9)).astype(np.float32), np.mean)
valid1 = por_metro(valid.astype(np.float32), np.min) > 0.5


def lado_dados(lado, sg):
    e, borda, ruim = B[lado][:3]
    zebra = np.zeros(NS1)
    pint = np.zeros(NS1)
    pcor = np.array([''] * NS1, dtype=object)
    esc = []
    muro = np.full(NS1, np.nan)
    conf = np.full(NS1, 2, int)
    sombra = np.zeros(NS1)
    for j in range(NS1):
        k_e = I0 + sg * int(round(borda[j] / DD))
        idx = lambda dist: I0 + sg * int(round((borda[j] + dist) / DD))
        # --- zebra: linhas com amplitude periódica alta (ciclo 2,0–3,2 m) começando a até 0,75 m da borda, com
        # cor saturada em ≥ 50% da faixa (no satélite o amarelo/verde da zebra cai nas classes grama/terra/verde
        # escuro) — sombra de alambrado e postes do muro dos boxes também são periódicos, mas cinza/brancos
        w = 0.0
        start = None
        for k in range(-2, int(0.75 / DD) + 1):
            i = k_e + sg * k
            if A1[i, j] >= ZEB_A:
                start = k
                break
        if start is not None:
            k = start
            while k < int(3.5 / DD):
                i = k_e + sg * k
                if A1[i, j] >= 0.6 * ZEB_A:
                    k += 1
                else:
                    break
            a0 = k_e + sg * start
            a1 = k_e + sg * k
            rr = np.arange(min(a0, a1), max(a0, a1) + 1)
            if len(rr) and ZCOR[rr, j].mean() >= 0.5:
                w = (k - max(start, 0)) * DD
        zebra[j] = w if w >= 0.5 else 0.0
        # --- pintura logo depois da zebra (ou da borda)
        p0 = zebra[j] + 0.25
        k = 0
        cores = []
        while p0 + k * DD < 15.0:
            c = cls1[idx(p0 + k * DD), j]
            if c in (4, 5):
                cores.append('verde')
            elif c == 6:
                cores.append('vermelha')
            elif c in (2, 3) and zebra[j] == 0 and k * DD < 1.5:
                cores.append('outra')
            else:
                break
            k += 1
        if k * DD >= 0.5:
            pint[j] = k * DD
            pcor[j] = max(set(cores), key=cores.count)
        # --- superfícies do escape: códigos a cada 0,5 m da borda até ALCANCE
        cod = []
        for dist in np.arange(0.0, ALCANCE, 0.5):
            i = idx(dist + 0.25)
            if i < 0 or i >= ND or not valid[i, j * 4]:
                cod.append('x')
                continue
            c = cls1[i, j]
            cod.append({0: 'a', 1: 'a', 2: 'p', 3: 'p', 4: 'p', 5: 'p', 6: 'p', 7: 'g', 8: 'b', 9: 's', 10: 'o'}[int(c)])
        esc.append(cod)
        # --- sombra/copa na faixa próxima
        faixa = [cls1[idx(dd_), j] for dd_ in np.arange(0.25, 10.0, 0.5)]
        sombra[j] = np.mean([c == 9 for c in faixa])
    return borda, ruim, zebra, pint, pcor, esc, sombra


def muro_lado(lado, sg, borda, zebra):
    """muro/barreira: linha estreita contínua em s (crista clara neutra ou risco escuro) além da zebra."""
    vs = por_metro(v)
    ss = por_metro(sat_)
    k1 = int(round(1.0 / DD))
    up = np.roll(vs, k1, axis=0)
    dn = np.roll(vs, -k1, axis=0)
    crista = ((vs - np.maximum(up, dn)) >= 25) & (ss <= 45)
    risco = ((np.minimum(up, dn) - vs) >= 30) & (vs <= 60)
    cand = np.full(NS1, np.nan)
    for j in range(NS1):
        for dist in np.arange(zebra[j] + 0.75, ALCANCE, DD):
            i = I0 + sg * int(round((borda[j] + dist) / DD))
            if i < 0 or i >= ND:
                break
            if crista[i, j] or risco[i, j]:
                cand[j] = dist
                break
    # persistência: o candidato tem que repetir (±0,6 m) em ≥ 60% dos vizinhos a ±5 m
    m = np.full(NS1, np.nan)
    for j in range(NS1):
        if np.isnan(cand[j]):
            continue
        viz = cand[(np.arange(j - 5, j + 6)) % NS1]
        if np.mean(np.abs(viz - cand[j]) <= 0.6) >= 0.6:
            m[j] = cand[j]
    return m


def runs(mask):
    """lista de (j0, j1) inclusivos de True em array circular (sem emendar 0/fim)."""
    out = []
    j = 0
    N_ = len(mask)
    while j < N_:
        if mask[j]:
            k = j
            while k + 1 < N_ and mask[k + 1]:
                k += 1
            out.append((j, k))
            j = k + 1
        else:
            j += 1
    if len(out) > 1 and out[0][0] == 0 and out[-1][1] == N_ - 1:
        a, b = out.pop(), out.pop(0)
        out.append((a[0], b[1] + N_))
    return out


def fecha_buracos(mask, gap=2):
    m = mask.copy()
    N_ = len(m)
    for j0, j1 in [(a, b) for a, b in runs(~mask)]:
        if j1 - j0 + 1 <= gap:
            for j in range(j0, j1 + 1):
                m[j % N_] = True
    return m


def rle_escape(cod):
    """'g4.5a12b40' — cada letra vale até a distância seguinte (m da borda). Moda ±1 m em s já aplicada."""
    out = []
    cur = cod[0]
    for i, c in enumerate(cod[1:], 1):
        if c != cur:
            out.append(f'{cur}{i * 0.5:g}')
            cur = c
    out.append(f'{cur}{len(cod) * 0.5:g}')
    return ''.join(out)


def limpa_escape(esc):
    """moda em s (±3 m) e remoção de trechos < 1,5 m em d."""
    E = np.array(esc)
    NS_, NDc = E.shape
    letras = np.array(list('apgbsox'))
    onehot = np.stack([(E == L_) for L_ in letras], -1).astype(np.float32)
    onehot = uniform_filter1d(onehot, 7, axis=0, mode='wrap')
    E2 = letras[onehot.argmax(-1)]
    for j in range(NS_):
        row = E2[j]
        i = 0
        segs = []
        while i < NDc:
            k = i
            while k + 1 < NDc and row[k + 1] == row[i]:
                k += 1
            segs.append([row[i], i, k])
            i = k + 1
        changed = True
        while changed and len(segs) > 1:
            changed = False
            for q, sgm in enumerate(segs):
                if sgm[2] - sgm[1] + 1 < 3:  # < 1,5 m
                    viz = segs[q - 1] if q > 0 else segs[q + 1]
                    sgm[0] = viz[0]
                    changed = True
            merged = []
            for sgm in segs:
                if merged and merged[-1][0] == sgm[0]:
                    merged[-1][2] = sgm[2]
                else:
                    merged.append(sgm)
            if len(merged) == len(segs) and not changed:
                break
            segs = merged
            changed = False
            if all(sg_[2] - sg_[1] + 1 >= 3 for sg_ in segs):
                break
        for c, a, b in segs:
            row[a:b + 1] = c
    return E2


# estruturas transversais (ponte, pórtico, faixa pintada atravessando): faixa central da pista sem asfalto
cen = PAV[0][I0 - int(3 / DD):I0 + int(3 / DD)]
cm_ = np.round((B['dir'][1] - B['esq'][1]) / 2 / DD).astype(int)
rows_ = I0 + np.clip(cm_, -16, 16)[None, :] + np.arange(-int(3 / DD), int(3 / DD))[:, None]
naoasf = 1.0 - PAV[0][rows_, np.arange(NS1)[None, :]].mean(0)
estrutura = naoasf > 0.35

resultado = {}
for lado, sg in (('esq', -1), ('dir', 1)):
    borda, ruim, zebra, pint, pcor, esc, sombra = lado_dados(lado, sg)
    E2 = limpa_escape(esc)
    muro = muro_lado(lado, sg, borda, zebra)
    conf = np.full(NS1, 2, int)
    fonte = B[lado][3]
    conf[(sombra > 0.15) | ruim | (fonte == 1)] = 1
    conf[fonte == 2] = 0
    conf[(sombra > 0.4) | estrutura | ~valid1[I0 + sg * 40]] = 0
    # borda incerta em sequência longa (> 5 m) também é baixa
    for a, b in runs(ruim):
        if b - a + 1 > 5:
            for j in range(a, b + 1):
                conf[j % NS1] = 0
    resultado[lado] = dict(borda=borda, ruim=ruim, zebra=zebra, pint=pint, pcor=pcor, esc=E2, muro=muro,
                           conf=conf, sombra=sombra, braw=B[lado][0])

# ---------------------------------------------------------------- segmentos consolidados
def segmentos_zebra(lado):
    z = resultado[lado]['zebra']
    m = fecha_buracos(z > 0, 4)
    segs = []
    for a, b in runs(m):
        if b - a + 1 < 5:
            continue
        idx = np.arange(a, b + 1) % NS1
        w = z[idx]
        w = w[w > 0]
        segs.append({'lado': lado, 's0': int(a), 's1': int(b + 1) % NS1 if b + 1 > NS1 else int(b + 1),
                     'larg': round(float(np.median(w)), 1), 'largMax': round(float(np.percentile(w, 90)), 1),
                     'conf': int(np.round(np.median(resultado[lado]['conf'][idx])))})
    return segs


def segmentos_pintura(lado):
    p = resultado[lado]['pint']
    c = resultado[lado]['pcor']
    segs = []
    for cor in ('verde', 'vermelha', 'outra'):
        m = fecha_buracos((p > 0) & (c == cor), 4)
        for a, b in runs(m):
            if b - a + 1 < 5:
                continue
            idx = np.arange(a, b + 1) % NS1
            w = p[idx]
            w = w[w > 0]
            segs.append({'lado': lado, 's0': int(a), 's1': int(b + 1) % NS1 if b + 1 > NS1 else int(b + 1), 'cor': cor,
                         'larg': round(float(np.median(w)), 1),
                         'conf': int(np.round(np.median(resultado[lado]['conf'][idx])))})
    return sorted(segs, key=lambda q: q['s0'])


zebras = segmentos_zebra('esq') + segmentos_zebra('dir')
zebras.sort(key=lambda q: (q['s0'], q['lado']))
pinturas = segmentos_pintura('esq') + segmentos_pintura('dir')
pinturas.sort(key=lambda q: (q['s0'], q['lado']))

# ---------------------------------------------------------------- estruturas transversais (para as âncoras)
transv = []
for a, b in runs(estrutura):
    transv.append({'s0': int(a), 's1': int(b + 1), 'naoAsfalto': round(float(naoasf[a:b + 1].max()), 2)})

# ---------------------------------------------------------------- JSON
r1 = lambda a: [None if (x is None or (isinstance(x, float) and np.isnan(x))) else round(float(x), 1) for x in a]
saida = {
    'versao': 1,
    'fonte': 'Esri World Imagery z19 (~0,27 m/px), tiles em build/interlagos/tiles19; '
             'tools/tracks/interlagos/build_perfil.py',
    'pista': 'data/track/track.json', 'comprimento': L, 'passo': 1, 'n': NS1,
    'offset': {'dx': round(float(off[0]), 2), 'dz': round(float(off[1]), 2), 'aplicado': bool(aplicado)},
    'legenda': {
        'borda': 'distância da linha central do track.json até o fim do asfalto medido (comparar com wl/wr)',
        'zebra': 'largura da zebra a partir da borda (0 = sem zebra)',
        'pint': 'largura da faixa pintada logo depois da zebra/borda; pintCor v=verde (verde-água no satélite), '
                'r=vermelha, o=outra (branca/amarela larga sem zebra), -=nada',
        'esc': 'superfícies da borda até 40 m: letra + distância final (m da borda). a=asfalto, p=pintura, '
               'g=grama, b=brita/terra (não dá para separar no satélite), s=sombra/copa (indefinido), o=outro, '
               'x=sem imagem',
        'muro': 'distância da borda até o muro/barreira (linha estreita contínua); null = não detectado',
        'conf': '2 alta, 1 média, 0 baixa (sombra/copa, ponte ou estrutura, borda incerta, sem imagem)',
    },
}
for lado in ('esq', 'dir'):
    R_ = resultado[lado]
    saida[lado] = {
        'borda': r1(R_['borda']),
        'zebra': r1(R_['zebra']),
        'pint': r1(R_['pint']),
        'pintCor': ''.join({'verde': 'v', 'vermelha': 'r', 'outra': 'o', '': '-'}[c] for c in R_['pcor']),
        'esc': [rle_escape(list(row)) for row in R_['esc']],
        'muro': r1(R_['muro']),
        'conf': ''.join(str(int(c)) for c in R_['conf']),
    }
for lado in ('esq', 'dir'):
    R_ = resultado[lado]
    print(f'  {lado}: sem medida {np.mean(B[lado][3] == 2) * 100:.1f}%, linha fraca {np.mean(B[lado][3] == 1) * 100:.1f}%, '
          f'sombra>0,4 {np.mean(R_["sombra"] > 0.4) * 100:.1f}%, estrutura {np.mean(estrutura) * 100:.1f}%, '
          f'sem imagem {np.mean(~valid1[I0 + (-1 if lado == "esq" else 1) * 40]) * 100:.1f}%')
# feições que o detector de zebra confunde (conferidas na imagem): ilha zebrada da entrada dos boxes
for z in zebras:
    if z['lado'] == 'esq' and 3960 <= z['s0'] <= 4015:
        z['obs'] = 'ilha com divisas (>>>) da entrada dos boxes, não é zebra'
# âncoras medidas no satélite (conferidas olhando a imagem desenrolada e a vista de cima; s do track.json atual,
# com o offset global aplicado). sCenario = onde o cenário (tools/cenario/interlagos) põe hoje.
ANCORAS = [
    {'nome': 'pórtico/estrutura fina sobre a reta principal (provável pórtico de largada; linha pintada não '
             'distinguível)', 's': 64.5, 'sombra': [67, 68.5], 'sCenario': 0, 'conf': 1},
    {'nome': 'passarela sobre a reta (freada do S do Senna): tabuleiro', 's0': 292, 's1': 297, 'sombra': [297, 302],
     'sCenario': 264.6, 'conf': 2},
    {'nome': 'saída dos boxes: fim do separador entre pit lane e pista (início da área zebrada diagonal)',
     's': 830, 'sCenario': 734, 'conf': 1, 'obs': 'cenário: ponteira do guard-rail em s 735 (escala 4300)'},
    {'nome': 'saída dos boxes: fim da área zebrada diagonal (pit lane já na pista)', 's': 895,
     'sCenario': 794, 'conf': 1},
    {'nome': 'pórtico sobre a Reta Oposta: sombra', 's': 984, 'sCenario': 1038.5, 'conf': 2},
    {'nome': 'pórtico sobre a Reta Oposta: estrutura (duas vigas claras)', 's0': 988, 's1': 1001.5,
     'sCenario': 1038.5, 'conf': 1},
    {'nome': 'entrada dos boxes: começo do separador/ilha (bico)', 's0': 3880, 's1': 3920, 'sCenario': 3880,
     'conf': 0, 'obs': 'não dá para cravar no satélite (sombra e baixa resolução); faixa provável'},
    {'nome': 'entrada dos boxes: divisas brancas (>>>) na ilha verde', 's0': 3975, 's1': 4005,
     'sCenario': [3880, 4032], 'conf': 1},
]
geo = {}
for lado, col in (('esq', 0), ('dir', 1)):
    e_, f_, ruim_, fonte_ = B[lado]
    ok_ = (~ruim_) & (fonte_ == 0)
    dev_ = f_[ok_] - M1[ok_, col]
    geo[lado] = {'medianaDesvio': round(float(np.median(dev_)), 2), 'medianaAbs': round(float(np.median(np.abs(dev_))), 2),
                 'p95Abs': round(float(np.percentile(np.abs(dev_), 95)), 2), 'n': int(ok_.sum())}
cen_ = (B['dir'][1] - B['esq'][1]) / 2 - (M1[:, 1] - M1[:, 0]) / 2
geo['centroMedianaAbs'] = round(float(np.median(np.abs(cen_))), 2)
geo['centroP95Abs'] = round(float(np.percentile(np.abs(cen_), 95)), 2)
geo['obs'] = ('desvio = borda medida − wl/wr do track.json (só metros com transição clara), depois do offset global; '
              'o que sobra é erro local da geometria do track.json (curvas deslocadas 2–4 m) e largura ~0,7 m maior '
              'no track.json por lado')
saida['georef'] = geo
print('georef final:', geo)
saida['ancoras'] = ANCORAS
saida['zebras'] = zebras
saida['pinturas'] = pinturas
saida['transversais'] = transv
json.dump(saida, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(f'{OUT}: {os.path.getsize(OUT) / 1024:.0f} KB')
np.savez_compressed(os.path.join(RAW, 'perfil_debug.npz'), img=img.astype(np.uint8), cls=cls, A=A.astype(np.float16),
                    off=off)

# ---------------------------------------------------------------- resumo
for lado in ('esq', 'dir'):
    c = resultado[lado]['conf']
    print(f'{lado}: zebras {sum(1 for z in zebras if z["lado"] == lado)}, pinturas '
          f'{sum(1 for z in pinturas if z["lado"] == lado)}, conf baixa {np.mean(c == 0) * 100:.1f}%, '
          f'média {np.mean(c == 1) * 100:.1f}%, muro detectado {np.mean(~np.isnan(resultado[lado]["muro"])) * 100:.0f}%')

# ---------------------------------------------------------------- imagens de conferência
PX = 4  # px por metro


def faixa(a, b):
    sub = img[:, a * 4:b * 4].astype(np.uint8)          # ND × (b-a)*4  (já 4 px/m em s e em d)
    top = Image.fromarray(sub)
    dr = ImageDraw.Draw(top)
    cl = Image.fromarray((0.45 * sub + 0.55 * PAL[cls[:, a * 4:b * 4]]).astype(np.uint8))
    dc = ImageDraw.Draw(cl)
    y = lambda dist: (dist + DMAX) / DD
    for j in range(a, min(b, NS1)):
        x = (j - a) * PX
        for lado, sg, cw, ck, cwall in (('esq', -1, 0, 2, 6), ('dir', 1, 1, 3, 7)):
            R_ = resultado[lado]
            e = R_['borda'][j]
            col_e = (255, 0, 0) if R_['conf'][j] == 2 else (255, 140, 0) if R_['conf'][j] == 1 else (160, 0, 255)
            for D_ in (dr, dc):
                D_.line([(x, y(sg * e)), (x + PX - 1, y(sg * e))], fill=col_e)
                # modelo: wl/wr (ciano), zebra do modelo (azul), muro do modelo (branco tracejado)
                D_.point((x + 1, y(sg * M1[j, cw])), fill=(0, 255, 255))
                if M1[j, ck] > 0:
                    D_.point((x + 2, y(sg * (M1[j, cw] + M1[j, ck]))), fill=(0, 90, 255))
                if j % 2 == 0:
                    D_.point((x, y(sg * M1[j, cwall])), fill=(255, 255, 255))
            z = R_['zebra'][j]
            if z > 0:
                for D_ in (dr, dc):
                    D_.line([(x, y(sg * (e + z))), (x + PX - 1, y(sg * (e + z)))], fill=(255, 255, 0))
            p = R_['pint'][j]
            if p > 0:
                colp = (0, 255, 120) if R_['pcor'][j] == 'verde' else (255, 60, 60) if R_['pcor'][j] == 'vermelha' else (230, 230, 230)
                for D_ in (dr, dc):
                    D_.line([(x, y(sg * (e + z + p))), (x + PX - 1, y(sg * (e + z + p)))], fill=colp)
            m = R_['muro'][j]
            if not np.isnan(m):
                for D_ in (dr, dc):
                    D_.line([(x, y(sg * (e + m))), (x + PX - 1, y(sg * (e + m)))], fill=(255, 0, 255))
        if j % 10 == 0:
            for D_ in (dr, dc):
                D_.line([(x, 0), (x, 5)], fill=(255, 255, 0))
                if j % 50 == 0:
                    D_.text((x + 2, 1), str(j), fill=(255, 255, 0))
    W_, H_ = top.size
    out = Image.new('RGB', (W_, 2 * H_ + 4), (0, 0, 0))
    out.paste(top, (0, 0))
    out.paste(cl, (0, H_ + 4))
    return out


for a in range(0, NS1, 400):
    faixa(a, min(a + 400, NS1)).save(os.path.join(OVL, f'faixa_{a:04d}.png'))

# vista de cima da volta inteira (meia resolução): bordas, zebras, pintura e muros medidos
H2 = sat[::2, ::2].copy()
top = Image.fromarray(H2)
dr = ImageDraw.Draw(top)


def ponto(j, dist):
    p = P4[j * 4]
    r_ = R4[j * 4]
    q = p + r_ * dist + off
    rr, cc_ = pix(q[0], q[1])
    return cc_ / 2, rr / 2


for j in range(NS1):
    for lado, sg in (('esq', -1), ('dir', 1)):
        R_ = resultado[lado]
        e = R_['borda'][j]
        cx, cy = ponto(j, sg * e)
        dr.point((cx, cy), fill=(255, 0, 0) if R_['conf'][j] else (160, 0, 255))
        if R_['zebra'][j] > 0:
            cx, cy = ponto(j, sg * (e + R_['zebra'][j]))
            dr.ellipse((cx - 1, cy - 1, cx + 1, cy + 1), fill=(255, 255, 0))
        if not np.isnan(R_['muro'][j]):
            cx, cy = ponto(j, sg * (e + R_['muro'][j]))
            dr.point((cx, cy), fill=(255, 0, 255))
    if j % 100 == 0:
        cx, cy = ponto(j, 0)
        dr.text((cx + 3, cy), str(j), fill=(255, 255, 255))
top.save(os.path.join(OVL, 'volta_cima.jpg'), quality=88)
print('imagens em', OVL)
