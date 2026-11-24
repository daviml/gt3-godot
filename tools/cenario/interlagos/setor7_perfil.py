# Fase 7 (PLANO-INTERLAGOS-DETALHES.md) — Ferradura + Laranjinha: reescreve as fatias do perfil lateral
# (data/track/visual_profile.json) entre s 1984 e 2282 (s novo; o plano diz 1976–2278, que é o s antigo), a partir da
# ficha build/ref/interlagos/fichas/setor-7.md. Fora do setor o arquivo não muda. Idempotente (larguras limitadas pelo
# muro da física atual: rodar de novo depois de mudar a física). Os scripts dos setores em qualquer ordem dão o mesmo
# arquivo (cada um só reescreve o seu trecho).
#
# uso (de REPOS/gt3-godot): python tools/cenario/interlagos/setor7_perfil.py
#
# Decisões (vídeo = quadros chase_v2/onboard_v2 do atlas, folhas build/ref/interlagos/folhas/fase7_ini_*; satélite =
# build/interlagos/perfil/diferencas.md "Setor 7" e overlay_perfil/cima_setor7.jpg):
#   esq 1984–2014  como estava (escape verde da entrada da Ferradura, barreira ROLEX baixa até 2006)
#   esq 2016–2140  escape verde 5,8 m (satélite: zebra + escape mediana 6,0 m em s novo 2016–2153; antes 10,7; < 6 m para não pôr os cones automáticos de escape largo, que o LMU não tem) + faixa verde-água de
#                  1,5 m (LMU s 1990/2050: verde, faixa verde-azulada e grama até a barreira)
#   esq 2142–2178  verde estreitando de 5,8 para 1,5 m (LMU s 2150/2170; satélite sem escape a partir de ~2168)
#   esq 2180–2282  zebra (a física passou a ir até 2282: LMU chase s 2190–2270 e onboard s 2230/2270 com a zebra
#                  verde-amarela contínua até a Esse) + verde de 1 m (LMU s 2250/2270)
#   esq barreira   2008–2282 muro baixo com a placa DHL (`dhl`; LMU s 1990–2270, amarela com DHL vermelho, sem faixa em
#                  cima); alambrado só até 2084 (LMU s 2010: alambrado atrás); paredão alto com a faixa DHL de 2086 a 2276
#                  (`paredao`; LMU s 2070: arquibancada virada para a curva e o paredão começando à direita dela; s 2270
#                  ainda com o paredão)
#   dir 1984–1992  grama (LMU s 1990: a faixa começa logo à frente)
#   dir 1994–2062  faixa verde-água de 1,2 m + salsicha amarela 0,4 m, sem escape depois (LMU s 2010/2030/2050; satélite
#                  sem escape à direita em 2009–2173; antes faixa verde viva 0,65 m + escape verde 2,2 m)
#   dir 2064–2104  escape verde-água largo, sem salsicha, entre os dois ápices (LMU s 2070/2090; no satélite é o pé da
#                  antiga ligação pintada de verde-água que entra no miolo da Ferradura)
#   dir 2106–2164  faixa verde-água 1,2 m + salsicha (LMU s 2110/2130/2150; s 2170 já sem)
#   dir 2166–2282  grama (LMU s 2170–2270)
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from perfil_setor import K, aplicar, arvores, escape, folga, gravar, zebra  # noqa: E402

S0, S1 = 1984, 2282  # amostras do setor (inclusive; passo 2 m): a fatia anterior acaba em 1982, a seguinte começa em 2284


def rampa(s, a, b, va, vb):
    t = min(1.0, max(0.0, (s - a) / (b - a)))
    return va + (vb - va) * t


def faixa_salsicha():
    return [{'tipo': 'pintura', 'cor': 'agua', 'larg': 1.2}, {'tipo': 'salsicha', 'larg': 0.4}]


def regra(lado, s, i, fx):
    # zebra só onde a física tem (as fatias antigas tinham "zebra fisica" com kerb 0 em vários trechos)
    fx = [x for x in fx if x['tipo'] != 'zebra'] if K[lado][i] <= 0 else fx
    if K[lado][i] > 0 and not zebra(fx):
        fx = [{'tipo': 'zebra', 'larg': 'fisica'}] + fx
    if lado == 'esq':
        if s <= 2014:
            return fx
        if s <= 2140:
            ini = rampa(s, 2014, 2026, 3.4, 5.8)
            return escape(lado, i, fx, 'verde', ini, fora=('agua', 1.5))
        if s <= 2178:
            return escape(lado, i, fx, 'verde', rampa(s, 2140, 2162, 5.8, 1.5))
        return escape(lado, i, fx, 'verde', 1.0)
    if s <= 1992:
        return zebra(fx)
    if s <= 2062:
        return zebra(fx) + faixa_salsicha()
    if s <= 2104:
        larg = min(rampa(s, 2064, 2072, 1.6, 8.0), rampa(s, 2096, 2104, 8.0, 1.6))
        return escape(lado, i, fx, 'agua', larg)
    if s <= 2164:
        return zebra(fx) + faixa_salsicha()
    return zebra(fx)


def barreira(lado, s, i, b):
    b = dict(b)
    if lado == 'esq' and s >= 2008:
        b = {'tipo': 'wall', 'dist': 'fisica', 'banner': 'dhl'}
        if s <= 2084:
            b['alambrado'] = True
        if 2086 <= s <= 2276:
            b['paredao'] = True
    return b


aplicar(S0, S1, regra, barreira, rotulo='7')

# Árvores, Etapa A (§5): zonas por s e lado, d = metros além do muro da física; dens = fração que fica. Fontes: altura
# de copa do LiDAR (lidar.copa > 4 m, fração por faixa de d; tabela no setor-7.md) e o vídeo (LMU chase_v2).
ZONAS7 = [
    ('esq', 1983, 2090, 0, 70, 0.0, 'paddock, arquibancada virada para a curva e prédios atrás da barreira DHL (copa ≈ 0 até 70 m; LMU s 2010–2070)'),
    ('esq', 1983, 2090, 70, 200, 0.5, 'árvores ao fundo (copa 0,2–0,45 a 70–110 m)'),
    ('esq', 2090, 2190, 0, 70, 0.0, 'paredão e talude (copa ≈ 0 até 70 m; LMU s 2110–2170)'),
    ('esq', 2090, 2190, 70, 200, 0.6, 'mata no alto do morro (copa 0,3–0,6)'),
    ('esq', 2190, 2283, 0, 40, 0.0, 'paredão (copa 0,07–0,2 a 0–20 m é o próprio paredão/alambrado; LMU s 2190–2270)'),
    ('esq', 2190, 2283, 40, 200, 0.7, 'árvores no morro atrás do paredão (copa 0,2–0,6; LMU s 2230–2270)'),
    ('dir', 1983, 2283, 0, 200, 0.0, 'miolo da Ferradura: campo de grama seca (copa ≈ 0, 0,13 só em 2090–2140 a 7–40 m; LMU s 2010–2270)'),
]
arvores(1983, 2283, ZONAS7)
gravar()
