# Conferência da Fase 2 (PLANO-INTERLAGOS-DETALHES.md): o perfil lateral FINAL (data/track/visual_profile.json,
# avaliado como em tools/cenario/interlagos/perfil.ts) desenhado sobre o satélite, e a tabela de diferenças.
#
# Entrada:  data/track/visual_profile.json, data/track/track.json, tools/tracks/interlagos/interlagos-perfil-sat.json,
#           build/interlagos/sat19.npy + sat19.json (python tools/tracks/interlagos/download.py)
#           decisões de zebra/picos: ./perfil_zebras.py (ZEBRAS, NAO_APLICADAS, PICOS, PICOS_NAO)
# Saída:    build/interlagos/overlay_perfil/faixa_NNNN.png   satélite desenrolado (400 m por imagem, 4 px/m, d ±30 m)
#           build/interlagos/overlay_perfil/cima_volta.jpg   vista de cima da volta inteira (1/4 da resolução)
#           build/interlagos/overlay_perfil/cima_setorN.jpg  vista de cima por setor das Fases 3–10 (resolução cheia)
#           build/interlagos/perfil/diferencas.md            zebra a zebra + o que não foi aplicado, por setor
#
# Legenda das imagens (perfil final): ciano = borda do asfalto (wl/wr); amarelo cheio = zebra listrada;
#   verde = faixa verde atrás da zebra; laranja = salsicha; contorno verde-claro / azul-água / vermelho = fim do
#   escape pintado; branco = barreira (rail), magenta = muro (wall/rolex_pad), azul = tecpro.
#   Barras no alto (esq) e embaixo (dir) das faixas: vermelho = zebra do satélite, amarelo = zebra do perfil.
#
# uso (de REPOS/gt3-godot): python tools/tracks/interlagos/overlay_perfil.py
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import map_coordinates

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perfil_zebras as PZ  # noqa: E402

ROOT = PZ.ROOT
RAW = os.path.join(ROOT, 'build', 'interlagos')
OUT = os.path.join(RAW, 'overlay_perfil')
MD = os.path.join(RAW, 'perfil', 'diferencas.md')
os.makedirs(OUT, exist_ok=True)
os.makedirs(os.path.dirname(MD), exist_ok=True)

t, perfil = PZ.carrega()
sat = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'interlagos-perfil-sat.json'), encoding='utf-8'))
n = t['n']
L = float(t['length'])
S = np.array(t['s'], float).reshape(n, 16)
A = {lado: PZ.avalia(perfil, t, lado) for lado in ('esq', 'dir')}
FIS = PZ.fisica(t)
OFF = np.array([sat['offset']['dx'], sat['offset']['dz']]) if sat['offset'].get('aplicado') else np.zeros(2)

SETORES = [  # Fases 3–10
    (3, 'Reta dos boxes + freada do S', [(3884, 4294), (0, 250)]),
    (4, 'S do Senna + Curva do Sol', [(250, 776)]),
    (5, 'Reta Oposta', [(776, 1362)]),
    (6, 'Descida do Lago + subida', [(1362, 1976)]),
    (7, 'Ferradura + Laranjinha', [(1976, 2278)]),
    (8, 'Esse + Pinheirinho + Bico de Pato', [(2278, 2868)]),
    (9, 'Mergulho + Junção + Café', [(2868, 3578)]),
    (10, 'Subida dos Boxes + arquibancadas', [(3578, 3884)]),
]


def setor(s):
    for nfase, _, faixas in SETORES:
        if any(a <= s % L < b for a, b in faixas):
            return nfase
    return 3


# ------------------------------------------------------------------------------------------------ geometria
def interp(s, cols):
    u = (np.asarray(s, float) % L) / 2.0
    i0 = np.floor(u).astype(int) % n
    i1 = (i0 + 1) % n
    f = (u - np.floor(u))[..., None]
    return S[i0][:, cols] * (1 - f) + S[i1][:, cols] * f


meta = json.load(open(os.path.join(RAW, 'sat19.json')))
MOS = np.load(os.path.join(RAW, 'sat19.npy'))
LAT0, LON0 = meta['lat0'], meta['lon0']
ML = 111320.0
MO = ML * math.cos(math.radians(LAT0))
NT = 2 ** meta['z']


