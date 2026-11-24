# Fase 6 (PLANO-INTERLAGOS-DETALHES.md) — Descida do Lago + subida: reescreve as fatias do perfil lateral
# (data/track/visual_profile.json) entre s 1369 e 1982 (s novo; o plano diz 1362–1976, que é o s antigo), a partir da
# ficha build/ref/interlagos/fichas/setor-6.md. Fora do setor o arquivo não muda. Idempotente (larguras limitadas pelo
# muro da física atual: rodar de novo depois de mudar a física).
#
# uso (de REPOS/gt3-godot): python tools/cenario/interlagos/setor6_perfil.py
#
# Decisões (vídeo = quadros chase_v2/onboard_v2 do atlas, folhas build/ref/interlagos/folhas/fase6_ini_*; satélite =
# Esri z19 desenrolado, build/interlagos/fase6/sat_setor6.jpg e agua.py/azul.py):
#   esq 1369–1488  zebra + faixa verde-água de 0,6 m + grama (LMU s 1390/1410/1430); barreira: guard-rail (física a
#                  borda + 9 m: grama larga até o guard-rail, LMU s 1410/1430)
#   esq 1490–1658  zebra (física desde ~1533) + escape verde até a barreira azul DUPLA Goodyear ("tecpro2", física a
#                  borda + 2,6 m; LMU s 1490–1640: zebra + ~1 m de verde e a barreira)
#   esq 1660–1802  grama até a barreira azul simples Goodyear sem faixa amarela (LMU s 1670–1790); fim com ponteira
#                  na física (~1800)
#   esq 1804–1838  grama (LMU s 1820)
#   esq 1840–1982  escape verde-água largo: 8 m (1852–1900) → 10 m (1915+, cortado no muro) (LMU s 1850/1890/1930/
#                  1970, folha final: 5 m ficava estreito; satélite: faixa clara até borda + ~10 m em 1910–1950)
#   dir 1369–1438  sem escape (satélite: grama/sem pintura; LMU s 1390–1430)
#   dir 1440–1528  escape verde vivo até o muro (LMU s 1460/1490/1510; satélite: pintura até borda + 20–33 m)
#   dir 1530–1720  escape verde-água até o muro (LMU s 1550–1730: verde-azulado; zebra da subida mantida)
#   dir 1722–1760  verde-água estreitando até 3 m (satélite: pintura 7 → 3 m em 1730–1750; LMU s 1760)
#   dir 1762–1832  faixa verde-água de 2 m (LMU s 1790/1820)
#   dir 1834–1982  grama (LMU s 1850–1970)
#   barreiras azuis simples ("tecpro") do setor: sem a faixa amarela DHL em cima (topo: false; LMU s 1490–1790)
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from perfil_setor import K, aplicar, arvores, escape, folga, gravar, zebra  # noqa: E402

S0, S1 = 1370, 1982  # amostras do setor (inclusive; passo 2 m): a fatia anterior acaba em 1368, a seguinte começa em 1984


def rampa(s, a, b, va, vb):
    t = min(1.0, max(0.0, (s - a) / (b - a)))
    return va + (vb - va) * t


def regra(lado, s, i, fx):
    # zebra da física onde a fatia antiga não tinha a faixa (a Fase 6 mudou a zebra dir do Lago para 1478–1527)
    if K[lado][i] > 0 and not zebra(fx):
        fx = [{'tipo': 'zebra', 'larg': 'fisica'}] + fx
    if lado == 'esq':
        if s <= 1488:
            return zebra(fx) + [{'tipo': 'escape', 'cor': 'agua', 'larg': round(min(0.6, folga(lado, i, not zebra(fx))), 3)}]
        if s <= 1658:
            return escape(lado, i, fx, 'verde', 30.0)
        if s <= 1838:
            return zebra(fx)
        larg = rampa(s, 1840, 1852, 0.5, 8.0) if s < 1900 else rampa(s, 1900, 1915, 8.0, 10.0)
        return escape(lado, i, fx, 'agua', larg)
    if s <= 1438:
        return zebra(fx)
    if s <= 1528:
        return escape(lado, i, fx, 'verde', 40.0)
    if s <= 1720:
        return escape(lado, i, fx, 'agua', 40.0)
    if s <= 1760:
        return escape(lado, i, fx, 'agua', rampa(s, 1720, 1746, min(20.0, folga(lado, i, not zebra(fx))), 3.0))
    if s <= 1832:
        return escape(lado, i, fx, 'agua', 2.0)
    return zebra(fx)


