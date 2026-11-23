# Fase 2C (PLANO-INTERLAGOS-DETALHES.md): zebras do perfil lateral pelo satélite + vídeo do LMU e correção dos
# picos de muro/escape nas transições herdadas do código antigo.
#
# Entrada:  data/track/visual_profile.json (perfil atual), data/track/track.json (física: wl/wr, kerb, run, wall)
#           tools/tracks/interlagos/interlagos-perfil-sat.json (medidas do satélite, Fase 2A)
# Saída:    data/track/visual_profile.json reescrito (só as fatias tocadas são divididas/alteradas)
#
# O que muda no perfil (e só isso):
#   - zebra listrada: visível exatamente nos trechos de ZEBRAS (o resto vira `listrada: false`, que mantém a largura
#     da física para escape e barreira). Onde a física não tem zebra, entra `visual: "normal" | "saida"` (perfil.ts).
#   - Ferradura: faixa verde + salsicha (sem listras) estendidas até o fim medido (PINTURA_EXTRA).
#   - PICOS: muro (dist sem `de`, contada da linha branca) e escape trocados por uma transição monotônica
#     (smoothstep) entre os valores das pontas.
# Reaplicar é idempotente (os trechos já divididos são reescritos com os mesmos valores).
#
# Tabelas abaixo também são lidas por overlay_perfil.py (diferencas.md).
#
# uso (de REPOS/gt3-godot): python tools/tracks/interlagos/perfil_zebras.py [--seco]
import copy
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
PERFIL = os.path.join(ROOT, 'data', 'track', 'visual_profile.json')
TRACK = os.path.join(ROOT, 'data', 'track', 'track.json')

