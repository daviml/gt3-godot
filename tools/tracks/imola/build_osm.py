# Arredores de Imola a partir do OpenStreetMap + alturas reais de prédios pelo DSM-DTM (DsmAgea2008 - Dtm1x1PST),
# nas coordenadas do jogo (x = leste, z = -norte, origem 44.3410 N, 11.7135 E):
#   buildings (contorno, altura medida/OSM, tipo), water, woods, grass, treeRows, pitLane,
#   walls (barrier=wall/retaining_wall), fences (barrier=fence), gravel, paved, roads, riverLine.
# uso (de REPOS/gt3-godot): python tools/tracks/imola/build_osm.py
import json
import os
import re
import numpy as np
from scipy.ndimage import map_coordinates

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'imola')
OUT = os.path.dirname(os.path.abspath(__file__))
LAT0, LON0 = 44.3410, 11.7135
ML = 111320.0
MO = ML * np.cos(np.radians(LAT0))
RE = 6378137.0


class Raster:
    def __init__(self, name: str):
        self.a = np.load(os.path.join(RAW, name + '.npy'))
        self.m = json.load(open(os.path.join(RAW, name + '.json')))

    def sample(self, x, z, order=1):
        lat = LAT0 - np.asarray(z) / ML
        lon = LON0 + np.asarray(x) / MO
        X = RE * np.radians(lon)
        Y = RE * np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))
        col = (X - self.m['x0']) / self.m['px'] - 0.5
        row = (self.m['y1'] - Y) / self.m['px'] - 0.5
        return map_coordinates(self.a, [row, col], order=order, mode='nearest')


xml = open(os.path.join(RAW, 'osm.xml'), encoding='utf8').read()
nodes = {}
for m in re.finditer(r'<node id="(\d+)"[^>]*lat="([-\d.]+)" lon="([-\d.]+)"', xml):
    nodes[m[1]] = [round((float(m[3]) - LON0) * MO, 1), round(-(float(m[2]) - LAT0) * ML, 1)]

tags_of = lambda body: dict(re.findall(r'<tag k="([^"]+)" v="([^"]*)"', body))
ways = {}
raceway_pts = []
for m in re.finditer(r'<way id="(\d+)"[^>]*>([\s\S]*?)</way>', xml):
    pts = [nodes[r] for r in re.findall(r'<nd ref="(\d+)"', m[2]) if r in nodes]
    t = tags_of(m[2])
    ways[m[1]] = (pts, t)
    if t.get('highway') == 'raceway' and t.get('name') not in ('Pit Lane', 'Variante Bassa'):
        raceway_pts.extend(pts)

dem = Raster('dem1m')
dsm = Raster('dsm2m')
if raceway_pts:
    rp = np.array(raceway_pts)
    chm_offset = float(np.median(dsm.sample(rp[:, 0], rp[:, 1]) - dem.sample(rp[:, 0], rp[:, 1])))
else:
    chm_offset = 5.77
print(f'DSM - DTM offset em pista aberta: {chm_offset:+.2f} m')


def chm_building_height(pts) -> float:
    arr = np.array(pts, dtype=np.float64)
    cx, cz = arr.mean(axis=0)
    sx = np.concatenate([arr[:, 0], [cx], (arr[:, 0] + cx) * 0.5])
    sz = np.concatenate([arr[:, 1], [cz], (arr[:, 1] + cz) * 0.5])
    dh = dsm.sample(sx, sz) - dem.sample(sx, sz) - chm_offset
    dh = dh[np.isfinite(dh)]
    if len(dh) == 0:
        return 0.0
    h = float(np.percentile(dh, 75))
    return h if 2.8 <= h <= 24.0 else 0.0


def area(p):
    a = 0.0
    for i in range(len(p)):
        x1, z1 = p[i]
        x2, z2 = p[(i + 1) % len(p)]
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

out = {
    'buildings': [],
    'water': [],
    'forest': [],
    'woods': [],
    'grass': [],
    'treeRows': [],
    'pitLane': [],
    'kart': [],
    'corners': [],
    'waterTower': None,
    'walls': [],
    'fences': [],
    'gravel': [],
    'paved': [],
    'roads': [],
    'riverLine': [],
}

