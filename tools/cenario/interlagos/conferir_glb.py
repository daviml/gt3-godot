# Fase 2B, etapa F: confere em números o cenário de Interlagos (assets/track/cenario.glb + arvores_pos.json +
# props.json) contra a física (data/track/track.json, com o camber `bank` aplicado como no track.gd/bank.ts).
#
#   1. asfalto do GLB × bordas da física (posição lateral de cada vértice no plano inclinado da pista)
#   2. zebras do GLB (pinta:zebra) × zebras da física (kerbL/kerbR > 0), amostra a amostra, e a largura visual
#   3. barreiras do GLB (guard-rail, muro, cabeceira, barreiras acolchoadas, separador da saída dos boxes, Goodyear do
#      Lago, muro da Ferradura: identificadas pelo material) × muro da física: nenhuma barreira entre a borda e o muro
#      da física (o carro a atravessaria) e nenhuma amostra sem barreira no muro da física (muro invisível)
#   4. árvores e props fora do asfalto (e onde ficam em relação ao muro)
#
# uso (de REPOS/gt3-godot): python tools/cenario/interlagos/conferir_glb.py [--glb=<cenario.glb>] [--dados=<pasta com
#   arvores_pos.json e props.json>] [--json=<saída>]
import json
import os
import struct
import sys

import numpy as np
from scipy.spatial import cKDTree

sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
arg = {a.split('=', 1)[0]: a.split('=', 1)[1] for a in sys.argv[1:] if '=' in a}
GLB = arg.get('--glb', os.path.join(ROOT, 'assets', 'track', 'cenario.glb'))
DADOS = arg.get('--dados', os.path.join(ROOT, 'data', 'track'))

# ---------------------------------------------------------------- física
T = json.load(open(os.path.join(ROOT, 'data', 'track', 'track.json'), encoding='utf-8'))
N, st = T['n'], T['stride']
A = np.array(T['s'], float).reshape(N, st)
P = A[:, 0:3]
TT = A[:, 3:6] / np.linalg.norm(A[:, 3:6], axis=1)[:, None]
R0 = np.c_[A[:, 6], np.zeros(N), A[:, 7]]
R0 /= np.linalg.norm(R0, axis=1)[:, None]
N0 = np.cross(R0, TT)
N0 /= np.linalg.norm(N0, axis=1)[:, None]
th = np.array(T.get('bank', np.zeros(N)), float)
R = R0 * np.cos(th)[:, None] + N0 * np.sin(th)[:, None]
R /= np.linalg.norm(R, axis=1)[:, None]
NN = np.cross(R, TT)
NN /= np.linalg.norm(NN, axis=1)[:, None]
WL, WR, KL, KR, RL, RR, ML, MR = (A[:, k] for k in range(8, 16))
arvore = cKDTree(P[:, [0, 2]])


def localiza(V):
    """(índice da amostra, u no segmento, d lateral no plano inclinado, h acima da pista, ao longo) por vértice"""
    _, i0 = arvore.query(V[:, [0, 2]])
    # segmento i0-1→i0 ou i0→i0+1, como o Track.locate
    rel = V - P[i0]
    i = np.where((rel[:, [0, 2]] * TT[i0][:, [0, 2]]).sum(1) < 0, (i0 - 1) % N, i0)
    j = (i + 1) % N
    seg = P[j] - P[i]
    u = np.clip(((V - P[i])[:, [0, 2]] * seg[:, [0, 2]]).sum(1) / (seg[:, [0, 2]] ** 2).sum(1), 0, 1)
    c = P[i] + seg * u[:, None]
    r = R[i] * (1 - u)[:, None] + R[j] * u[:, None]
    r /= np.linalg.norm(r, axis=1)[:, None]
    n = NN[i] * (1 - u)[:, None] + NN[j] * u[:, None]
    n /= np.linalg.norm(n, axis=1)[:, None]
    d = ((V - c) * r).sum(1)
    h = ((V - c) * n).sum(1)
    return i, u, d, h