# ------------------------------------------------------------------------------------------------ decisões
# zebra listrada final: (lado, s0, s1, classe, fonte, nota)
#   classe: 'fisica' = largura visual pela física (1,2 → 1,0 m; 2,2 → 1,6 m); 'normal' (1,0 m) / 'saida' (1,6 m)
#   fonte:  'satelite' = início e fim do satélite; 'video' = existência e metro tirados do vídeo (±5–10 m);
#           'satelite+video' = satélite, com o vídeo confirmando presença/continuidade
#   sat:    segmentos do satélite (interlagos-perfil-sat.json → zebras) que a zebra representa
ZEBRAS = [
    # esquerda
    dict(lado='esq', s0=321, s1=417, classe='fisica', fonte='satelite+video', sat=[(321, 340), (353, 366), (387, 417)],
         nota='S do Senna: vídeo s350/s380 mostra zebra contínua; buracos do satélite (340–353, 366–387) são sombra/pintura'),
    dict(lado='esq', s0=531, s1=802, classe='normal', fonte='satelite+video', sat=[(531, 541), (550, 802)],
         nota='Curva do Sol interna: vídeo s540 com o carro já na zebra (começa antes de 540); junta 531–541 e 550–802'),
    dict(lado='esq', s0=1361, s1=1467, classe='fisica', fonte='satelite+video', sat=[(1361, 1389), (1402, 1420), (1432, 1467)],
         nota='Descida do Lago (ápice): vídeo s1400 contínua; buracos do satélite sem listras visíveis (desbotada)'),
    dict(lado='esq', s0=1529, s1=1639, classe='fisica', fonte='satelite+video', sat=[(1529, 1639)],
         nota='Lago, saída junto ao muro Goodyear: listras nítidas no satélite (conf 0 só pela sombra); vídeo s1540 confirma; s1660 já sem zebra'),
    dict(lado='esq', s0=2176, s1=2222, classe='fisica', fonte='video', sat=[],
         nota='Ferradura, saída por fora: satélite sem zebra (sombra das arquibancadas); vídeo s2160 sem, s2190 com zebra ao lado do carro; fim = fim da física'),
    dict(lado='esq', s0=2405, s1=2552, classe='fisica', fonte='satelite+video', sat=[(2405, 2552)],
         nota='Pinheirinho: vídeo s2390 (começa logo à frente) e s2560 (já acabou)'),
    dict(lado='esq', s0=2738, s1=2762, classe='fisica', fonte='satelite', sat=[(2738, 2762)],
         nota='Bico de Pato (entrada, por fora): só satélite, sem quadro do vídeo'),
    dict(lado='esq', s0=2879, s1=3034, classe='fisica', fonte='satelite+video', sat=[(2879, 3054)],
         nota='Mergulho: início pelo satélite; fim pelo vídeo (s3020 zebra acaba à frente, s3040 só faixa verde) — satélite 3054'),
    dict(lado='esq', s0=3200, s1=3289, classe='fisica', fonte='satelite+video', sat=[(3200, 3237), (3255, 3289)],
         nota='Junção: vídeo s3250 com zebra contínua ao lado do carro (o buraco 3237–3255 é sombra)'),
    dict(lado='esq', s0=3352, s1=3413, classe='fisica', fonte='satelite', sat=[(3352, 3378), (3403, 3413)],
         nota='saída da Junção: blocos visíveis no satélite entre os dois segmentos; sem quadro do vídeo'),
    dict(lado='esq', s0=3659, s1=3696, classe='normal', fonte='satelite', sat=[(3659, 3696)],
         nota='Subida dos Boxes: só satélite (listras fracas), sem quadro do vídeo'),
    # direita
    dict(lado='dir', s0=412, s1=474, classe='fisica', fonte='satelite+video', sat=[(412, 441), (457, 474)],
         nota='S do Senna (2ª perna): vídeo s440 mostra zebra contínua à direita até ~460'),
    dict(lado='dir', s0=745, s1=878, classe='saida', fonte='satelite+video', sat=[(796, 812), (818, 878)],
         nota='Curva do Sol, saída por fora (larga + vermelho): vídeo s750 já com zebra ao lado do carro e s720 sem; '
              'início pelo vídeo (~745, satélite 796, onde só vê a pintura verde-água), fim pelo satélite (s870 confirma)'),
    dict(lado='dir', s0=1505, s1=1535, classe='saida', fonte='video', sat=[],
         nota='Descida do Lago, saída por fora: vídeo s1520 com zebra ao lado do carro, s1400 e s1540 sem; '
              'satélite só vê o escape verde-água (1473–1528). Início e fim estimados (±10 m)'),
    dict(lado='dir', s0=1669, s1=1746, classe='normal', fonte='satelite+video', sat=[(1669, 1675), (1681, 1692), (1699, 1707), (1729, 1746)],
         nota='subida do Lago: vídeo s1660 mostra zebra contínua começando à frente; segmentos do satélite juntados'),
    dict(lado='dir', s0=2563, s1=2638, classe='saida', fonte='satelite+video', sat=[(2563, 2612), (2617, 2638)],
         nota='Pinheirinho, saída por fora: vídeo s2560 (zebra larga começando ao lado do carro)'),
    dict(lado='dir', s0=2750, s1=2810, classe='fisica', fonte='satelite', sat=[(2750, 2771), (2777, 2810)],
         nota='Bico de Pato (ápice): listras contínuas no recorte do satélite; sem quadro do vídeo'),
    dict(lado='dir', s0=3239, s1=3253, classe='saida', fonte='satelite', sat=[(3239, 3253)],
         nota='Junção, saída por fora: só satélite (fora do quadro no vídeo s3250)'),
    dict(lado='dir', s0=3334, s1=3365, classe='saida', fonte='satelite', sat=[(3334, 3365)],
         nota='saída da Junção por fora: listras nítidas no satélite; sem quadro do vídeo'),
]

