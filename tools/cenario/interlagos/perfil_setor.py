# Ferramentas comuns dos scripts de perfil por setor (PLANO-INTERLAGOS-DETALHES.md, Fases 3–10):
# setor4_perfil.py, setor6_perfil.py, ... Cada script declara uma `regra(lado, s, i, fx)` (faixas novas de uma amostra a
# partir das faixas atuais) e as zonas de árvores do setor; `aplicar` reescreve SÓ as fatias de [S0, S1] do
# data/track/visual_profile.json (as fatias que cruzam as pontas são cortadas nelas com os mesmos valores) e
# `arvores` troca só o setor dele no bloco `arvores` (os outros setores ficam). Idempotente.
#
# Extraído do setor4_perfil.py da Fase 4 sem mudar o resultado (conferido: o setor4_perfil.py reescrito sobre o perfil
# da Fase 4 dá o mesmo arquivo byte a byte).
import json
import os
import re

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
PERFIL = os.path.join(ROOT, 'data', 'track', 'visual_profile.json')

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
                if 'grama' in x:  # (Fase 5) grama antes do escape
                    x['grama'] = valor(x['grama'], k)
                if 'fora' in x:
                    x['fora'] = dict(x['fora'], larg=valor(x['fora']['larg'], k))
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
        if isinstance(x.get('grama'), list):
            x['grama'] = x['grama'][a:b + 1]
        if 'fora' in x and isinstance(x['fora'].get('larg'), list):
            x['fora']['larg'] = x['fora']['larg'][a:b + 1]
    if isinstance(g['barreira'].get('dist'), list):
        g['barreira']['dist'] = g['barreira']['dist'][a:b + 1]
    return g


def folga(lado, i, sem_zebra=False):
    """espaço da borda da zebra física até 0,3 m antes do muro da física"""
    return max(0.0, M[lado][i] - W[lado][i] - (0 if sem_zebra else K[lado][i]) - 0.3)


def zebra(fx):
    return [x for x in fx if x['tipo'] == 'zebra']


def escape(lado, i, fx, cor, larg, fora=None):
    """zebra atual + escape `cor` de `larg` m (cortado a 0,3 m do muro da física); `fora` = (cor, larg) de uma faixa
    pintada depois do escape (Faixa escape.fora)"""
    z = zebra(fx)
    g = folga(lado, i, not z)
    out = z + [{'tipo': 'escape', 'cor': cor, 'larg': round(min(larg, g), 3)}]
    if fora:
        cor2, l2 = fora
        l2 = min(l2, g)
        out[-1]['larg'] = round(max(0.0, min(larg, g - l2)), 3)
        out[-1]['fora'] = {'cor': cor2, 'larg': round(l2, 3)}
    return out


def chave(fx, b):
    """estrutura da fatia sem os números que variam por amostra"""
    def sem(x):
        x = dict(x)
        if 'larg' in x and not isinstance(x['larg'], str):
            x['larg'] = '#'
        if 'grama' in x:
            x['grama'] = '#'
        if 'fora' in x:
            x['fora'] = dict(x['fora'], larg='#')
        return x
    b = dict(b)
    if 'dist' in b and not isinstance(b['dist'], str):
        b['dist'] = '#'
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
                for campo in ('larg', 'grama'):
                    if campo in x and not isinstance(x[campo], str):
                        vs = [g[1][j][campo] for g in grupo]
                        x[campo] = vs[0] if all(v == vs[0] for v in vs) else vs
                if 'fora' in x:
                    vs = [g[1][j]['fora']['larg'] for g in grupo]
                    x['fora'] = dict(x['fora'], larg=vs[0] if all(v == vs[0] for v in vs) else vs)
                faixas.append(x)
            b = dict(b0)
            if 'dist' in b and not isinstance(b['dist'], str):
                vs = [g[2]['dist'] for g in grupo]
                b['dist'] = vs[0] if all(v == vs[0] for v in vs) else vs
            fatias.append({'s0': grupo[0][0] * passo, 's1': grupo[-1][0] * passo, 'faixas': faixas, 'barreira': b})
            grupo = []
        if item is not None:
            grupo.append(item)
    return fatias


