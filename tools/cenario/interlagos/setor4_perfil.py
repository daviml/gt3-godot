# Fase 4 (PLANO-INTERLAGOS-DETALHES.md) — S do Senna + Curva do Sol: reescreve as fatias do perfil lateral
# (data/track/visual_profile.json) entre s 250 e 783 (s novo), a partir da ficha build/ref/interlagos/fichas/setor-4.md.
# Fora do setor o arquivo não muda (as fatias que cruzam 250/784 são cortadas nesses pontos, com os mesmos valores).
# Idempotente: dá para rodar de novo depois de mudar a física (larguras limitadas pelo muro da física atual).
#
# uso (de REPOS/gt3-godot): python tools/cenario/interlagos/setor4_perfil.py
#
# Decisões (vídeo = quadros chase_v2 do atlas; satélite = Esri z19 desenrolado, build/interlagos/fase4/):
#   esq 250–326  escape verde-água até o muro (LMU s 250–300: faixa verde-azulada até o muro ROLEX)
#   esq 328–360  ápice de dentro do S: escape verde 6 m (satélite: pintura verde 6,2 m; LMU s 330/350)
#   esq 362–466  sem escape: zebra e grama seca (LMU s 380/400/430)
#   esq 468–548  escape verde 8 m (satélite: verde 8,1 m; LMU s 480/500/530)
#   esq 550–556  como estava (fim da mancha verde; LMU s 550)
#   esq 558–783  zebra + faixa verde-água de 0,5 m + grama (LMU s 580–780; era verde vivo + 0,2 m de pintura)
#   dir 250–518  escape verde-água até o muro (LMU s 250–450: escape largo verde-azulado até o muro)
#   dir 520–552  sem escape (LMU s 530/550: grama até o guard-rail)
#   dir 700–740  escape verde até o muro (LMU s 700/730; satélite: pintura de 12,5 m)
#   dir 742–783  saída da Curva do Sol: zebra + escape vermelho + faixa verde de 2,5 m junto do muro (LMU s 750/780;
#                satélite: pintura até borda + ~10 m e faixa escura de ~3 m até o muro)
# Larguras de escape sempre cortadas a 0,3 m do muro da física.
import json
import os

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
PERFIL = os.path.join(ROOT, 'data', 'track', 'visual_profile.json')
S0, S1 = 250, 782  # amostras do setor (inclusive); a fatia seguinte começa em 784

T = json.load(open(os.path.join(ROOT, 'data', 'track', 'track.json'), encoding='utf-8'))
A = np.array(T['s'], float).reshape(T['n'], T['stride'])
W = {'esq': A[:, 8], 'dir': A[:, 9]}
K = {'esq': A[:, 10], 'dir': A[:, 11]}
M = {'esq': A[:, 14], 'dir': A[:, 15]}

p = json.load(open(PERFIL, encoding='utf-8'))
passo = p['passo']


def valor(v, k):
    return v[k] if isinstance(v, list) else v


def expandir(fatias):
    """uma entrada por amostra: (faixas com valores escalares, barreira)"""
    out = {}
    for f in fatias:
        i0, i1 = round(f['s0'] / passo), round(f['s1'] / passo)
        for i in range(i0, i1 + 1):
            k = i - i0
            fx = []
            for x in f['faixas']:
                x = dict(x)
                if 'larg' in x:
                    x['larg'] = valor(x['larg'], k)
                fx.append(x)
            b = dict(f['barreira'])
            if isinstance(b.get('dist'), list):
                b['dist'] = b['dist'][k]
            out[i] = (fx, b)
    return out


def cortar(f, s0, s1):
    """pedaço [s0, s1] de uma fatia, com as listas por amostra cortadas"""
    i0 = round(f['s0'] / passo)
    a, b = round(s0 / passo) - i0, round(s1 / passo) - i0
    g = json.loads(json.dumps(f))
    g['s0'], g['s1'] = s0, s1
    for x in g['faixas']:
        if isinstance(x.get('larg'), list):
            x['larg'] = x['larg'][a:b + 1]
    if isinstance(g['barreira'].get('dist'), list):
        g['barreira']['dist'] = g['barreira']['dist'][a:b + 1]
    return g


def folga(lado, i, sem_zebra=False):
    """espaço da borda da zebra física até 0,3 m antes do muro da física"""
    return max(0.0, M[lado][i] - W[lado][i] - (0 if sem_zebra else K[lado][i]) - 0.3)


def zebra(fx):
    return [x for x in fx if x['tipo'] == 'zebra']


def escape(lado, i, fx, cor, larg, fora=None):
    z = zebra(fx)
    g = folga(lado, i, not z)
    out = z + [{'tipo': 'escape', 'cor': cor, 'larg': round(min(larg, g), 3)}]
    if fora:
        cor2, l2 = fora
        l2 = min(l2, g)
        out[-1]['larg'] = round(max(0.0, min(larg, g - l2)), 3)
        out[-1]['fora'] = {'cor': cor2, 'larg': round(l2, 3)}
    return out