# segmentos do satélite que não viraram zebra: (lado, s0, s1, motivo)
NAO_APLICADAS = [
    ('esq', 427, 439, 'vídeo s440 sem zebra à esquerda; sem listras visíveis no recorte do satélite'),
    ('esq', 999, 1006, 'curto (< 12 m) e estreito; pórtico da Reta Oposta / sombra'),
    ('esq', 1212, 1244, 'ruído de copa/sombra de árvore no recorte (sem listras), reta'),
    ('esq', 1249, 1254, 'curto, conf 0'),
    ('esq', 1801, 1815, 'conf 1, sem curva, sem conferência no vídeo'),
    ('esq', 2332, 2338, 'curto (< 12 m)'),
    ('esq', 2607, 2614, 'curto (< 12 m)'),
    ('esq', 2644, 2650, 'curto (< 12 m)'),
    ('esq', 2669, 2677, 'curto (< 12 m), conf 0'),
    ('esq', 3081, 3093, 'curto (< 12 m), largura 0,5'),
    ('esq', 3504, 3515, 'curto (< 12 m); objeto branco junto à borda no satélite'),
    ('esq', 3855, 3863, 'entrada dos boxes (marcas da ilha); vídeo s3870 sem zebra'),
    ('esq', 3879, 3887, 'entrada dos boxes (marcas da ilha); vídeo s3870 sem zebra'),
    ('esq', 3892, 3909, 'entrada dos boxes (marcas da ilha); vídeo s3870 sem zebra'),
    ('dir', 942, 947, 'curto (< 12 m), largura 0,5'),
    ('dir', 2191, 2197, 'curto; é o fim da faixa verde + salsicha da Ferradura (usado como fim dela)'),
    ('dir', 2318, 2324, 'curto (< 12 m)'),
    ('dir', 2346, 2351, 'curto (< 12 m), largura 0,5'),
    ('dir', 2362, 2373, 'curto (< 12 m), largura 0,8'),
    ('dir', 3105, 3123, 'largura 0,8 (provável linha/pintura), sem vídeo'),
    ('dir', 3314, 3322, 'curto (< 12 m)'),
    ('dir', 3423, 3431, 'curto (< 12 m), conf 0'),
    ('dir', 3757, 3766, 'curto, conf 1, junto ao muro dos boxes'),
    ('dir', 3780, 3785, 'curto, conf 1'),
]

# Ferradura (direita): faixa verde + salsicha sem listras (o LMU tem isso nos dois ápices; vídeo s2000, s2120, s2160).
# Já existia de 1988 a 2044; estendida até o fim medido (s2190 sem salsicha; satélite 2191–2197).
PINTURA_EXTRA = [('dir', 2046, 2196, [{'tipo': 'pintura', 'cor': 'verde', 'larg': 0.65}, {'tipo': 'salsicha', 'larg': 0.4}])]

# picos de muro/escape: (lado, s0, s1, muro?, escape?, motivo) — transição monotônica entre as pontas (s0-2 e s1+2)
PICOS = [
    ('esq', 376, 394, True, True, 'muro 3,8 → 6,0 → 4,2 m e escape 2,6 → 4,8 → 3,0 (salto em 384→386)'),
    ('esq', 580, 594, True, False, 'muro salta 3,0 → 5,5 m em 2 m (entrada da Curva do Sol) e sobe a 10,5'),
    ('esq', 2242, 2266, False, True, 'escape cai de 1,8 a 0,2 e volta a 2,4 m'),
    ('esq', 4010, 4034, True, False, 'muro 9,4 → 11,7 → 1,4 m com salto de 10 m em 4032→4034'),
    ('dir', 2178, 2270, True, True, 'muro 9 → 16 → 5,5 m (vai ao muro da física e volta) e escape com degrau em 2224→2232'),
    ('dir', 2468, 2510, True, True, 'muro 5,5 → 15,5 → 9 m e escape 0 → 12 → 0 m (satélite: grama, sem escape largo)'),
    ('dir', 3428, 3460, True, True, 'muro salta 1,4 → 15,8 m em 3434→3436 e volta a 1,4; escape 1,4 → 7,5 → 1,4'),
]
# pedidos que não são pico (transição monotônica para um platô longo do muro da física): ficam como estão
PICOS_NAO = [
    ('dir', 1968, 1986, 'transição monotônica 16 → 9 m: o muro da física (16 m) vale de 1688 a 1966 (280 m), não é pico'),
    ('dir', 2612, 2620, 'transição monotônica 9 → 15,6 m para o platô da física 2622–2880 (258 m)'),
    ('esq', 2478, 2496, 'transição monotônica 16 → 5,7 m saindo do platô 2268–2476 (escape de 12 m da física, 208 m)'),
    ('esq', 3354, 3370, 'transição monotônica 9,7 → 16 m para o platô da física 3372–3494 (122 m)'),
    ('esq', 3496, 3520, 'transição monotônica 16 → 3,8 m saindo do mesmo platô'),
]