def pix(x, z):
    lat = LAT0 - np.asarray(z) / ML
    lon = LON0 + np.asarray(x) / MO
    tx = (lon + 180.0) / 360.0 * NT
    lr = np.radians(lat)
    ty = (1.0 - np.log(np.tan(lr) + 1.0 / np.cos(lr)) / math.pi) / 2.0 * NT
    return (ty - meta['ty0']) * 256.0 - 0.5, (tx - meta['tx0']) * 256.0 - 0.5


PXM = 4            # px por metro (s e d)
DMAX = 30.0        # d em [-DMAX, DMAX)
s4 = np.arange(0.0, L, 1.0 / PXM)
P4 = interp(s4, [0, 2])
R4 = interp(s4, [6, 7])
R4 /= np.linalg.norm(R4, axis=1)[:, None]
dd = np.arange(-DMAX, DMAX, 1.0 / PXM)


def desenrola(a, b):
    """satélite desenrolado de s=a a s=b (m): linhas = d de -DMAX (esq) a +DMAX (dir), colunas = s."""
    k0, k1 = a * PXM, b * PXM
    x = P4[k0:k1, 0, None] + R4[k0:k1, 0, None] * dd[None] + OFF[0]
    z = P4[k0:k1, 1, None] + R4[k0:k1, 1, None] * dd[None] + OFF[1]
    r, c = pix(x.ravel(), z.ravel())
    img = np.stack([map_coordinates(MOS[..., ch].astype(np.float32), [r, c], order=1, mode='constant') for ch in range(3)], -1)
    return img.reshape(k1 - k0, len(dd), 3).transpose(1, 0, 2).clip(0, 255).astype(np.uint8)


COR_ESC = {'verde': (140, 255, 140), 'agua': (80, 230, 230), 'vermelho': (255, 70, 70)}
COR_BAR = {'rail': (255, 255, 255), 'wall': (255, 0, 255), 'rolex_pad': (255, 0, 255), 'tecpro': (60, 120, 255), 'tecpro2': (60, 120, 255)}


def camadas(lado, i):
    """distâncias da linha central (m, positivas para fora) de cada camada do perfil na amostra i."""
    a = A[lado][i]
    w = a['w']
    z0 = w
    z1 = w + a['zebra']
    v1 = z1 + a['verde']
    s1 = v1 + a['salsicha']
    e0 = w + min(a['zebra'] + a['verde'] + a['salsicha'], a['kerb'])
    e1 = w + a['kerb'] + a['run']
    return dict(w=w, z=(z0, z1), v=(z1, v1), sal=(v1, s1), esc=(e0, e1) if a['run'] > 0 else None, cor=a['cor'],
                wall=a['wall'], tipo=a['tipo'])


def sat_zebra_metros(lado):
    m = np.zeros(int(L), bool)
    for z in sat['zebras']:
        if z['lado'] == lado:
            m[z['s0']:z['s1'] + 1] = True
    return m


SATZ = {lado: sat_zebra_metros(lado) for lado in ('esq', 'dir')}


