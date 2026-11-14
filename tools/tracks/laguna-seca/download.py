# Baixa as fontes reais de Laguna Seca para build/laguna-seca/ (não versionado; ~200 MB):
#   osm.xml              OpenStreetMap (API 0.6), recorte da pista + ~1 km
#   dem1m.npy / .json    USGS 3DEP 1 m (LiDAR, terreno nu), mesmo recorte, grade em Web Mercator
#   sat.npy / .json      Esri World Imagery 0,25 m, só a área da pista (para medir bordas do asfalto)
# Os serviços cortam pedidos grandes (502) e, pedidos em graus, desalinham os blocos: tudo é pedido em blocos na
# projeção nativa (EPSG:3857) com bbox e tamanho exatos.
# uso (de REPOS/gt3-godot): python tools/tracks/laguna-seca/download.py   (precisa de numpy, tifffile, imagecodecs, pillow)
import io, json, os, time, urllib.request
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'laguna-seca')
os.makedirs(RAW, exist_ok=True)
RE = 6378137.0
mx = lambda lon: np.radians(lon) * RE
my = lambda lat: RE * np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))
COS = np.cos(np.radians(36.584))


def get(url):
    for _ in range(5):
        try:
            return urllib.request.urlopen(url, timeout=120).read()
        except Exception as e:
            print('  de novo:', e)
            time.sleep(3)
    raise SystemExit('falhou ' + url)


def mosaic(lon0, lon1, lat0, lat1, res_m, tile, fetch, shape_extra=()):
    px = res_m / COS
    X0, X1, Y0, Y1 = mx(lon0), mx(lon1), my(lat0), my(lat1)
    nx, ny = int(round((X1 - X0) / px)), int(round((Y1 - Y0) / px))
    out = None
    for j0 in range(0, ny, tile):
        for i0 in range(0, nx, tile):
            w, h = min(tile, nx - i0), min(tile, ny - j0)
            bbox = f'{X0 + i0 * px:.3f},{Y1 - (j0 + h) * px:.3f},{X0 + (i0 + w) * px:.3f},{Y1 - j0 * px:.3f}'
            arr = fetch(bbox, w, h)
            if out is None:
                out = np.zeros((ny, nx) + arr.shape[2:], arr.dtype)
            out[j0:j0 + h, i0:i0 + w] = arr[:h, :w]
            print(f'  bloco {j0},{i0}', flush=True)
    return out, {'proj': 'EPSG:3857', 'x0': X0, 'y1': Y1, 'px': px, 'nx': nx, 'ny': ny, 'res_m': res_m}


# ---- OpenStreetMap
print('OSM')
open(os.path.join(RAW, 'osm.xml'), 'wb').write(
    get('https://api.openstreetmap.org/api/0.6/map?bbox=-121.7700,36.5700,-121.7370,36.5980'))

# ---- LiDAR 1 m
print('USGS 3DEP 1 m')
import tifffile


def dem_tile(bbox, w, h):
    url = ('https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage?'
           f'bbox={bbox}&bboxSR=3857&imageSR=3857&size={w},{h}&format=tiff&pixelType=F32'
           '&interpolation=RSP_BilinearInterpolation&f=image')
    a = tifffile.imread(io.BytesIO(get(url))).astype(np.float32)
    a[a < -1000] = np.nan
    return a


dem, meta = mosaic(-121.7700, -121.7370, 36.5700, 36.5980, 1.0, 800, dem_tile)
np.save(os.path.join(RAW, 'dem1m.npy'), dem)
json.dump(meta, open(os.path.join(RAW, 'dem1m.json'), 'w'))
print('  altitude', np.nanmin(dem), '..', np.nanmax(dem), 'buracos', int(np.isnan(dem).sum()))

# ---- foto de satélite 0,25 m
print('Esri World Imagery 0,25 m')
from PIL import Image


def sat_tile(bbox, w, h):
    url = ('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?'
           f'bbox={bbox}&bboxSR=3857&imageSR=3857&size={w},{h}&format=png24&f=image')
    return np.asarray(Image.open(io.BytesIO(get(url))).convert('RGB'))


sat, meta = mosaic(-121.7600, -121.7470, 36.5785, 36.5900, 0.25, 2000, sat_tile)
np.save(os.path.join(RAW, 'sat.npy'), sat)
json.dump(meta, open(os.path.join(RAW, 'sat.json'), 'w'))
Image.fromarray(sat).resize((sat.shape[1] // 4, sat.shape[0] // 4)).save(os.path.join(RAW, 'sat_preview.jpg'), quality=85)
print('ok')
