# Fase 3 (PLANO-INTERLAGOS-DETALHES.md) — Reta dos boxes + freada do S: reescreve as fatias do perfil lateral
# (data/track/visual_profile.json) entre s 3900 e 4306 e entre s 0 e 248 (s novo; o setor cruza a linha de chegada; o
# plano diz 3884–4294 + 0–250, que é o s antigo), a partir da ficha build/ref/interlagos/fichas/setor-3.md. Fora do setor o
# arquivo não muda (o setor 10 acaba em 3898 e o setor 4 começa em 250). Idempotente (larguras limitadas pelo muro da
# física atual: rodar de novo depois de mudar a física). Os scripts 3, 4, 5 e 6 rodados em qualquer ordem dão o mesmo
# arquivo.
#
# uso (de REPOS/gt3-godot): python tools/cenario/interlagos/setor3_perfil.py
#
# Decisões (vídeo = quadros chase_v2 do atlas, folhas build/ref/interlagos/folhas/fase3_ini_*; satélite = Esri z19
# desenrolado, build/interlagos/fase3/sat_esq_d2.jpg, sat_reta.jpg, sat_setor3.jpg):
#   esq 3900–3938  como estava (grama até o guard-rail, LMU s 3910)
#   esq 3940–3984  pista dos boxes colada na pista: escape "asfalto" até o muro da física (= muro de fora da pista dos
#                  boxes desde a Fase 3; LMU s 3940/3970: linha tracejada e asfalto até o guard-rail)
#   esq 3986–4098  ilha verde (e até ~4116, enquanto o muro da física desce em diagonal no bico) entre a pista e a pista dos boxes (escape "verde", largura ILHA: 0 → 13 m; satélite: ponta
#                  com divisas em 3985–4020, ilha até o bico do muro dos boxes em ~4104; LMU s 4000–4090) + pista dos
#                  boxes (escape.fora "asfalto") até o muro da física
#   esq 4100–4306  faixa verde até o muro dos boxes (física a borda + 4 m; satélite: pintura verde de 4,0 m; LMU s
#                  4120–4300); antes 1,4 m de verde
#   esq 0–248      como estava
#   dir 3900–4306, 0–248  faixa verde até o muro (satélite: pintura 2,5–4,2 m = o vão até o muro; LMU s 3910–230: verde
#                  até o muro, sem grama); antes 1,4 m de verde e grama
#   barreiras      esq 3930–4098 guard-rail com alambrado (LMU s 3940–4060: guard-rail e alambrado depois da pista dos
#                  boxes); esq 4100–4306 muro dos boxes verde (ROLEX) com alambrado (antes a partir de 4058, no meio da
#                  ilha); dir 3900–3926 muro AVIS (LMU s 3910: fim dos painéis AVIS), 3928–4306 muro verde ROLEX (antes
#                  AVIS até 4042); o resto como estava
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from perfil_setor import aplicar, arvores, folga, gravar  # noqa: E402

# largura da ilha da entrada dos boxes (m além da borda), por s novo; = ILHA no trackDetails.ts (buildPitEntry)
ILHA = ([3986, 4000, 4020, 4040, 4060, 4098], [0.0, 3.0, 7.0, 11.0, 13.0, 13.0])


def regra(lado, s, i, fx):
    if lado == 'esq':
        if 3940 <= s <= 3984:
            return [{'tipo': 'escape', 'cor': 'asfalto', 'larg': round(folga(lado, i, True), 3)}]
        if 3986 <= s <= 4098 or (4100 <= s <= 4120 and folga(lado, i, True) > 5):
            # (4100–4120: bico do muro dos boxes, onde o muro da física ainda desce em diagonal: a ilha segue com 13 m)
            g = folga(lado, i, True)
            ilha = min(float(np.interp(s, *ILHA)), g)
            out = {'tipo': 'escape', 'cor': 'verde', 'larg': round(ilha, 3)}
            if g - ilha > 0.5:
                out['fora'] = {'cor': 'asfalto', 'larg': round(g - ilha, 3)}
            return [out] if ilha > 0 else [{'tipo': 'escape', 'cor': 'asfalto', 'larg': round(g, 3)}]
        if 4100 <= s <= 4306:
            return [{'tipo': 'escape', 'cor': 'verde', 'larg': round(folga(lado, i, True), 3)}]
        return fx
    return [{'tipo': 'escape', 'cor': 'verde', 'larg': round(folga(lado, i, True), 3)}]


def barreira(lado, s, i, b):
    if lado == 'esq':
        if 3930 <= s <= 4098:
            return {'tipo': 'rail', 'dist': 'fisica', 'alambrado': True}
        if 4100 <= s <= 4306:
            return {'tipo': 'wall', 'dist': 'fisica', 'banner': 'verde', 'alambrado': True}
        return b
    if 3900 <= s <= 3926:
        return {'tipo': 'wall', 'dist': 'fisica', 'banner': 'avis', 'alambrado': True}
    if 3928 <= s <= 4306:
        return {'tipo': 'wall', 'dist': 'fisica', 'banner': 'verde', 'alambrado': True}
    return b


aplicar(3900, 4306, regra, barreira, rotulo='3 (3900–4306)')
aplicar(0, 248, regra, barreira, rotulo='3 (0–248)')

# Árvores, Etapa A (§5): zonas por s e lado, d = metros além do muro da física; dens = fração que fica. Fontes: altura
# de copa do LiDAR (lidar.copa > 4 m, fração por faixa de d; build/interlagos/fase3/copa.py, tabela no setor-3.md; aqui a
# "copa" também pega a cobertura do paddock e as arquibancadas) e o vídeo (LMU chase_v2). Plantio novo (mata atrás da
# arquibancada aberta da direita, s 3900–4110) no trackView.ts (buildScenery).
ZONAS3A = [
    ('esq', 3900, 3990, 0, 40, 0.0, 'guard-rail, grama e alambrado da entrada dos boxes (copa 0,03–0,1; LMU s 3910–3970)'),
    ('esq', 3900, 3990, 40, 200, 0.5, 'árvores esparsas ao fundo (copa 0,05–0,1)'),
    ('esq', 3990, 4308, 0, 70, 0.0, 'ilha, pista dos boxes, garagens e paddock (copa ≤ 0,27; LMU s 4000–4300)'),
    ('esq', 3990, 4308, 70, 200, 0.4, 'fundo do paddock'),
]
ZONAS3B = [
    ('esq', 0, 249, 0, 70, 0.0, 'pista dos boxes e paddock coberto (LMU s 80–230: tendas brancas e prédios; copa 1,0 a '
     '20–40 m = cobertura do paddock)'),
    ('esq', 0, 249, 70, 200, 0.4, 'fundo do paddock (copa 0,1–0,3)'),
]
arvores(3900, 4308, ZONAS3A)
arvores(0, 249, ZONAS3B)
gravar()
