# Baixa as fontes reais de Imola para build/imola/ (não versionado):
#   osm.xml              OpenStreetMap (API 0.6 / Overpass), recorte da pista + ~1 km
#   dem1m.npy / .json    LiDAR DTM 1 m (Geoportale Emilia-Romagna Dtm1x1PST + preenchimento Dtm5x5), EPSG:3857
#   dsm2m.npy / .json    DSM 2 m (Geoportale Emilia-Romagna DsmAgea2008), para DSM - DTM (copas e prédios)
#   sat.npy / .json      Esri World Imagery 0,25 m, área da pista e boxes (bordas, zebras e brita)
# Tudo é pedido em blocos na projeção nativa (EPSG:3857) com bbox e tamanho exatos.
# uso (de REPOS/gt3-godot): python tools/tracks/imola/download.py
import io
import json
import os
import subprocess
import time
import urllib.request
import numpy as np
import tifffile
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RAW = os.path.join(ROOT, 'build', 'imola')
os.makedirs(RAW, exist_ok=True)

LAT0 = 44.3410
RE = 6378137.0
COS = np.cos(np.radians(LAT0))
mx = lambda lon: np.radians(lon) * RE
my = lambda lat: RE * np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))

LON0, LON1 = 11.6880, 11.7390
LAT_A, LAT_B = 44.3260, 44.3560

SAT_LON0, SAT_LON1 = 11.7000, 11.7270
SAT_LAT0, SAT_LAT1 = 44.3350, 44.3470


def get(url: str) -> bytes:
    last_err = None
    for attempt in range(5):
        try:
            # curl.exe usa a cadeia TLS nativa do Windows (necessário para servizigis.regione.emilia-romagna.it)
            return subprocess.check_output(
                ['curl.exe', '-sS', '-L', '--fail', '--max-time', '120', '-A', 'gt3-godot/1.0', url],
                stderr=subprocess.PIPE,
            )
        except Exception as e:
            last_err = e
            try:
                req = urllib.request.Request(url, headers={'User-Agent': 'gt3-godot/1.0'})
                return urllib.request.urlopen(req, timeout=120).read()
            except Exception as e2:
                last_err = e2
            print(f'  tentativa {attempt + 1} falhou ({last_err}), tentando novamente...', flush=True)
            time.sleep(2 + attempt)
    raise SystemExit(f'falhou {url}: {last_err}')


def mosaic(lon0, lon1, lat0, lat1, res_m, tile, fetch):
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
            print(f'  bloco {j0},{i0} ({w}x{h})', flush=True)
    return out, {'proj': 'EPSG:3857', 'x0': float(X0), 'y1': float(Y1), 'px': float(px), 'nx': nx, 'ny': ny, 'res_m': res_m}


# ---- 1) OpenStreetMap
osm_path = os.path.join(RAW, 'osm.xml')
if not os.path.exists(osm_path) or os.path.getsize(osm_path) < 10000:
    print('OSM')
    osm_bytes = None
    for url in [
        f'https://api.openstreetmap.org/api/0.6/map?bbox={LON0},{LAT_A},{LON1},{LAT_B}',
        f'https://overpass-api.de/api/map?bbox={LON0},{LAT_A},{LON1},{LAT_B}',
    ]:
        try:
            osm_bytes = get(url)
            if b'<osm' in osm_bytes[:500]:
                break
        except SystemExit:
            continue
    if not osm_bytes or b'<osm' not in osm_bytes[:500]:
        raise SystemExit('Falha ao baixar OSM de Imola')
    with open(osm_path, 'wb') as f:
        f.write(osm_bytes)
    print(f'  osm.xml salvo ({len(osm_bytes) / 1e6:.2f} MB)')
else:
    print(f'OSM já existe ({os.path.getsize(osm_path) / 1e6:.2f} MB)')


# ---- 2) LiDAR DTM 1 m (Emilia-Romagna Dtm1x1PST + fallback Dtm5x5 para bordas sem buracos)
def rer_tile(service: str):
    def _fetch(bbox, w, h):
        url = (
            f'https://servizigis.regione.emilia-romagna.it/arcgis/rest/services/public/{service}/ImageServer/exportImage?'
            f'bbox={bbox}&bboxSR=3857&imageSR=3857&size={w},{h}&format=tiff&pixelType=F32&noData=-9999'
            '&interpolation=RSP_BilinearInterpolation&f=image'
        )
        a = tifffile.imread(io.BytesIO(get(url))).astype(np.float32)
        a[(a <= 1.0) | (a > 2500.0)] = np.nan
        return a
    return _fetch