def lerp(a, i, u):
    return a[i] * (1 - u) + a[(i + 1) % N] * u


# ---------------------------------------------------------------- GLB
def le_glb(path):
    b = open(path, 'rb').read()
    _, _, _ = struct.unpack_from('<III', b, 0)
    off = 12
    js = bn = None
    while off < len(b):
        ln, tp = struct.unpack_from('<II', b, off)
        ch = b[off + 8:off + 8 + ln]
        if tp == 0x4E4F534A:
            js = json.loads(ch)
        elif tp == 0x004E4942:
            bn = ch
        off += 8 + ln
    return js, bn


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_mat(nd):
    if 'matrix' in nd:
        return np.array(nd['matrix'], float).reshape(4, 4).T
    M = np.eye(4)
    S = np.diag(nd.get('scale', [1, 1, 1]))
    M[:3, :3] = quat_mat(nd.get('rotation', [0, 0, 0, 1])) @ S
    M[:3, 3] = nd.get('translation', [0, 0, 0])
    return M


js, bn = le_glb(GLB)


def accessor(k):
    a = js['accessors'][k]
    bv = js['bufferViews'][a['bufferView']]
    comp = {5126: ('<f4', 4), 5125: ('<u4', 4), 5123: ('<u2', 2), 5121: ('<u1', 1)}[a['componentType']]
    nc = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', comp[1] * nc)
    raw = np.frombuffer(bn, np.uint8, count=stride * (a['count'] - 1) + comp[1] * nc, offset=o)
    if stride == comp[1] * nc:
        return np.frombuffer(raw.tobytes(), comp[0]).reshape(a['count'], nc)
    rows = np.lib.stride_tricks.as_strided(raw, (a['count'], comp[1] * nc), (stride, 1))
    return np.frombuffer(rows.copy().tobytes(), comp[0]).reshape(a['count'], nc)


mats = js['materials']


def cor(m):
    return [round(x, 3) for x in m.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])[:3]]


def tipo_barreira(mi):
    """material → tipo de barreira (None = não é barreira). Pelas cores lineares dos materiais do gerador."""
    m = mats[mi]
    nome = m.get('name', '')
    pr = m.get('pbrMetallicRoughness', {})
    c = cor(m)
    met, rou = pr.get('metallicFactor', 1), pr.get('roughnessFactor', 1)
    if nome == 'ph:concrete_wall_008':
        return 'muro'
    if c == [0.539, 0.565, 0.591] and abs(met - 0.3) < 1e-3:
        return 'guard-rail'
    if c == [0.539, 0.565, 0.591] and abs(met - 0.35) < 1e-3:
        return 'separador saída dos boxes'
    if c == [0.018, 0.095, 0.451]:
        return 'barreira azul (tampa)'
    if c == [0.003, 0.156, 0.048]:
        return 'barreira ROLEX (tampa)'
    if c == [0.012, 0.068, 0.319]:
        return 'Goodyear do Lago (tampa)'
    if c == [0.198, 0.209, 0.223] and abs(rou - 0.9) < 1e-3:
        return 'paredão da Ferradura'
    if c == [0.509, 0.503, 0.468]:
        return 'cabeceira do muro'
    return None


malhas = []  # (material, vértices no mundo)


def visita(ni, M):
    nd = js['nodes'][ni]
    W = M @ node_mat(nd)
    if 'mesh' in nd:
        for p in js['meshes'][nd['mesh']]['primitives']:
            V = accessor(p['attributes']['POSITION']).astype(float)
            V = (W[:3, :3] @ V.T).T + W[:3, 3]
            malhas.append((p.get('material', -1), V))
    for c in nd.get('children', []):
        visita(c, W)


for ni in js['scenes'][js.get('scene', 0)]['nodes']:
    visita(ni, np.eye(4))

out = {'glb': GLB}

# ---------------------------------------------------------------- 1. asfalto
asf = [V for m, V in malhas if mats[m].get('name') == 'asfalto' and len(V) == (N + 1) * 2]
if len(asf) != 1:
    raise SystemExit(f'malha de asfalto da pista não encontrada ({len(asf)})')