# ------------------------------------------------------------------------------------------------ avaliação
def carrega():
    t = json.load(open(TRACK, encoding='utf-8'))
    p = json.load(open(PERFIL, encoding='utf-8'))
    return t, p


def fisica(t):
    S = t['s']
    N = t['n']
    col = lambda c: [S[i * 16 + c] for i in range(N)]
    return {'esq': dict(w=col(8), k=col(10), r=col(12), W=col(14)), 'dir': dict(w=col(9), k=col(11), r=col(13), W=col(15))}


def _val(v, k, f):
    return f if v == 'fisica' else (v if isinstance(v, (int, float)) else v[k])


def avalia(p, t, lado):
    """o perfil avaliado por amostra (mesma conta de tools/cenario/interlagos/perfil.ts)."""
    F = fisica(t)[lado]
    N = t['n']
    passo = p['passo']
    out = [None] * N
    for fi, f in enumerate(p['lados'][lado]):
        g = lambda tp: next((x for x in f['faixas'] if x['tipo'] == tp), None)
        z, pin, sal, esc = g('zebra'), g('pintura'), g('salsicha'), g('escape')
        b = f['barreira']
        i0 = round(f['s0'] / passo)
        for i in range(i0, round(f['s1'] / passo) + 1):
            k = i - i0
            kerb = (max(F['k'][i], z['minimo']) if 'minimo' in z else F['k'][i]) if z else 0
            run = _val(esc['larg'], k, F['r'][i]) if esc else 0
            if b['dist'] == 'fisica':
                wall = F['W'][i]
            else:
                d = _val(b['dist'], k, None)
                wall = F['w'][i] + (kerb + run + d if b.get('de') == 'escape' else kerb + d if b.get('de') == 'zebra' else d)
            listrada = bool(z) and z.get('listrada', True) is not False
            vis = z.get('visual') if z else None
            if not listrada:
                zl = 0.0
            elif vis == 'normal':
                zl = 1.0
            elif vis == 'saida':
                zl = 1.6
            elif kerb > 0:
                zl = 1.0 + 0.6 * max(0.0, min(1.0, (kerb - 1.2) / 1.0))
            else:
                zl = 0.0
            out[i] = dict(fi=fi, kerb=kerb, zebra=zl, verde=pin['larg'] if pin else 0.0, salsicha=sal['larg'] if sal else 0.0,
                          run=run, cor=esc['cor'] if esc else 'verde', wall=wall, w=F['w'][i], tipo=b['tipo'],
                          banner=b.get('banner'), alambrado=bool(b.get('alambrado')))
    return out


def segmentos(xs, cond):
    r, cur = [], None
    for i, a in enumerate(xs):
        if cond(a):
            if cur is None:
                cur = i
        elif cur is not None:
            r.append((cur, i - 1))
            cur = None
    if cur is not None:
        r.append((cur, len(xs) - 1))
    return r