for pts, t in items:
    if len(pts) < 2:
        continue
    btag = t.get('building') or t.get('building:part')
    if btag or t.get('leisure') == 'bleachers':
        if not closed(pts):
            continue
        r = ring(pts)
        a = area(r)
        if a < 8:
            continue
        kind = 'house'
        if btag == 'grandstand' or t.get('leisure') == 'bleachers':
            kind = 'grandstand'
        elif t.get('man_made') == 'storage_tank':
            kind = 'tank'
        elif btag == 'roof':
            kind = 'roof'
        elif a > 400 or btag in ('industrial', 'commercial', 'civic', 'public', 'apartments'):
            kind = 'big'
        h = 0.0
        try:
            h = float(re.sub(r'[^\d.]', '', t.get('height', '0').split(';')[0]) or 0)
        except ValueError:
            pass
        if not h and t.get('building:levels'):
            try:
                h = float(t['building:levels'].split(';')[0]) * 3.1
            except ValueError:
                pass
        if not h:
            h = chm_building_height(r)
        if not h:
            h = {'grandstand': 8.5, 'tank': 8.0, 'roof': 5.5, 'big': 8.0}.get(kind, 6.0)
        if kind == 'house':
            h = max(4.0, min(14.0, h))
        else:
            h = max(4.0, min(22.0, h))
        out['buildings'].append({'pts': r, 'h': round(h, 1), 'kind': kind, 'a': round(a)})
    elif t.get('man_made') == 'storage_tank' and closed(pts):
        r = ring(pts)
        out['buildings'].append({'pts': r, 'h': 8.0, 'kind': 'tank', 'a': round(area(r))})
    elif t.get('natural') == 'water' or t.get('water'):
        if closed(pts):
            out['water'].append(ring(pts))
    elif t.get('waterway') == 'river':
        out['riverLine'].append(pts)
    elif t.get('landuse') == 'forest' or t.get('natural') in ('wood', 'scrub'):
        if closed(pts):
            out['woods'].append(ring(pts))
    elif t.get('landuse') in ('grass', 'orchard', 'meadow') or t.get('leisure') in ('park', 'pitch', 'garden'):
        if closed(pts):
            out['grass'].append(ring(pts))
    elif t.get('natural') == 'tree_row':
        out['treeRows'].append(pts)
    elif t.get('natural') == 'sand' or (t.get('surface') in ('gravel', 'fine_gravel') and closed(pts) and not t.get('highway')):
        if closed(pts):
            out['gravel'].append(ring(pts))
    elif t.get('barrier') in ('wall', 'retaining_wall'):
        out['walls'].append(pts)
    elif t.get('barrier') == 'fence':
        out['fences'].append(pts)
    elif t.get('highway') == 'raceway' and re.search('pit', t.get('name', ''), re.I):
        out['pitLane'].append(pts)
    elif t.get('amenity') == 'parking' or 'area:highway' in t or (
        t.get('sport') == 'motor' and t.get('surface') in ('concrete', 'asphalt') and closed(pts) and not t.get('highway')
    ):
        if closed(pts):
            out['paved'].append(ring(pts))
    elif t.get('highway') in ('service', 'unclassified', 'track', 'residential', 'trunk', 'secondary', 'tertiary', 'path', 'footway'):
        out['roads'].append({'pts': pts, 'kind': t['highway']})

with open(os.path.join(OUT, 'imola-osm.json'), 'w', encoding='utf8') as f:
    json.dump(out, f)

kinds = {}
for b in out['buildings']:
    kinds[b['kind']] = kinds.get(b['kind'], 0) + 1
print(
    'prédios', len(out['buildings']), kinds,
    '| água', len(out['water']),
    '| mata', len(out['woods']),
    '| grama', len(out['grass']),
    '| brita', len(out['gravel']),
    '| muros', len(out['walls']),
    '| cercas', len(out['fences']),
    '| pavimentado', len(out['paved']),
    '| vias', len(out['roads']),
    '| pit', len(out['pitLane']),
)