V = asf[0]
i, u, d, h = localiza(V)
w = np.where(d < 0, -lerp(WL, i, u), lerp(WR, i, u))
e = np.abs(d - w)
out['asfalto'] = {'vertices': int(len(V)), 'borda_max_cm': round(float(e.max() * 100), 2), 'borda_p99_cm': round(float(np.percentile(e, 99) * 100), 2),
                  'altura_max_cm': round(float(np.abs(h).max() * 100), 2)}
# centro: média das duas bordas da mesma amostra (vértices 2k, 2k+1)
c = (V[0::2] + V[1::2]) / 2
ic, uc, dc, hc = localiza(c)
dcentro = dc - (lerp(WR, ic, uc) - lerp(WL, ic, uc)) / 2
out['asfalto']['centro_max_cm'] = round(float(np.abs(dcentro).max() * 100), 2)
out['asfalto']['centro_altura_max_cm'] = round(float(np.abs(hc).max() * 100), 2)


# ---------------------------------------------------------------- 2. zebras
def kerb_visual(k):
    return np.where(k <= 0, 0.0, 1.0 + 0.6 * np.clip((k - 1.2) / 1.0, 0, 1))


Z = np.concatenate([V for m, V in malhas if mats[m].get('name') == 'pinta:zebra'])
i, u, d, h = localiza(Z)
jj = np.where(u < 0.5, i, (i + 1) % N)
larg = np.zeros((N, 2))
for lado, sel, W in ((0, d < 0, WL), (1, d > 0, WR)):
    fora = np.abs(d[sel]) - W[jj[sel]]
    np.maximum.at(larg[:, lado], jj[sel], fora)
vis = larg > 0.3
fis = np.c_[KL > 0, KR > 0]


def trechos(m):
    r, a = [], None
    for k in range(N + 1):
        on = k < N and m[k]
        if on and a is None:
            a = k
        if not on and a is not None:
            r.append([a * 2, (k - 1) * 2])
            a = None
    return r


kv = np.c_[kerb_visual(KL), kerb_visual(KR)]
zz = {}
for lado, nome in ((0, 'esq'), (1, 'dir')):
    so_v = vis[:, lado] & ~fis[:, lado]
    so_f = fis[:, lado] & ~vis[:, lado]
    ambos = vis[:, lado] & fis[:, lado]
    dl = np.abs(larg[ambos, lado] - kv[ambos, lado])
    zz[nome] = {'visual_m': int(vis[:, lado].sum() * 2), 'fisica_m': int(fis[:, lado].sum() * 2),
                'so_visual': trechos(so_v), 'so_fisica': trechos(so_f),
                'largura_visual_menos_esperada_max_cm': round(float(dl.max() * 100), 1) if len(dl) else None}
out['zebras'] = zz

