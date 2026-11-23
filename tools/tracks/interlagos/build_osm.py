# OpenStreetMap de Interlagos para a Fase 2B (PLANO-INTERLAGOS-DETALHES.md): baixa (Overpass) só o que o traçado
# precisa — highway=raceway (volta, pit lane), barrier=* (muros, cercas) e areias/britas — e grava:
#   build/interlagos/osm/osm.xml               bruto (não versionado)
#   tools/tracks/interlagos/interlagos-osm.json  = o arquivo do jogo web (../gt3-time-attack/data/tracks/
#       interlagos-osm.json, que o cenário usa hoje: prédios, árvores, pit lane, nomes) COPIADO SEM MUDANÇA +
#       chaves novas: raceway (volta do OSM, 1 m), raceName (trechos com nome), walls (barrier=wall), fences
#       (barrier=fence), pitLaneOsm, finishLine. Nada do que já existia muda de lugar.
#
# Coordenadas do jogo: x = leste, z = sul, origem lat -23.7036, lon -46.6997 (igual ao web).
# uso (de REPOS/gt3-godot): python tools/tracks/interlagos/build_osm.py [--baixar]
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request

import numpy as np

sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'interlagos', 'osm')
OUT = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.abspath(os.path.join(ROOT, '..', 'gt3-time-attack', 'data', 'tracks', 'interlagos-osm.json'))
LAT0, LON0 = -23.7036, -46.6997
ML = 111320.0
MO = ML * math.cos(math.radians(LAT0))
BBOX = '-23.7085,-46.7030,-23.6950,-46.6915'
# trechos motor que não fazem parte do Grand Prix (variante do Bico de Pato e ligação antiga perto do Café)
FORA_DA_VOLTA = {'638329117', '189535481'}
XML = os.path.join(RAW, 'osm.xml')


def baixar():
    os.makedirs(RAW, exist_ok=True)
    q = (f'[out:xml][timeout:90];(way["highway"="raceway"]({BBOX});way["barrier"]({BBOX});'
         f'way["natural"="sand"]({BBOX});way["surface"="gravel"]({BBOX}););(._;>;);out body;')
    req = urllib.request.Request('https://overpass-api.de/api/interpreter',
                                 data=urllib.parse.urlencode({'data': q}).encode(),
                                 headers={'User-Agent': 'gt3-track-tools'})
    open(XML, 'wb').write(urllib.request.urlopen(req, timeout=180).read())


def le():
    xml = open(XML, encoding='utf8').read()
    nodes = {m[0]: (float(m[1]), float(m[2])) for m in
             re.findall(r'<node id="(\d+)"[^>]*lat="([-\d.]+)" lon="([-\d.]+)"', xml)}
    xy = lambda n: [round((nodes[n][1] - LON0) * MO, 2), round(-(nodes[n][0] - LAT0) * ML, 2)]
    tags_nos = {}
    for m in re.finditer(r'<node id="(\d+)"[^>]*?>([\s\S]*?)</node>', xml):
        tags_nos[m[1]] = dict(re.findall(r'<tag k="([^"]+)" v="([^"]*)"', m[2]))
    ways = []
    for m in re.finditer(r'<way id="(\d+)"[^>]*>([\s\S]*?)</way>', xml):
        t = dict(re.findall(r'<tag k="([^"]+)" v="([^"]*)"', m[2]))
        nd = [r for r in re.findall(r'<nd ref="(\d+)"', m[2]) if r in nodes]
        ways.append((m[1], t, nd))
    return nodes, xy, tags_nos, ways


def volta(ways):
    """encadeia os trechos highway=raceway sport=motor (sem pit lane) numa volta fechada, no sentido do OSM."""
    gp = {w: (t, nd) for w, t, nd in ways if t.get('highway') == 'raceway' and t.get('sport') == 'motor'
          and t.get('name') != 'Pit Lane' and w not in FORA_DA_VOLTA}
    by = {nd[0]: w for w, (t, nd) in gp.items()}
    k0 = '131439569'  # S do Senna (primeiro trecho depois da reta)
    k, seq = k0, []
    while True:
        seq.append(k)
        k = by[gp[k][1][-1]]
        if k == k0:
            break
    assert len(seq) == len(gp), f'volta do OSM não fecha ({len(seq)} de {len(gp)} trechos)'
    return seq, gp


if __name__ == '__main__':
    if '--baixar' in sys.argv or not os.path.exists(XML):
        baixar()
    nodes, xy, tags_nos, ways = le()
    seq, gp = volta(ways)
    loop, nomes = [], []
    for w in seq:
        t, nd = gp[w]
        a = len(loop)
        loop += nd[:-1]
        if t.get('name'):
            nomes.append({'name': t['name'], 'i0': a, 'i1': len(loop)})
    P = np.array([xy(n) for n in loop])
    seg = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    L = float(s[-1])
    t1 = np.arange(0, L, 1.0)
    Q = np.vstack([P, P[:1]])
    P1 = np.stack([np.interp(t1, s, Q[:, 0]), np.interp(t1, s, Q[:, 1])], 1)
    out = json.load(open(WEB, encoding='utf-8'))
    out['raceway'] = [[round(float(x), 2), round(float(z), 2)] for x, z in P1]
    out['raceName'] = [{'name': c['name'], 's0': round(float(s[c['i0']]), 1), 's1': round(float(s[c['i1']]), 1)}
                       for c in nomes]
    out['walls'] = [[xy(n) for n in nd] for w, t, nd in ways if t.get('barrier') == 'wall']
    out['fences'] = [[xy(n) for n in nd] for w, t, nd in ways if t.get('barrier') == 'fence']
    out['pitLaneOsm'] = [[xy(n) for n in nd] for w, t, nd in ways
                         if t.get('highway') == 'raceway' and t.get('name') == 'Pit Lane' and t.get('sport') == 'motor']
    out['finishLine'] = [xy(n) for n, t in tags_nos.items() if t.get('name') == 'Finish Line']
    json.dump(out, open(os.path.join(OUT, 'interlagos-osm.json'), 'w', encoding='utf-8'), ensure_ascii=False,
              separators=(',', ':'))
    print(f'OSM: volta {L:.1f} m ({len(seq)} trechos, {len(P)} nós), muros {len(out["walls"])}, cercas '
          f'{len(out["fences"])}, pit lane {len(out["pitLaneOsm"])}, linha de chegada {out["finishLine"]}')
