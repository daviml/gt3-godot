# Fase 5 (PLANO-INTERLAGOS-DETALHES.md) — Reta Oposta: reescreve as fatias do perfil lateral
# (data/track/visual_profile.json) entre s 784 e 1368 (s novo; o plano diz 776–1362, que é o s antigo), a partir da
# ficha build/ref/interlagos/fichas/setor-5.md. Fora do setor o arquivo não muda. Idempotente (larguras limitadas pelo
# muro da física atual: rodar de novo depois de mudar a física).
#
# uso (de REPOS/gt3-godot): python tools/cenario/interlagos/setor5_perfil.py
#
# Decisões (vídeo = quadros chase_v2/onboard_v2 do atlas, folhas build/ref/interlagos/folhas/fase5_ini_*; satélite =
# Esri z19 desenrolado, build/interlagos/fase5/c1.jpg, c2.jpg, esq_par.jpg, dir_par.jpg):
#   esq 784–810   zebra + faixa verde-água de 0,5 m (continua a da Curva do Sol, setor 4)
#   esq 812–1004  pista dos boxes depois da junção = o escape asfaltado da física (runL, faixa de aceleração): cor
#                 "asfalto" (antes grama); a ilha do separador (runL = 0, até ~830) fica grama
#   esq 1006–1368 grama até o guard-rail (como estava)
#   esq barreira  guard-rail; alambrado só até 1004 (LMU s 1020–1290: guard-rail e árvores, sem alambrado perto)
#   dir 784–888   zebra + escape vermelho até 2,5 m do muro + faixa verde de 2,5 m junto do muro MOTUL (LMU s 790–870;
#                 emenda contínua com a saída da Curva do Sol, que acaba em 782 do mesmo jeito)
#   dir 890–948   sem zebra: grama de 2,5 m + vermelho + faixa verde (LMU s 900–950: grama, vermelho e verde; satélite:
#                 faixa clara de ~2 m antes da pintura)
#   dir 950–1002  escape verde-água até o muro (LMU s 950–1000; satélite: escape 7,5 m em s novo 964–1000), a grama
#                 da borda some até 962
#   dir 1004–1260 grama até o muro (LMU s 1020–1230)
#   dir 1262–1368 área de escape ("AT ESCAPE ROAD" no vídeo): grama de 3,8 m + asfalto até o muro (satélite: grama clara
#                 até borda + ~3,5 m e asfalto até o muro da física, borda + 8,5 m; LMU s 1260–1360); afina em 1336–1368
#                 para emendar com o setor 6, que não a tem
#   dir barreira  muro MOTUL até 1002; depois muro de concreto verde-escuro liso com alambrado (banner "muro_verde";
#                 LMU s 1000–1360; antes muro MOTUL até 1154 e barreira acolchoada ROLEX até 1368)
# As faixas vermelha e verde da Reta Oposta saíram do código (trackDetails.ts buildOppositeRunoff, que as desenhava a
# borda + 1,5–4,5 e 4,5–7 m de s 786 a 1155) para este perfil.
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from perfil_setor import K, aplicar, ancora, arvores, escape, folga, gravar, zebra  # noqa: E402

S0, S1 = 784, 1368  # amostras do setor (inclusive; passo 2 m): a fatia anterior acaba em 782, a seguinte começa em 1370

T = json.load(open(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'data', 'track', 'track.json'), encoding='utf-8'))
RUN_L = [T['s'][i * T['stride'] + 12] for i in range(T['n'])]


def rampa(s, a, b, va, vb):
    t = min(1.0, max(0.0, (s - a) / (b - a)))
    return va + (vb - va) * t