def aplicar(S0, S1, regra, barreira=None, rotulo=''):
    """reescreve as fatias de [S0, S1] (s das amostras, inclusive). regra(lado, s, i, fx) → faixas novas;
    barreira(lado, s, i, b) → barreira nova (opcional; sem ela a barreira não muda)"""
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
            s = i * passo
            meio.append((i, regra(lado, s, i, fx), barreira(lado, s, i, b) if barreira else b))
        novas = comprimir(meio)
        p['lados'][lado] = antes + novas + depois
        print(f'{lado}: {len(novas)} fatias no setor {rotulo}')


def arvores(S0, S1, zonas):
    """troca o setor [S0, S1] e as zonas dele no bloco `arvores` (os outros setores ficam). Parâmetros comuns
    (espacamento 5 m, escala 0,8–1,25, base 2,6) da Fase 4."""
    a = p.get('arvores') or {'setores': [], 'espacamento': 5.0, 'escala': [0.8, 1.25], 'base': 2.6, 'zonas': []}
    dentro = lambda z: z['s0'] >= S0 and z['s1'] <= S1 + 1  # noqa: E731
    a['setores'] = sorted([z for z in a['setores'] if not dentro(z)] + [{'s0': S0, 's1': S1}], key=lambda z: z['s0'])
    novas = [{'lado': l, 's0': s0, 's1': s1, 'd0': d0, 'd1': d1, 'dens': de, 'fonte': f} for l, s0, s1, d0, d1, de, f in zonas]
    outras = [z for z in a['zonas'] if not dentro(z)]
    # ordem: por setor (o que contém o s0 da zona; com o limite de cima aberto, porque setores vizinhos dividem a ponta:
    # Fase 5, 783 e 1369), e dentro do setor a ordem do script
    a['zonas'] = sorted(outras + novas, key=lambda z: next(k for k, t in enumerate(a['setores']) if t['s0'] <= z['s0'] < t['s1'] or k == len(a['setores']) - 1))
    p['arvores'] = {'setores': a['setores'], 'espacamento': a['espacamento'], 'escala': a['escala'], 'base': a['base'], 'zonas': a['zonas']}
    if 'ancora' in a:  # âncora do sorteio congelada pelos setores (Fase 6; arvoresSetor.ts)
        p['arvores']['ancora'] = a['ancora']


def ancora(segmentos):
    """(Fase 5) junta trechos de muro congelado ao bloco arvores.ancora: {lado: {s0, muro}} → cada lado vira uma lista
    ordenada por s0; um trecho novo substitui o que se sobrepõe a ele (rodar o mesmo setor de novo dá o mesmo arquivo)"""
    anc = p['arvores'].setdefault('ancora', {})
    for lado, seg in segmentos.items():
        atual = anc.get(lado, [])
        lista = atual if isinstance(atual, list) else [atual]
        a0, a1 = seg['s0'], seg['s0'] + passo * (len(seg['muro']) - 1)
        fica = [x for x in lista if x['s0'] + passo * (len(x['muro']) - 1) < a0 or x['s0'] > a1]
        anc[lado] = sorted(fica + [seg], key=lambda x: x['s0'])
    print('âncora congelada:', {k: [(x['s0'], x['s0'] + passo * (len(x['muro']) - 1)) for x in v] for k, v in anc.items()})


def gravar():
    txt = json.dumps(p, indent=1, ensure_ascii=False)
    # listas de números numa linha só (como o migrarPerfil2B.ts)
    txt = re.sub(r'\[\s+([-0-9.,\s]+?)\s+\]', lambda m: '[' + re.sub(r'\s+', '', m.group(1)) + ']', txt)
    open(PERFIL, 'w', encoding='utf-8', newline='\n').write(txt + '\n')
    print('gravado', PERFIL)
