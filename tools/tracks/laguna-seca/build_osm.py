# Arredores de Laguna Seca a partir do OpenStreetMap, no mesmo formato de data/tracks/interlagos-osm.json do web
# (build-interlagos-osm.mjs), nas coordenadas do jogo (x = leste, z = -norte, mesma origem de laguna-seca.json):
#   buildings (contorno, altura, tipo), water, forest (vazio), grass, treeRows, pitLane, kart, corners, waterTower
# e campos extras de Laguna:
#   walls   linhas de barrier=wall (muros de concreto da pista)
#   gravel  áreas natural=sand / surface=gravel (caixas de brita)
#   paved   áreas asfaltadas/concretadas (paddock, estacionamentos: amenity=parking, area:highway)
#   roads   vias de serviço e acesso (highway=service/unclassified/track/residential), para faixas no terreno
# uso (de REPOS/gt3-godot): python tools/tracks/laguna-seca/build_osm.py
import json, os, re
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'laguna-seca')
OUT = os.path.dirname(os.path.abspath(__file__))
LAT0, LON0 = 36.5840, -121.7530
ML = 111320.0
MO = ML * np.cos(np.radians(LAT0))

xml = open(os.path.join(RAW, 'osm.xml'), encoding='utf8').read()
nodes = {}
for m in re.finditer(r'<node id="(\d+)"[^>]*lat="([-\d.]+)" lon="([-\d.]+)"', xml):
    nodes[m[1]] = [round((float(m[3]) - LON0) * MO, 1), round(-(float(m[2]) - LAT0) * ML, 1)]
tags_of = lambda body: dict(re.findall(r'<tag k="([^"]+)" v="([^"]*)"', body))
ways = {}
for m in re.finditer(r'<way id="(\d+)"[^>]*>([\s\S]*?)</way>', xml):
    pts = [nodes[r] for r in re.findall(r'<nd ref="(\d+)"', m[2]) if r in nodes]
    ways[m[1]] = (pts, tags_of(m[2]))


def area(p):
    a = 0.0
    for i in range(len(p)):
        x1, z1 = p[i]; x2, z2 = p[(i + 1) % len(p)]
        a += x1 * z2 - x2 * z1
    return abs(a) / 2


closed = lambda p: len(p) > 3 and p[0] == p[-1]
ring = lambda p: p[:-1] if closed(p) else p

items = list(ways.values())
for m in re.finditer(r'<relation id="\d+"[^>]*>([\s\S]*?)</relation>', xml):
    t = tags_of(m[1])
    for r in re.findall(r'<member type="way" ref="(\d+)" role="outer"', m[1]):
        if r in ways and closed(ways[r][0]):
            items.append((ways[r][0], t))

out = {'buildings': [], 'water': [], 'forest': [], 'woods': [], 'grass': [], 'treeRows': [], 'pitLane': [], 'kart': [],
       'corners': [], 'waterTower': None, 'walls': [], 'gravel': [], 'paved': [], 'roads': []}
for pts, t in items:
    if len(pts) < 2:
        continue
    if t.get('building') or t.get('building:part'):
        if not closed(pts):
            continue
        r = ring(pts); a = area(r)
        if a < 8:
            continue
        kind = 'house'
        if t.get('building') == 'grandstand' or t.get('leisure') == 'bleachers':
            kind = 'grandstand'
        elif t.get('man_made') == 'storage_tank':
            kind = 'tank'
        elif t.get('building') == 'roof':
            kind = 'roof'
        elif a > 400:
            kind = 'big'
        h = 0.0
        try:
            h = float(t.get('height', '0').split()[0])
        except ValueError:
            pass
        if not h and t.get('building:levels'):
            h = float(t['building:levels']) * 3.1
        if not h:
            # galpões sem altura no OSM: 7 m (o cenário do web transformaria em torres de 12–24 andares, coisa de
            # São Paulo; em Laguna são garagens, oficinas e depósitos térreos)
            h = {'grandstand': 7, 'tank': 8, 'roof': 6, 'big': 7}.get(kind, 0)
        out['buildings'].append({'pts': r, 'h': round(h, 1), 'kind': kind, 'a': round(a)})
    elif t.get('man_made') == 'storage_tank' and closed(pts):
        r = ring(pts)
        out['buildings'].append({'pts': r, 'h': 8, 'kind': 'tank', 'a': round(area(r))})
    elif t.get('natural') == 'water' or t.get('water'):
        if closed(pts):
            out['water'].append(ring(pts))
    elif t.get('landuse') == 'forest' or t.get('natural') in ('wood', 'scrub'):
        if closed(pts):
            # em 'woods', não em 'forest': o cenário do web enche 'forest' de árvores iguais em grade (pomar);
            # o de Laguna planta carvalhos irregulares nessas manchas (tools/cenario/laguna/trackView.ts)
            out['woods'].append(ring(pts))
    elif t.get('landuse') == 'grass' or t.get('leisure') in ('park', 'pitch', 'golf_course'):
        if closed(pts):
            out['grass'].append(ring(pts))
    elif t.get('natural') == 'tree_row':
        out['treeRows'].append(pts)
    elif t.get('natural') == 'sand' or (t.get('surface') == 'gravel' and closed(pts) and not t.get('highway')):
        if closed(pts):
            out['gravel'].append(ring(pts))
    elif t.get('barrier') == 'wall':
        out['walls'].append(pts)
    elif t.get('highway') == 'raceway' and re.search('pit', t.get('name', ''), re.I):
        out['pitLane'].append(pts)
    elif t.get('amenity') == 'parking' or 'area:highway' in t or (t.get('sport') == 'motor' and t.get('surface') in ('concrete', 'asphalt') and closed(pts) and not t.get('highway')):
        if closed(pts):
            out['paved'].append(ring(pts))
    elif t.get('highway') in ('service', 'unclassified', 'track', 'residential', 'trunk', 'path', 'footway'):
        out['roads'].append({'pts': pts, 'kind': t['highway']})

json.dump(out, open(os.path.join(OUT, 'laguna-seca-osm.json'), 'w'))
kinds = {}
for b in out['buildings']:
    kinds[b['kind']] = kinds.get(b['kind'], 0) + 1
print('prédios', len(out['buildings']), kinds, '| água', len(out['water']), '| mata', len(out['woods']),
      '| grama', len(out['grass']), '| brita', len(out['gravel']), '| muros', len(out['walls']),
      '| pavimentado', len(out['paved']), '| vias', len(out['roads']), '| pit', len(out['pitLane']))
