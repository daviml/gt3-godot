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
# Funções comuns (expandir/cortar/comprimir/gravar) em ./perfil_setor.py desde a Fase 6 (mesmo resultado).
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from perfil_setor import aplicar, arvores, escape, folga, gravar, zebra  # noqa: E402

S0, S1 = 250, 782  # amostras do setor (inclusive); a fatia seguinte começa em 784


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


aplicar(S0, S1, regra, rotulo='4')

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
arvores(250, 783, ZONAS4)
gravar()