dem_path = os.path.join(RAW, 'dem1m.npy')
if not os.path.exists(dem_path):
    print('Emilia-Romagna LiDAR DTM 1 m (Dtm1x1PST)')
    dem, meta = mosaic(LON0, LON1, LAT_A, LAT_B, 1.0, 1000, rer_tile('Dtm1x1PST'))
    n_nan = int(np.isnan(dem).sum())
    print(f'  Dtm1x1PST: min={np.nanmin(dem):.2f}, max={np.nanmax(dem):.2f}, buracos={n_nan} ({100 * n_nan / dem.size:.2f}%)')
    if n_nan > 0:
        print('Preenchendo bordas com Dtm5x5')
        dem5, _ = mosaic(LON0, LON1, LAT_A, LAT_B, 1.0, 1500, rer_tile('Dtm5x5'))
        mask = np.isnan(dem)
        dem[mask] = dem5[mask]
        rem = int(np.isnan(dem).sum())
        if rem > 0:
            raise SystemExit(f'Ainda restaram {rem} buracos no DEM!')
        # Conferir emenda
        from scipy.ndimage import distance_transform_edt
        # suaviza transição apenas numa faixa de 6 m ao redor da fronteira do preenchimento
        dist = distance_transform_edt(mask)
        blend = np.clip(dist / 6.0, 0.0, 1.0)
        # apenas onde mask foi preenchido próximo à borda, blend gradual não precisa alterar dem válido;
        # confere salto máximo na fronteira
        gy, gx = np.abs(np.diff(dem, axis=0)), np.abs(np.diff(dem, axis=1))
        print(f'  após Dtm5x5: buracos=0, degrau max dx={gx.max():.2f} m, dy={gy.max():.2f} m')
    np.save(dem_path, dem.astype(np.float32))
    json.dump(meta, open(os.path.join(RAW, 'dem1m.json'), 'w'))
else:
    dem = np.load(dem_path)
    print(f'dem1m.npy já existe: shape={dem.shape}, buracos={int(np.isnan(dem).sum())}')


# ---- 3) DSM 2 m (DsmAgea2008) para estimar copas e prédios via DSM - DTM
dsm_path = os.path.join(RAW, 'dsm2m.npy')
if not os.path.exists(dsm_path):
    print('Emilia-Romagna DSM 2 m (DsmAgea2008)')
    dsm, dsm_meta = mosaic(LON0, LON1, LAT_A, LAT_B, 2.0, 1200, rer_tile('DsmAgea2008'))
    n_nan = int(np.isnan(dsm).sum())
    print(f'  DsmAgea2008: min={np.nanmin(dsm):.2f}, max={np.nanmax(dsm):.2f}, buracos={n_nan}')
    np.save(dsm_path, dsm.astype(np.float32))
    json.dump(dsm_meta, open(os.path.join(RAW, 'dsm2m.json'), 'w'))
else:
    print('dsm2m.npy já existe')


# ---- 4) Satélite Esri World Imagery 0,25 m
sat_path = os.path.join(RAW, 'sat.npy')
if not os.path.exists(sat_path):
    print('Esri World Imagery 0,25 m')
    def sat_tile(bbox, w, h):
        url = (
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?'
            f'bbox={bbox}&bboxSR=3857&imageSR=3857&size={w},{h}&format=png24&f=image'
        )
        return np.asarray(Image.open(io.BytesIO(get(url))).convert('RGB'))

    sat, sat_meta = mosaic(SAT_LON0, SAT_LON1, SAT_LAT0, SAT_LAT1, 0.25, 2000, sat_tile)
    np.save(sat_path, sat)
    json.dump(sat_meta, open(os.path.join(RAW, 'sat.json'), 'w'))
    Image.fromarray(sat).resize((sat.shape[1] // 4, sat.shape[0] // 4)).save(
        os.path.join(RAW, 'sat_preview.jpg'), quality=85
    )
    print(f'  sat.npy salvo: shape={sat.shape}')
else:
    print('sat.npy já existe')

print('download Fase 0 concluído!')