# ---------------------------------------------------------------- 3. barreiras
bar = [(tipo_barreira(m), V) for m, V in malhas if tipo_barreira(m)]
tipos = {}
dentro = {}
perto = np.zeros((N, 2), bool)
for tp, V in bar:
    i, u, d, h = localiza(V)
    jj = np.where(u < 0.5, i, (i + 1) % N)
    lado = (d > 0).astype(int)
    wall = np.where(lado == 1, lerp(MR, i, u), lerp(ML, i, u))
    borda = np.where(lado == 1, lerp(WR, i, u), lerp(WL, i, u))
    ad = np.abs(d)
    # só o que está ao lado desta amostra (descarta vértice que cai sobre outro trecho da pista) e até 1,5 m de altura
    perto_pista = (ad < wall + 3) & (h > -1) & (h < 1.6)
    tipos[tp] = tipos.get(tp, 0) + int(len(V))
    # barreira entre a borda e o muro da física (o carro passaria através dela): > 10 cm para dentro do muro
    ruim = perto_pista & (ad > borda) & (ad < wall - 0.10)
    if ruim.any() and '--detalhe' in sys.argv:
        for k in np.nonzero(ruim)[0][:: max(1, int(ruim.sum() // 12))]:
            _, viz = arvore.query(V[k, [0, 2]], k=6)
            outra = [int(x) for x in viz if min(abs(int(x) - int(jj[k])), N - abs(int(x) - int(jj[k]))) > 20]
            print(f'  {tp}: s={jj[k] * 2} lado={"dir" if lado[k] else "esq"} |d|={ad[k]:.2f} borda={borda[k]:.2f} '
                  f'muro_fis={wall[k]:.2f} h={h[k]:.2f} outro_trecho_perto={[o * 2 for o in outra[:2]]}')
    if ruim.any():
        dd = dentro.setdefault(tp, {'vertices': 0, 'trechos': set(), 'max_m': 0.0})
        dd['vertices'] += int(ruim.sum())
        dd['max_m'] = max(dd['max_m'], float((wall - ad)[ruim].max()))
        for k, l in zip(jj[ruim], lado[ruim]):
            dd['trechos'].add((int(k), int(l)))
    # barreira no muro da física (± 0,8 m: por dentro de curva fechada, a 10–25 m do centro, a lateral medida pela
    # projeção no segmento — a mesma do Track.locate — difere até ~0,75 m da lateral de construção, r da amostra)
    ok = perto_pista & (np.abs(ad - wall) < 0.8)
    perto[jj[ok], lado[ok]] = True
for tp, dd in dentro.items():
    ks = sorted(dd['trechos'])
    lados = {}
    for k, l in ks:
        lados.setdefault('esq' if l == 0 else 'dir', []).append(k)
    dd['trechos'] = {l: trechos(np.isin(np.arange(N), v)) for l, v in lados.items()}
    dd['max_m'] = round(dd['max_m'], 2)
# um vizinho de folga (a faixa liga amostras vizinhas)
cob = perto | np.roll(perto, 1, 0) | np.roll(perto, -1, 0)
out['barreiras'] = {'vertices_por_tipo': tipos, 'dentro_do_limite_da_fisica': dentro,
                    'sem_barreira_no_muro_da_fisica': {'esq': trechos(~cob[:, 0]), 'dir': trechos(~cob[:, 1])},
                    'amostras_sem_barreira': {'esq': int((~cob[:, 0]).sum()), 'dir': int((~cob[:, 1]).sum())}}

# ---------------------------------------------------------------- 4. árvores e props
arv = np.array(json.load(open(os.path.join(DADOS, 'arvores_pos.json'))), float).reshape(-1, 7)
props = json.load(open(os.path.join(DADOS, 'props.json')))


def fora(Vx, nomes=None):
    i, u, d, h = localiza(Vx)
    jj = np.where(u < 0.5, i, (i + 1) % N)
    borda = np.where(d > 0, WR[jj], WL[jj])
    wall = np.where(d > 0, MR[jj], ML[jj])
    ad = np.abs(d)
    # vértice que "cai" sobre outro trecho: a distância horizontal real ao centro é o que vale
    no_asfalto = ad < borda
    r = {'n': int(len(Vx)), 'no_asfalto': int(no_asfalto.sum()), 'ate_1m_da_borda': int((ad < borda + 1).sum()),
         'dentro_do_muro': int((ad < wall).sum()), 'folga_min_da_borda_m': round(float((ad - borda).min()), 2)}
    if nomes is not None:
        r['dentro_do_muro_ids'] = sorted({nomes[k] for k in np.nonzero(ad < wall)[0]})
        r['no_asfalto_ids'] = sorted({nomes[k] for k in np.nonzero(no_asfalto)[0]})
    return r


out['arvores'] = fora(arv[:, :3])
out['props'] = fora(np.array([[p[1], p[2], p[3]] for p in props], float), [p[0] for p in props])
txt = json.dumps(out, ensure_ascii=False, indent=1)
print(txt)
if '--json' in arg:
    open(arg['--json'], 'w', encoding='utf-8').write(txt)