def regra(lado, s, i, fx):
    if K[lado][i] > 0 and not zebra(fx):
        fx = [{'tipo': 'zebra', 'larg': 'fisica'}] + fx
    if lado == 'esq':
        if K[lado][i] > 0:
            return zebra(fx) + [{'tipo': 'escape', 'cor': 'agua', 'larg': round(min(0.5, folga(lado, i)), 3)}]
        if s <= 1004 and RUN_L[i] > 0:
            return [{'tipo': 'escape', 'cor': 'asfalto', 'larg': 'fisica'}]
        return []
    if s <= 948:
        out = escape(lado, i, fx, 'vermelho', 30.0, ('verde', 2.5))
        if not zebra(fx):
            # grama antes do vermelho (rampa de 6 m depois do fim da zebra)
            ini = next(k for k in range(i, -1, -1) if K[lado][k] > 0) * 2 + 2
            g = round(min(rampa(s, ini, ini + 6, 0.0, 2.5), out[-1]['larg']), 3)
            if g > 0:
                out[-1]['grama'] = g
        return out
    if s <= 1002:
        out = escape(lado, i, fx, 'agua', 30.0)
        g = round(min(rampa(s, 950, 962, 2.5, 0.0), out[-1]['larg']), 3)
        if g > 0:
            out[-1]['grama'] = g
        return out
    if s <= 1260:
        return zebra(fx)
    larg = folga(lado, i, not zebra(fx))
    # o setor 6 (s ≥ 1370) não tem a área de escape: ela afina até sumir em 1368 (no satélite segue reta, afastando-se
    # da pista, até ~1420; pendência na ficha)
    larg = round(min(larg, rampa(s, 1336, 1368, larg, 3.8)), 3)
    if larg <= 4.3:
        return zebra(fx)
    return zebra(fx) + [{'tipo': 'escape', 'cor': 'asfalto', 'larg': larg, 'grama': 3.8}]


def barreira(lado, s, i, b):
    if lado == 'esq':
        b = {'tipo': 'rail', 'dist': 'fisica'}
        if 806 <= s <= 1004:
            b['alambrado'] = True
        return b
    if s <= 1002:
        return {'tipo': 'wall', 'dist': 'fisica', 'banner': 'vermelho'}
    return {'tipo': 'wall', 'dist': 'fisica', 'banner': 'muro_verde', 'alambrado': True}


aplicar(S0, S1, regra, barreira, rotulo='5')

# Árvores, Etapa A (§5): zonas por s e lado, d = metros além do muro da física; dens = fração que fica. Fontes: altura
# de copa do LiDAR (lidar.copa > 4 m, fração por faixa de d; tabela no setor-5.md, build/interlagos/fase5/copa.py) e o
# vídeo (LMU chase_v2). A esquerda a menos de 70 m do centro já é "aberta" desde antes (trackside.ts occupied, s 926+).
ZONAS5 = [
    ('esq', 783, 1004, 0, 60, 0.0, 'pista dos boxes, guard-rail e campo aberto (copa ≈ 0 até 70 m; LMU s 790–1000)'),
    ('esq', 783, 1004, 60, 200, 0.4, 'árvores esparsas ao fundo (copa 0,2–0,4 a 70–160 m)'),
    ('esq', 1004, 1060, 0, 20, 0.0, 'guard-rail e grama (copa 0 até 20 m)'),
    ('esq', 1004, 1180, 20, 200, 0.8, 'mata atrás do guard-rail (copa 0,3–1,0; LMU s 1020–1170)'),
    ('esq', 1060, 1180, 0, 20, 0.6, 'árvores junto do guard-rail (copa 0,2–0,6 a 7–20 m)'),
    ('esq', 1180, 1369, 0, 200, 0.5, 'árvores esparsas e área dos fiscais (copa 0,1–0,6; LMU s 1200–1360)'),
    ('dir', 783, 1004, 0, 70, 0.0, 'talude gramado atrás do muro MOTUL (copa ≈ 0; LMU s 790–1000)'),
    ('dir', 783, 1004, 70, 200, 0.4, 'árvores esparsas no alto (copa 0,1–0,5)'),
    ('dir', 1004, 1180, 0, 70, 0.0, 'talude gramado atrás do alambrado (copa ≈ 0; LMU s 1020–1170)'),
    ('dir', 1004, 1180, 70, 200, 0.3, 'campo aberto (copa ≈ 0)'),
    ('dir', 1180, 1369, 0, 40, 0.0, 'escape road e talude (copa ≈ 0 até 40 m; LMU s 1200–1360)'),
    ('dir', 1180, 1369, 40, 200, 0.7, 'mata ao fundo (copa 0,2–0,9 a 40–160 m)'),
]
arvores(783, 1369, ZONAS5)

# Âncora do sorteio da mata (arvores.ancora, ./arvoresSetor.ts): a Fase 5 moveu o muro da física (dir 770–920: muro
# MOTUL a borda + 15 m; esq 818–836: ponta do separador da saída dos boxes). A âncora fica no muro de antes, EXATO como o
# gerador montava: build/interlagos/fase5/ancora_exata.json (build/interlagos/fase5/ancora.ts, montaPista no
# interlagos.json de antes da Fase 5). Sem o arquivo, mantém a âncora que já está no perfil.
ANC = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'build', 'interlagos', 'fase5', 'ancora_exata.json')
if os.path.exists(ANC):
    ancora(json.load(open(ANC, encoding='utf-8')))
gravar()