def regra(lado, s, i, fx):
    if lado == 'esq':
        if s <= 326:
            return escape(lado, i, fx, 'agua', 30.0)
        if s <= 360:
            return escape(lado, i, fx, 'verde', 6.0)
        if s <= 466:
            return zebra(fx)
        if s <= 548:
            return escape(lado, i, fx, 'verde', 8.0)
        if s <= 556:
            return fx
        return zebra(fx) + [{'tipo': 'escape', 'cor': 'agua', 'larg': round(min(0.5, folga(lado, i)), 3)}]
    if s <= 518:
        return escape(lado, i, fx, 'agua', 30.0)
    if s <= 552:
        return [x for x in fx if x['tipo'] != 'escape']
    if s <= 698:
        return fx
    if s <= 740:
        return escape(lado, i, fx, 'verde', 30.0)
    return escape(lado, i, fx, 'vermelho', 30.0, ('verde', 2.5))


def chave(fx, b):
    """estrutura da fatia sem os números que variam por amostra"""
    def sem(x):
        x = dict(x)
        if 'larg' in x and not isinstance(x['larg'], str):
            x['larg'] = '#'
        if 'fora' in x:
            x['fora'] = dict(x['fora'], larg='#')
        return x
    return json.dumps([[sem(x) for x in fx], b], sort_keys=True)


def comprimir(amostras):
    """lista [(i, faixas, barreira)] → fatias (números constantes viram escalar, os outros lista por amostra)"""
    fatias = []
    grupo = []
    for item in amostras + [None]:
        if grupo and (item is None or chave(item[1], item[2]) != chave(grupo[-1][1], grupo[-1][2])):
            fx0, b0 = grupo[0][1], grupo[0][2]
            faixas = []
            for j, x in enumerate(fx0):
                x = dict(x)
                for campo in ('larg',):
                    if campo in x and not isinstance(x[campo], str):
                        vs = [g[1][j][campo] for g in grupo]
                        x[campo] = vs[0] if all(v == vs[0] for v in vs) else vs
                if 'fora' in x:
                    vs = [g[1][j]['fora']['larg'] for g in grupo]
                    x['fora'] = dict(x['fora'], larg=vs[0] if all(v == vs[0] for v in vs) else vs)
                faixas.append(x)
            fatias.append({'s0': grupo[0][0] * passo, 's1': grupo[-1][0] * passo, 'faixas': faixas, 'barreira': b0})
            grupo = []
        if item is not None:
            grupo.append(item)
    return fatias


for lado in ('esq', 'dir'):
    fatias = p['lados'][lado]
    exp = expandir(fatias)
    antes, depois = [], []
    for f in fatias:
        if f['s1'] < S0:
            antes.append(f)
        elif f['s0'] > S1:
            depois.append(f)
        else:
            if f['s0'] < S0:
                antes.append(cortar(f, f['s0'], S0 - passo))
            if f['s1'] > S1:
                depois.append(cortar(f, S1 + passo, f['s1']))
    meio = []
    for i in range(S0 // passo, S1 // passo + 1):
        fx, b = exp[i]
        meio.append((i, regra(lado, i * passo, i, fx), b))
    novas = comprimir(meio)
    p['lados'][lado] = antes + novas + depois
    print(f'{lado}: {len(novas)} fatias no setor 4')

# Árvores, Etapa A (§5): zonas por s e lado, d = metros além do muro da física. Fontes: altura de copa do LiDAR
# (lidar.copa > 4 m, fração por faixa de d; tabela no setor-4.md) e o vídeo (LMU chase_v2). dens = fração que fica.
ZONAS4 = [
    ('esq', 250, 330, 0, 40, 0.0, 'arquibancada/estruturas atrás do muro ROLEX (LMU s 250–300); copa = estruturas'),
    ('esq', 330, 460, 0, 30, 0.0, 'saída dos boxes, tendas e contêineres (LMU s 350–430)'),
    ('esq', 330, 460, 30, 200, 0.8, 'mata atrás das tendas (copa 0,4–0,8 a 20–70 m)'),
    ('esq', 460, 784, 0, 70, 0.0, 'pista dos boxes e campo aberto (LMU s 480–780; copa ≈ 0)'),
    ('esq', 460, 784, 70, 200, 0.35, 'árvores esparsas (copa 0,1–0,2)'),
    ('dir', 300, 400, 0, 40, 0.0, 'escape largo e grama (copa ≈ 0,05; LMU s 300–380)'),
    ('dir', 400, 700, 0, 100, 0.0, 'muro de arrimo, estacionamento e talude (LMU s 450–680; copa 0 até 70 m)'),
    ('dir', 400, 700, 100, 200, 0.7, 'mata ao fundo (copa 0,4–0,6 a 110–160 m)'),
    ('dir', 700, 784, 0, 40, 0.0, 'talude gramado com carros atrás do muro MOTUL (LMU s 700–780)'),
]
p['arvores'] = {
    'setores': [{'s0': 250, 's1': 783}],
    'espacamento': 5.0,
    'escala': [0.8, 1.25],
    'base': 2.6,
    'zonas': [{'lado': l, 's0': a, 's1': b, 'd0': d0, 'd1': d1, 'dens': de, 'fonte': f} for l, a, b, d0, d1, de, f in ZONAS4],
}

txt = json.dumps(p, indent=1, ensure_ascii=False)
# listas de números numa linha só (como o migrarPerfil2B.ts)
import re  # noqa: E402
txt = re.sub(r'\[\s+([-0-9.,\s]+?)\s+\]', lambda m: '[' + re.sub(r'\s+', '', m.group(1)) + ']', txt)
open(PERFIL, 'w', encoding='utf-8', newline='\n').write(txt + '\n')
print('gravado', PERFIL)