# ------------------------------------------------------------------------------------------------ aplicação
def _smooth(t):
    return t * t * (3 - 2 * t)


def aplica(p, t):
    N = t['n']
    passo = p['passo']
    novo = {}
    for lado in ('esq', 'dir'):
        A = avalia(p, t, lado)
        fat = p['lados'][lado]
        # estado desejado por amostra
        zeb = [None] * N
        for z in ZEBRAS:
            if z['lado'] != lado:
                continue
            idx = range(-(-z['s0'] // passo), z['s1'] // passo + 1)
            # classe "fisica": nas pontas que passam da zebra da física (kerb 0), a classe que a física tem no meio
            ks = sorted(A[i]['kerb'] for i in idx if A[i]['kerb'] > 0)
            dom = 'saida' if ks and ks[len(ks) // 2] >= 1.7 else 'normal'
            for i in idx:
                zeb[i] = z['classe'] if z['classe'] != 'fisica' or A[i]['kerb'] > 0 else dom
        pint = [None] * N
        for (l, a, b, fx) in PINTURA_EXTRA:
            if l == lado:
                for i in range(-(-a // passo), b // passo + 1):
                    pint[i] = fx
        pico = [None] * N
        for (l, a, b, muro, esc, _) in PICOS:
            if l != lado:
                continue
            ia, ib = a // passo, b // passo
            e0, e1 = A[ia - 1], A[(ib + 1) % N]
            for i in range(ia, ib + 1):
                u = _smooth((i - (ia - 1)) / ((ib + 1) - (ia - 1)))
                pico[i] = dict(
                    W=(e0['wall'] - e0['w']) + ((e1['wall'] - e1['w']) - (e0['wall'] - e0['w'])) * u if muro else None,
                    R=e0['run'] + (e1['run'] - e0['run']) * u if esc else None,
                    cor=e0['cor'] if e0['run'] > 0 or e1['run'] <= 0 else e1['cor'])
        # amostra → (fatia original, deslocamento)
        orig = []
        for fi, f in enumerate(fat):
            i0 = round(f['s0'] / passo)
            for i in range(i0, round(f['s1'] / passo) + 1):
                orig.append((fi, i - i0))
        assert len(orig) == N
        chave = lambda i: (orig[i][0], zeb[i], json.dumps(pint[i]), pico[i] is not None)
        out = []
        i = 0
        while i < N:
            j = i
            while j + 1 < N and chave(j + 1) == chave(i):
                j += 1
            fi, k0 = orig[i]
            k1 = orig[j][1]
            f = copy.deepcopy(fat[fi])
            corta = lambda v: v[k0:k1 + 1] if isinstance(v, list) else v
            for fx in f['faixas']:
                if 'larg' in fx:
                    fx['larg'] = corta(fx['larg'])
            f['barreira']['dist'] = corta(f['barreira']['dist'])
            f['s0'], f['s1'] = i * passo, j * passo
            # zebra
            z = next((x for x in f['faixas'] if x['tipo'] == 'zebra'), None)
            classe = zeb[i]
            if classe is None:
                if z is not None:
                    z['listrada'] = False
                    z.pop('visual', None)
            else:
                if z is None:
                    if classe == 'fisica':
                        raise SystemExit(f'{lado} {f["s0"]}..{f["s1"]}: zebra "fisica" onde o perfil não tem zebra da física')
                    z = {'tipo': 'zebra', 'larg': 'fisica'}
                    f['faixas'].insert(0, z)
                z.pop('listrada', None)
                if classe == 'fisica':
                    z.pop('visual', None)
                else:
                    z['visual'] = classe
            # pintura + salsicha extra (sem listras)
            if pint[i] is not None:
                f['faixas'] = [x for x in f['faixas'] if x['tipo'] not in ('pintura', 'salsicha')]
                pos = 1 if f['faixas'] and f['faixas'][0]['tipo'] == 'zebra' else 0
                for n_, fx in enumerate(copy.deepcopy(pint[i])):
                    f['faixas'].insert(pos + n_, fx)
            # pico: muro e/ou escape explícitos
            if pico[i] is not None:
                P = [pico[x] for x in range(i, j + 1)]
                if P[0]['W'] is not None:
                    f['barreira']['dist'] = [round(q['W'], 4) for q in P]
                    f['barreira'].pop('de', None)
                elif f['barreira'].get('de') == 'escape' and P[0]['R'] is not None:
                    raise SystemExit(f'{lado} {f["s0"]}: escape do pico mexeria no muro (de: escape)')
                if P[0]['R'] is not None:
                    runs = [round(q['R'], 4) for q in P]
                    f['faixas'] = [x for x in f['faixas'] if x['tipo'] != 'escape']
                    if max(runs) > 1e-3:
                        f['faixas'].append({'tipo': 'escape', 'cor': P[0]['cor'], 'larg': runs})
            # listas constantes viram número (mesmo resultado)
            for fx in f['faixas']:
                if isinstance(fx.get('larg'), list) and len(set(fx['larg'])) == 1:
                    fx['larg'] = fx['larg'][0]
            if isinstance(f['barreira']['dist'], list) and len(set(f['barreira']['dist'])) == 1:
                f['barreira']['dist'] = f['barreira']['dist'][0]
            out.append(f)
            i = j + 1
        novo[lado] = out
    p2 = copy.deepcopy(p)
    p2['lados'] = novo
    return p2


def confere(p_antes, p_depois, t):
    """o que mudou por amostra (zebra visível, muro, escape, kerb) — kerb nunca pode mudar."""
    rel = {}
    for lado in ('esq', 'dir'):
        A, B = avalia(p_antes, t, lado), avalia(p_depois, t, lado)
        mud = {k: [i for i in range(len(A)) if abs(A[i][k] - B[i][k]) > 1e-6] for k in ('kerb', 'zebra', 'wall', 'run', 'verde', 'salsicha')}
        if mud['kerb']:
            raise SystemExit(f'{lado}: largura da física (kerb) mudou em {len(mud["kerb"])} amostras')
        for k in ('tipo', 'banner', 'alambrado'):
            if any(A[i][k] != B[i][k] for i in range(len(A))):
                raise SystemExit(f'{lado}: {k} da barreira mudou')
        rel[lado] = {k: [(a * 2, b * 2) for a, b in segmentos(range(len(A)), lambda i: i in set(v))] for k, v in mud.items() if v}
    return rel


def salva(p):
    # mesmo formato do arquivo gerado por extrairPerfil.ts (uma fatia por linha, JSON compacto)
    linhas = ['{', f'  "versao": {p["versao"]},', f'  "pista": {json.dumps(p["pista"])},', f'  "passo": {p["passo"]},',
              f'  "comprimento": {p["comprimento"]},', f'  "n": {p["n"]},', '  "lados": {']
    for li, lado in enumerate(('esq', 'dir')):
        linhas.append(f'  "{lado}": [')
        fs = p['lados'][lado]
        for k, f in enumerate(fs):
            linhas.append('    ' + json.dumps(f, ensure_ascii=False, separators=(',', ':')) + (',' if k < len(fs) - 1 else ''))
        linhas.append('  ]' + (',' if li == 0 else ''))
    linhas += ['  }', '}', '']
    open(PERFIL, 'w', encoding='utf-8', newline='\n').write('\n'.join(linhas))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    t, p = carrega()
    p2 = aplica(p, t)
    rel = confere(p, p2, t)
    for lado, r in rel.items():
        for k, v in r.items():
            print(f'{lado} {k}: {v}')
    print('fatias:', {l: len(p2['lados'][l]) for l in ('esq', 'dir')})
    if '--seco' not in sys.argv:
        salva(p2)
        print('gravado', PERFIL)