def barreira(lado, s, i, b):
    b = dict(b)
    if lado == 'esq':
        if s <= 1488:
            b = {'tipo': 'rail', 'dist': 'fisica'}
        elif s <= 1658:
            b = {'tipo': 'tecpro2', 'dist': 'fisica'}
        elif s <= 1802:
            b = {'tipo': 'tecpro', 'dist': 'fisica'}
    if b['tipo'] == 'tecpro':
        b['topo'] = False
    return b


aplicar(S0, S1, regra, barreira, rotulo='6')

# Árvores, Etapa A (§5): zonas por s e lado, d = metros além do muro da física; dens = fração que fica. Fontes: altura
# de copa do LiDAR (lidar.copa > 4 m, fração por faixa de d; tabela no setor-6.md) e o vídeo (LMU chase_v2).
ZONAS6 = [
    ('esq', 1369, 1490, 0, 40, 0.0, 'grama até o guard-rail e a estrada do lago (copa 0 até 40 m; LMU s 1390–1460)'),
    ('esq', 1369, 1490, 40, 200, 0.6, 'mata ao fundo (copa 0,2–0,55 a 40–160 m)'),
    ('esq', 1490, 1660, 0, 40, 0.0, 'talude gramado atrás da Goodyear dupla (copa ≈ 0 até 40 m; LMU s 1550–1640)'),
    ('esq', 1490, 1660, 40, 200, 0.4, 'árvores esparsas (copa 0,1–0,3)'),
    ('esq', 1660, 1800, 0, 70, 0.0, 'talude gramado com outdoor Goodyear e carros (copa ≈ 0; LMU s 1670–1760)'),
    ('esq', 1660, 1800, 70, 200, 0.4, 'árvores esparsas no alto (copa 0,03–0,4)'),
    ('esq', 1800, 1983, 0, 70, 0.0, 'estrada de serviço, talude e arquibancadas/tendas (copa ≈ 0; LMU s 1790–1970)'),
    ('esq', 1800, 1983, 70, 200, 0.4, 'árvores ao fundo (copa 0,1–0,6)'),
    ('dir', 1369, 1440, 0, 40, 0.0, 'grama e alambrado (copa ≈ 0; LMU s 1370–1430)'),
    ('dir', 1369, 1440, 40, 200, 0.5, 'árvores ao fundo (copa 0,13–0,33)'),
    ('dir', 1440, 1700, 0, 40, 0.0, 'escape largo e o lago (copa ≈ 0; LMU s 1460–1640)'),
    ('dir', 1440, 1700, 40, 200, 0.4, 'margem do lago e morro (copa 0,1–0,18)'),
    ('dir', 1700, 1800, 0, 40, 0.0, 'campo aberto (copa 0,1; LMU s 1700–1790)'),
    ('dir', 1700, 1800, 40, 200, 0.3, 'árvores esparsas'),
    ('dir', 1880, 1983, 0, 70, 0.0, 'grama seca até a Ferradura (copa ≈ 0; LMU s 1890–1970)'),
    ('dir', 1880, 1983, 70, 200, 0.4, 'árvores esparsas ao fundo'),
    # dir 1800–1880: mata do LiDAR (copa 0,4–0,5 a 0–20 m) fica como estava
]
arvores(1369, 1983, ZONAS6)

# Âncora do sorteio da mata (arvores.ancora, ./arvoresSetor.ts): a Fase 6 moveu o muro da física (esq 1370–1680, dir
# 1418–1708); a âncora fica no muro de antes, senão os capões sorteados a partir dessas amostras andam com o muro e
# caem perto da Reta Oposta e do Mergulho (fora do setor). O muro de antes tem de ser o EXATO que o gerador montava
# (o track.json arredonda a 1 cm, e 5 mm já mudam a semente por posição das árvores): build/interlagos/fase6/
# ancora_exata.json, gerado por build/interlagos/fase6/ancora.ts (montaPista no interlagos.json de antes da Fase 6).
# Sem o arquivo, mantém a âncora que já está no perfil.
ANC = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'build', 'interlagos', 'fase6', 'ancora_exata.json')
# (Fase 5: arvores.ancora virou uma lista de trechos por lado; perfil_setor.ancora troca só o trecho deste setor)
if os.path.exists(ANC):
    import json

    from perfil_setor import ancora  # noqa: E402
    ancora(json.load(open(ANC, encoding='utf-8')))
gravar()