def faixa(a, b):
    img = Image.fromarray(desenrola(a, b))
    over = Image.new('RGBA', img.size, (0, 0, 0, 0))
    dr = ImageDraw.Draw(over)
    H = img.size[1]
    y = lambda dist: (dist + DMAX) * PXM
    for j in range(a, b):
        x = (j - a) * PXM
        i = int(j // 2) % n
        for lado, sg in (('esq', -1), ('dir', 1)):
            c = camadas(lado, i)
            band = lambda d0, d1, cor: dr.rectangle([x, min(y(sg * d0), y(sg * d1)), x + PXM - 1, max(y(sg * d0), y(sg * d1))], fill=cor)
            if c['z'][1] > c['z'][0]:
                band(*c['z'], (255, 220, 0, 150))
            if c['v'][1] > c['v'][0]:
                band(*c['v'], (0, 200, 60, 170))
            if c['sal'][1] > c['sal'][0]:
                band(*c['sal'], (255, 140, 0, 220))
            if c['esc']:
                for dist in c['esc']:
                    dr.line([(x, y(sg * dist)), (x + PXM - 1, y(sg * dist))], fill=COR_ESC[c['cor']] + (255,))
            dr.line([(x, y(sg * c['w'])), (x + PXM - 1, y(sg * c['w']))], fill=(0, 255, 255, 255))
            if abs(c['wall']) < DMAX:
                dr.line([(x, y(sg * c['wall'])), (x + PXM - 1, y(sg * c['wall']))], fill=COR_BAR.get(c['tipo'], (255, 255, 255)) + (255,), width=2)
            # barras de comparação: satélite (vermelho) × perfil (amarelo)
            yb = (0, 4) if lado == 'esq' else (H - 9, H - 5)
            if SATZ[lado][j % int(L)]:
                dr.rectangle([x, yb[0], x + PXM - 1, yb[0] + 3], fill=(255, 30, 30, 255))
            if c['z'][1] > c['z'][0]:
                dr.rectangle([x, yb[1], x + PXM - 1, yb[1] + 3], fill=(255, 230, 0, 255))
        if j % 10 == 0:
            dr.line([(x, 9), (x, 15)], fill=(255, 0, 255, 255))
            if j % 50 == 0:
                dr.text((x + 2, 9), str(j), fill=(255, 0, 255, 255))
    return Image.alpha_composite(img.convert('RGBA'), over).convert('RGB')


# ------------------------------------------------------------------------------------------------ vista de cima
def ponto(i, dist):
    """pixel (col, lin) no mosaico da amostra i (2 m) deslocada `dist` m na lateral (+ = direita)."""
    p = S[i, [0, 2]]
    r = S[i, [6, 7]] / np.linalg.norm(S[i, [6, 7]])
    q = p + r * dist + OFF
    rr, cc = pix(q[0], q[1])
    return float(cc), float(rr)


def desenha_cima(dr, esc, i0, i1, larg=1):
    """polilinhas das camadas do perfil entre as amostras i0..i1 (escala esc: px do desenho / px do mosaico)."""
    P = lambda i, dist: tuple(v * esc for v in ponto(i % n, dist))
    for lado, sg in (('esq', -1), ('dir', 1)):
        for i in range(i0, i1):
            c, c2 = camadas(lado, i % n), camadas(lado, (i + 1) % n)
            seg = lambda d0, d1, cor, w_=larg: dr.line([P(i, sg * d0), P(i + 1, sg * d1)], fill=cor, width=w_)
            seg(c['w'], c2['w'], (0, 255, 255))
            if c['z'][1] > c['z'][0] and c2['z'][1] > c2['z'][0]:
                seg(c['z'][1], c2['z'][1], (255, 220, 0), larg + 2)
            if c['v'][1] > c['v'][0] and c2['v'][1] > c2['v'][0]:
                seg(c['v'][1], c2['v'][1], (0, 200, 60), larg + 1)
            if c['sal'][1] > c['sal'][0] and c2['sal'][1] > c2['sal'][0]:
                seg(c['sal'][1], c2['sal'][1], (255, 140, 0), larg + 1)
            if c['esc'] and c2['esc']:
                seg(c['esc'][1], c2['esc'][1], COR_ESC[c['cor']])
            seg(c['wall'], c2['wall'], COR_BAR.get(c['tipo'], (255, 255, 255)), larg + 1)
            if SATZ[lado][(2 * i) % int(L)]:
                dr.line([P(i, sg * (c['w'] + 3.5)), P(i + 1, sg * (c2['w'] + 3.5))], fill=(255, 30, 30), width=larg + 1)
        if i0 % 50 == 0:
            pass
    for i in range(i0, i1):
        if (2 * i) % 100 == 0:
            x, y_ = P(i, 0)
            dr.text((x + 3, y_ + 3), str(2 * i), fill=(255, 0, 255))


def cima_volta():
    esc = 0.25
    img = Image.fromarray(MOS).resize((int(MOS.shape[1] * esc), int(MOS.shape[0] * esc)), Image.LANCZOS)
    dr = ImageDraw.Draw(img)
    desenha_cima(dr, esc, 0, n, 1)
    img.save(os.path.join(OUT, 'cima_volta.jpg'), quality=88)


def cima_setor(nfase, faixas):
    for k, (a, b) in enumerate(faixas):
        i0, i1 = a // 2, b // 2
        pts = np.array([ponto(i % n, sg * 30) for i in range(i0, i1 + 1) for sg in (-1, 1)])
        c0, r0 = np.maximum(pts.min(0) - 20, 0).astype(int)
        c1, r1 = np.minimum(pts.max(0) + 20, [MOS.shape[1], MOS.shape[0]]).astype(int)
        img = Image.fromarray(MOS[r0:r1, c0:c1].copy())
        dr = ImageDraw.Draw(img)
        P = ponto

        class D:  # desloca o desenho para o recorte
            @staticmethod
            def line(xy, **kw):
                dr.line([(x - c0, y_ - r0) for x, y_ in xy], **kw)

            @staticmethod
            def text(xy, s, **kw):
                dr.text((xy[0] - c0, xy[1] - r0), s, **kw)

        desenha_cima(D, 1.0, i0, i1, 1)
        img.save(os.path.join(OUT, f'cima_setor{nfase}{"" if len(faixas) == 1 else "_" + "ab"[k]}.jpg'), quality=88)


# ------------------------------------------------------------------------------------------------ tabela
def seg_perfil(lado):
    return [(a * 2, b * 2) for a, b in PZ.segmentos(A[lado], lambda x: x['zebra'] > 0)]


def esc_medido(cod):
    """largura (m da borda) do asfalto/pintura contínuo logo depois da borda, pelo código do satélite ('a5p8g40')."""
    import re
    fim = 0.0
    for letra, dist in re.findall(r'([a-z])([\d.]+)', cod or ''):
        if letra in 'ap' or (letra == 'o' and float(dist) - fim <= 1.5):
            fim = float(dist)
        else:
            break
    return fim


def runs(mask):
    r, cur = [], None
    for i, m in enumerate(mask):
        if m and cur is None:
            cur = i
        if not m and cur is not None:
            r.append((cur, i - 1))
            cur = None
    if cur is not None:
        r.append((cur, len(mask) - 1))
    return r


def tabela():
    L_ = []
    w = L_.append
    w('# Fase 2 — perfil lateral × satélite (gerado por tools/tracks/interlagos/overlay_perfil.py)\n')
    w('Perfil: `data/track/visual_profile.json` (final). Satélite: `tools/tracks/interlagos/interlagos-perfil-sat.json`. '
      'Decisões: `tools/tracks/interlagos/perfil_zebras.py`. Imagens: `build/interlagos/overlay_perfil/`.\n')
    w('Erro = |perfil − satélite| no início e no fim (m). O perfil é amostrado a cada 2 m, então o melhor possível é ±1 m.\n')
    # ---- zebras
    w('## 1. Zebras (listradas), zebra a zebra\n')
    w('| lado | setor | satélite s0–s1 | perfil s0–s1 | erro início / fim | classe | fonte | nota |')
    w('|:--|:--:|:--|:--|:--|:--|:--|:--|')
    perf = {l: seg_perfil(l) for l in ('esq', 'dir')}
    dentro = fora = 0
    usados = {l: set() for l in perf}
    for z in sorted(PZ.ZEBRAS, key=lambda z: (z['lado'], z['s0'])):
        ps = [(a, b) for a, b in perf[z['lado']] if a <= z['s1'] + 2 and b >= z['s0'] - 2]
        for x in ps:
            usados[z['lado']].add(x)
        pa, pb = (ps[0][0], ps[-1][1]) if ps else (None, None)
        if z['sat']:
            sa, sb = z['sat'][0][0], z['sat'][-1][1]
            e0, e1 = abs(pa - sa), abs(pb - sb)
            ok = e0 <= 3 and e1 <= 3
            dentro += ok
            fora += not ok
            err = f'{e0:.0f} / {e1:.0f}' + ('' if ok else ' **> 3**')
            stxt = f'{sa}–{sb}' + (f' ({len(z["sat"])} segmentos)' if len(z['sat']) > 1 else '')
        else:
            err, stxt = '—', '— (sem zebra no satélite)'
            fora += 1
        w(f'| {z["lado"]} | {setor(z["s0"])} | {stxt} | {pa}–{pb} | {err} | {z["classe"]} | {z["fonte"]} | {z["nota"]} |')
    for l in perf:
        for a, b in perf[l]:
            if (a, b) not in usados[l]:
                w(f'| {l} | {setor(a)} | ? | {a}–{b} | ? | ? | **sem decisão** | zebra do perfil fora da tabela de decisões |')
    w('')
    w(f'Com satélite e dentro de ≤ 3 m nas duas pontas: **{dentro}**; fora (pelo vídeo ou sem satélite): **{fora}** '
      '(justificativas na nota).\n')
    w('### Segmentos do satélite não aplicados\n')
    w('| lado | setor | satélite s0–s1 | larg. sat. | conf | motivo |')
    w('|:--|:--:|:--|:--|:--:|:--|')
    satz = {(z['lado'], z['s0'], z['s1']): z for z in sat['zebras']}
    for l, a, b, motivo in PZ.NAO_APLICADAS:
        z = satz.get((l, a, b), {})
        w(f'| {l} | {setor(a)} | {a}–{b} | {z.get("larg", "?")} | {z.get("conf", "?")} | {motivo} |')
    usados_sat = {(z['lado'], a, b) for z in PZ.ZEBRAS for a, b in z['sat']} | {(l, a, b) for l, a, b, _ in PZ.NAO_APLICADAS}
    falt = [z for z in sat['zebras'] if (z['lado'], z['s0'], z['s1']) not in usados_sat]
    if falt:
        w('\n**Segmentos do satélite sem decisão:** ' + ', '.join(f'{z["lado"]} {z["s0"]}–{z["s1"]}' for z in falt))
    w('')
    # ---- visual × física
    w('## 2. Zebra visual × física (`track.json`, kerbL/kerbR) — para a Fase 2B\n')
    w('| lado | setor | s0–s1 | situação |')
    w('|:--|:--:|:--|:--|')
    for l in ('esq', 'dir'):
        vis = [a['zebra'] > 0 for a in A[l]]
        fis = [k > 0 for k in FIS[l]['k']]
        for a, b in runs([v and not f for v, f in zip(vis, fis)]):
            w(f'| {l} | {setor(2 * a)} | {2 * a}–{2 * b} | zebra só no visual (física sem zebra) |')
        for a, b in runs([f and not v for v, f in zip(vis, fis)]):
            w(f'| {l} | {setor(2 * a)} | {2 * a}–{2 * b} | física com zebra, visual sem (escondida: `listrada: false`) |')
    w('')
    # ---- picos
    w('## 3. Picos de muro/escape corrigidos\n')
    w('| lado | s0–s1 | muro | escape | antes |')
    w('|:--|:--|:--:|:--:|:--|')
    for l, a, b, m, e, mot in PZ.PICOS:
        w(f'| {l} | {a}–{b} | {"sim" if m else "—"} | {"sim" if e else "—"} | {mot} |')
    w('\nPedidos conferidos e mantidos (não são pico):\n')
    for l, a, b, mot in PZ.PICOS_NAO:
        w(f'- {l} {a}–{b}: {mot}')
    w('')
    # ---- por setor: o que não foi aplicado
    w('## 4. Diferenças não aplicadas, por setor (insumo das Fases 3–10)\n')
    w('Medidas laterais absolutas do satélite **não** entraram (a linha central tem erro local de 2–5 m; Fase 2B). '
      'Muro do satélite não é confiável: só candidatos. Distâncias contadas da borda do asfalto.\n')
    sd = {l: sat[l] for l in ('esq', 'dir')}
    for nfase, nome, faixas in SETORES:
        w(f'### Setor {nfase} (Fase {nfase}) — {nome}: s {", ".join(f"{a}–{b}" for a, b in faixas)}\n')
        dentro_set = lambda s: setor(s) == nfase
        # pinturas do satélite × perfil
        linhas = []
        for p in sat['pinturas']:
            if not dentro_set(p['s0']):
                continue
            i = (p['s0'] + p['s1']) // 4 % n if p['s1'] >= p['s0'] else p['s0'] // 2
            a = A[p['lado']][i]
            temos = []
            if a['verde'] > 0:
                temos.append(f'faixa verde {a["verde"]:.2f}')
            if a['run'] > 0:
                temos.append(f'escape {a["cor"]} {a["run"]:.1f} m')
            linhas.append(f'| {p["lado"]} | {p["s0"]}–{p["s1"]} | {p["cor"]} {p["larg"]} m (conf {p["conf"]}) | {", ".join(temos) or "nada"} |')
        if linhas:
            w('Pinturas medidas no satélite × perfil:\n')
            w('| lado | s | satélite | perfil (no meio do trecho) |')
            w('|:--|:--|:--|:--|')
            L_.extend(linhas)
            w('')
        # escape asfaltado/pintado medido × perfil (trechos ≥ 20 m com diferença > 2 m, conf ≥ 1)
        linhas = []
        for l in ('esq', 'dir'):
            med = np.array([esc_medido(c) for c in sd[l]['esc']])
            conf = np.array([int(c) for c in sd[l]['conf']])
            per = np.array([A[l][min(j // 2, n - 1)]['kerb'] + A[l][min(j // 2, n - 1)]['run'] for j in range(int(L))])
            difm = (np.abs(med - per) > 2) & (conf >= 1)
            for a, b in runs(list(difm)):
                if b - a + 1 >= 20 and dentro_set(a):
                    linhas.append(f'| {l} | {a}–{b} | {np.median(med[a:b + 1]):.1f} | {np.median(per[a:b + 1]):.1f} |')
        if linhas:
            w('Escape asfaltado/pintado (zebra + escape, m da borda), trechos ≥ 20 m com diferença > 2 m:\n')
            w('| lado | s | satélite (mediana) | perfil (mediana) |')
            w('|:--|:--|:--:|:--:|')
            L_.extend(linhas)
            w('')
        # candidatos de muro
        linhas = []
        for l in ('esq', 'dir'):
            mu = np.array([np.nan if v is None else v for v in sd[l]['muro']], float)
            per = np.array([A[l][min(j // 2, n - 1)]['wall'] - A[l][min(j // 2, n - 1)]['w'] for j in range(int(L))])
            difm = ~np.isnan(mu) & (np.abs(mu - per) > 3)
            for a, b in runs(list(difm)):
                if b - a + 1 >= 15 and dentro_set(a):
                    linhas.append(f'| {l} | {a}–{b} | {np.nanmedian(mu[a:b + 1]):.1f} | {np.median(per[a:b + 1]):.1f} |')
        if linhas:
            w('Candidatos de muro (satélite × perfil, > 3 m em ≥ 15 m; **não confiável**, conferir no vídeo):\n')
            w('| lado | s | muro satélite (m da borda) | muro perfil |')
            w('|:--|:--|:--:|:--:|')
            L_.extend(linhas)
            w('')
        # âncoras
        anc = [x for x in sat['ancoras'] if dentro_set(x.get('s', x.get('s0', 0)))]
        if anc:
            w('Âncoras (satélite × cenário atual; não movidas nesta fase):\n')
            for x in anc:
                ss = x.get('s', f'{x.get("s0")}–{x.get("s1")}')
                w(f'- {x["nome"]}: satélite s {ss}, cenário s {x.get("sCenario")} (conf {x.get("conf")})' + (f' — {x["obs"]}' if x.get('obs') else ''))
            w('')
        # zebras não aplicadas no setor
        na = [x for x in PZ.NAO_APLICADAS if dentro_set(x[1])]
        if na:
            w('Zebras do satélite não aplicadas: ' + '; '.join(f'{l} {a}–{b} ({m})' for l, a, b, m in na) + '\n')
    open(MD, 'w', encoding='utf-8').write('\n'.join(L_) + '\n')
    return dentro, fora


if __name__ == '__main__':
    so_tabela = '--so-tabela' in sys.argv
    d, f = tabela()
    print(f'diferencas.md: zebras dentro de 3 m: {d}, fora/sem satélite: {f} → {MD}')
    if so_tabela:
        sys.exit(0)
    for a in range(0, int(L), 400):
        faixa(a, min(a + 400, int(L))).save(os.path.join(OUT, f'faixa_{a:04d}.png'))
    print('faixas ok')
    cima_volta()
    for nfase, _, faixas in SETORES:
        cima_setor(nfase, faixas)
    print('vista de cima ok →', OUT)
