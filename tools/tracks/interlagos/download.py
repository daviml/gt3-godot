# Baixa os tiles do satélite Esri World Imagery (z19, ~0,27 m/px em Interlagos) que cobrem a volta inteira e a
# pit lane com margem de ~80 m, para build/interlagos/tiles19/<x>_<y>.jpg (não versionado; mesma convenção dos
# tiles da Fase 1). Só baixa o que falta. Monta também build/interlagos/sat19.npy + sat19.json (mosaico RGB e
# georreferência em pixels globais Web Mercator z19) para o build_perfil.py.
#
# Georreferência da pista (igual a gt3-time-attack/scripts/ref-lib.ts): origem lat -23.7036, lon -46.6997;
#   x = (lon - lon0) * 111320 * cos(lat0),  z = -(lat - lat0) * 111320   (z positivo para o sul)
#
# uso (de REPOS/gt3-godot): python tools/tracks/interlagos/download.py
import json
import math
import os
import time
import urllib.request

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'interlagos')
TILES = os.path.join(RAW, 'tiles19')
os.makedirs(TILES, exist_ok=True)

LAT0, LON0 = -23.7036, -46.6997
ML = 111320.0
MO = ML * math.cos(math.radians(LAT0))
Z = 19
N = 2 ** Z
MARGEM = 80.0
URL = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
UA = 'Mozilla/5.0'


def local_to_tile(x, z):
    """local (m) -> coordenada de tile fracionária z19 (Web Mercator)."""
    lat = LAT0 - np.asarray(z) / ML
    lon = LON0 + np.asarray(x) / MO
    tx = (lon + 180.0) / 360.0 * N
    lr = np.radians(lat)
    ty = (1.0 - np.log(np.tan(lr) + 1.0 / np.cos(lr)) / math.pi) / 2.0 * N
    return tx, ty


def pontos():
    t = json.load(open(os.path.join(ROOT, 'data', 'track', 'track.json')))
    S = np.array(t['s']).reshape(t['n'], 16)
    pts = [S[:, [0, 2]]]
    osm = json.load(open(os.path.join(ROOT, '..', 'gt3-time-attack', 'data', 'tracks', 'interlagos-osm.json')))
    for pl in osm.get('pitLane', []):
        p = np.asarray(pl, float)
        # densifica a cada 5 m
        seg = []
        for a, b in zip(p[:-1], p[1:]):
            k = max(1, int(np.linalg.norm(b - a) / 5))
            seg.append(a + (b - a) * np.linspace(0, 1, k, endpoint=False)[:, None])
        seg.append(p[-1:])
        pts.append(np.vstack(seg))
    return np.vstack(pts)


def tiles_necessarios():
    P = pontos()
    need = set()
    # disco de raio MARGEM em volta de cada ponto: amostra um anel de deslocamentos
    off = [(dx, dz) for dx in np.arange(-MARGEM, MARGEM + 1, 20) for dz in np.arange(-MARGEM, MARGEM + 1, 20)
           if dx * dx + dz * dz <= (MARGEM + 10) ** 2]
    for dx, dz in off:
        tx, ty = local_to_tile(P[:, 0] + dx, P[:, 1] + dz)
        for a, b in zip(np.floor(tx).astype(int), np.floor(ty).astype(int)):
            need.add((int(a), int(b)))
    return sorted(need)


def baixar(x, y):
    f = os.path.join(TILES, f'{x}_{y}.jpg')
    if os.path.exists(f) and os.path.getsize(f) > 1000:
        return False
    url = URL.format(z=Z, x=x, y=y)
    for tent in range(5):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            data = urllib.request.urlopen(req, timeout=60).read()
            Image.open(__import__('io').BytesIO(data)).verify()
            with open(f, 'wb') as fh:
                fh.write(data)
            return True
        except Exception as e:  # noqa: BLE001
            print(f'  {x}_{y}: tentativa {tent + 1} falhou ({e})', flush=True)
            time.sleep(2 + tent)
    raise SystemExit(f'falhou tile {x}_{y}')


def main():
    need = tiles_necessarios()
    xs = [a for a, _ in need]
    ys = [b for _, b in need]
    print(f'{len(need)} tiles necessários (x {min(xs)}..{max(xs)}, y {min(ys)}..{max(ys)})')
    novos = 0
    for i, (x, y) in enumerate(need):
        if baixar(x, y):
            novos += 1
            time.sleep(0.05)
        if (i + 1) % 50 == 0:
            print(f'  {i + 1}/{len(need)}', flush=True)
    print(f'{novos} baixados agora, {len(need) - novos} já existiam')

    # mosaico (tiles fora da lista ficam pretos e marcados como sem dado)
    x0, y0 = min(xs), min(ys)
    W, H = (max(xs) - x0 + 1) * 256, (max(ys) - y0 + 1) * 256
    mos = np.zeros((H, W, 3), np.uint8)
    for x, y in need:
        im = np.asarray(Image.open(os.path.join(TILES, f'{x}_{y}.jpg')).convert('RGB'))
        mos[(y - y0) * 256:(y - y0 + 1) * 256, (x - x0) * 256:(x - x0 + 1) * 256] = im
    np.save(os.path.join(RAW, 'sat19.npy'), mos)
    meta = {'z': Z, 'tx0': x0, 'ty0': y0, 'w': W, 'h': H, 'lat0': LAT0, 'lon0': LON0,
            'tiles': [f'{x}_{y}' for x, y in need]}
    json.dump(meta, open(os.path.join(RAW, 'sat19.json'), 'w'))
    Image.fromarray(mos).resize((W // 4, H // 4)).save(os.path.join(RAW, 'sat19_preview.jpg'), quality=85)
    print(f'mosaico {W}x{H} px salvo em build/interlagos/sat19.npy')


if __name__ == '__main__':
    main()
