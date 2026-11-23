# Baixa e rasteriza o LiDAR da Prefeitura de São Paulo (GeoSampa, levantamento a laser 2017, ~10 pts/m²,
# SIRGAS 2000 / UTM 23S = EPSG:31983) para Interlagos: pista + ~1 km em volta.
#
# Fontes (públicas, sem conta):
#   índice das folhas 1:1000  WFS GeoSampa geoportal:quadricula_folha_mds (levantamento 2017)
#                             https://wms.geosampa.prefeitura.sp.gov.br/geoserver/geoportal/ows
#   nuvens LAZ                AWS Open Data "PMSP LiDAR Point Cloud" (mantido pelo GeoSampa), bucket público
#                             s3://laz-m3dc-pmsp/MDS_color_<folha>.laz  (sa-east-1, sem credencial)
#                             https://registry.opendata.aws/pmsp-lidar/
# Os LAZ "MDS_color" têm todos os retornos com classificação; o terreno nu sai dos pontos classe 2 (solo).
#
# Saída em build/interlagos/lidar/ (fora do git):
#   raw/indice_2017.geojson, raw/laz/MDS_color_<folha>.laz     brutos (dados não confiáveis: só lidos como dados)
#   blocos.json                                               extensão UTM e classes de cada folha
#   mdt.npy/.json (0,5 m), mdt_preenchido.npy, mds.npy/.json (1 m), copa.npy/.json (1 m)
# Depois: python tools/tracks/interlagos/lidar.py --conferir   (conferências, gráfico e interlagos-terrain.json)
#
# Requer, para rasterizar: laspy + lazrs (pip install "laspy[lazrs]"). O download funciona sem eles.
# uso (de REPOS/gt3-godot): python tools/tracks/interlagos/download_lidar.py [--so-baixar]
import json
import os
import subprocess
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lidar  # noqa: E402  (conversões jogo <-> UTM)

ROOT = lidar.ROOT
OUT = lidar.OUT
RAW = os.path.join(OUT, 'raw')
LAZ = os.path.join(RAW, 'laz')
os.makedirs(LAZ, exist_ok=True)
UA = 'gt3-godot/1.0'

# área em coordenadas do jogo: linha central atual x -94..574, z -734..315 (data/track/track.json) + ~1 km
AX0, AX1, AZ0, AZ1 = -1100.0, 1580.0, -1740.0, 1320.0
PX_MDT, PX_MDS = 0.5, 1.0
WFS = ('https://wms.geosampa.prefeitura.sp.gov.br/geoserver/geoportal/ows?service=WFS&version=1.0.0'
       '&request=GetFeature&typeName=geoportal:quadricula_folha_mds&outputFormat=application/json'
       '&srsName=EPSG:4326&bbox={lon0},{lat0},{lon1},{lat1},EPSG:4326')
S3 = 'https://laz-m3dc-pmsp.s3.sa-east-1.amazonaws.com/MDS_color_{cod}.laz'


def baixar(url, dest=None, tentativas=5):
    err = None
    for k in range(tentativas):
        try:
            cmd = ['curl.exe', '-sS', '-L', '--fail', '--max-time', '900', '-A', UA, url]
            if dest:
                subprocess.check_call(cmd + ['-o', dest + '.part'])
                os.replace(dest + '.part', dest)
                return None
            return subprocess.check_output(cmd)
        except Exception as e:
            err = e
            print(f'  tentativa {k + 1} falhou ({e})', flush=True)
            time.sleep(2 + 2 * k)
    raise SystemExit(f'falhou {url}: {err}')


def tamanho_remoto(url):
    h = subprocess.check_output(['curl.exe', '-sS', '-I', '--max-time', '60', '-A', UA, url]).decode('latin1')
    for ln in h.splitlines():
        if ln.lower().startswith('content-length:'):
            return int(ln.split(':')[1])
    return -1


# ---- 1) índice das folhas
lat_a, lon_a = lidar.jogo_para_ll(AX0, AZ1)
lat_b, lon_b = lidar.jogo_para_ll(AX1, AZ0)
idx_path = os.path.join(RAW, 'indice_2017.geojson')
if not os.path.exists(idx_path):
    print('índice das folhas (WFS GeoSampa)')
    b = baixar(WFS.format(lon0=f'{lon_a:.5f}', lat0=f'{lat_a:.5f}', lon1=f'{lon_b:.5f}', lat1=f'{lat_b:.5f}'))
    open(idx_path, 'wb').write(b)
idx = json.load(open(idx_path, encoding='utf8'))
folhas = sorted({str(f['properties']['cd_quadricula']) for f in idx['features']})
for c in folhas:  # o código vira nome de arquivo e URL: aceita só o formato conhecido 0000-000
    if not (len(c) == 8 and c[4] == '-' and (c[:4] + c[5:]).isdigit()):
        raise SystemExit(f'código de folha inesperado: {c!r}')
print(f'{len(folhas)} folhas: {" ".join(folhas)}')

# ---- 2) LAZ
for c in folhas:
    url = S3.format(cod=c)
    dest = os.path.join(LAZ, f'MDS_color_{c}.laz')
    tam = tamanho_remoto(url)
    if os.path.exists(dest) and os.path.getsize(dest) == tam:
        continue
    print(f'  baixando {c} ({tam / 1e6:.1f} MB)', flush=True)
    baixar(url, dest)
print('LAZ ok:', sum(os.path.getsize(os.path.join(LAZ, f)) for f in os.listdir(LAZ) if f.endswith('.laz')) / 1e6, 'MB')
if '--so-baixar' in sys.argv:
    raise SystemExit(0)

# ---- 3) rasterização numa grade UTM única (sem emendas por construção; conferidas em lidar.py)
try:
    import laspy
except ImportError:
    raise SystemExit('falta laspy + lazrs para ler LAZ: pip install "laspy[lazrs]"')
from scipy.ndimage import gaussian_filter

cE, cN = lidar.jogo_para_utm(np.array([AX0, AX1, AX0, AX1]), np.array([AZ0, AZ0, AZ1, AZ1]))
E0 = np.floor(cE.min() / 2) * 2
E1 = np.ceil(cE.max() / 2) * 2
N0 = np.floor(cN.min() / 2) * 2
N1 = np.ceil(cN.max() / 2) * 2
nx, ny = int(round((E1 - E0) / PX_MDT)), int(round((N1 - N0) / PX_MDT))
nx2, ny2 = nx // 2, ny // 2
print(f'grade UTM E {E0:.0f}..{E1:.0f}, N {N0:.0f}..{N1:.0f}: MDT {nx}x{ny} @ {PX_MDT} m, MDS {nx2}x{ny2} @ {PX_MDS} m')
soma = np.zeros(ny * nx, np.float64)
cont = np.zeros(ny * nx, np.int32)
smax = np.full(ny2 * nx2, -np.inf, np.float64)
blocos = []
for c in folhas:
    f = laspy.read(os.path.join(LAZ, f'MDS_color_{c}.laz'))
    x, y, zz = np.asarray(f.x), np.asarray(f.y), np.asarray(f.z)
    cl = np.asarray(f.classification)
    hist = {int(k): int(v) for k, v in zip(*np.unique(cl, return_counts=True))}
    blocos.append({'cod': c, 'n': int(len(x)), 'minx': float(x.min()), 'maxx': float(x.max()),
                   'miny': float(y.min()), 'maxy': float(y.max()), 'zmin': float(zz.min()), 'zmax': float(zz.max()),
                   'classes': hist})
    print(f'  {c}: {len(x)} pts, classes {hist}', flush=True)
    # MDT: média dos pontos de solo (classe 2) por célula de 0,5 m
    g = cl == 2
    col = np.floor((x[g] - E0) / PX_MDT).astype(np.int64)
    row = np.floor((N1 - y[g]) / PX_MDT).astype(np.int64)
    ok = (col >= 0) & (col < nx) & (row >= 0) & (row < ny)
    k = row[ok] * nx + col[ok]
    soma += np.bincount(k, zz[g][ok], minlength=ny * nx)
    cont += np.bincount(k, minlength=ny * nx).astype(np.int32)
    # MDS: maior ponto por célula de 1 m, sem ruído (classes 7 e 18)
    v = (cl != 7) & (cl != 18)
    col = np.floor((x[v] - E0) / PX_MDS).astype(np.int64)
    row = np.floor((N1 - y[v]) / PX_MDS).astype(np.int64)
    ok = (col >= 0) & (col < nx2) & (row >= 0) & (row < ny2)
    np.maximum.at(smax, row[ok] * nx2 + col[ok], zz[v][ok])
    del f, x, y, zz, cl

mdt = np.where(cont > 0, soma / np.maximum(cont, 1), np.nan).reshape(ny, nx).astype(np.float32)
buraco = np.isnan(mdt)
print(f'MDT: {100 * buraco.mean():.2f}% células sem solo (prédios, água, mata densa, fora da cobertura)')


def preencher(a):
    """Preenche NaN por pirâmide (média das células válidas, nível a nível) e suaviza só o preenchido."""
    if not np.isnan(a).any():
        return a
    h, w = a.shape
    hp, wp = h + (h % 2), w + (w % 2)
    b = np.full((hp, wp), np.nan, np.float64)
    b[:h, :w] = a
    v = np.where(np.isnan(b), 0.0, b)
    m = (~np.isnan(b)).astype(np.float64)
    s4 = v.reshape(hp // 2, 2, wp // 2, 2).sum((1, 3))
    m4 = m.reshape(hp // 2, 2, wp // 2, 2).sum((1, 3))
    meio = np.where(m4 > 0, s4 / np.maximum(m4, 1), np.nan)
    meio = preencher(meio)
    up = np.repeat(np.repeat(meio, 2, 0), 2, 1)[:h, :w]
    return np.where(np.isnan(a), up, a)


mdt_f = preencher(mdt.astype(np.float64))
# suaviza o preenchimento (blocos da pirâmide) sem tocar nas células medidas
for _ in range(3):
    sm = gaussian_filter(mdt_f, 2.0)
    mdt_f = np.where(buraco, sm, mdt_f)
mdt_f = mdt_f.astype(np.float32)
assert not np.isnan(mdt_f).any()
meta = {'proj': 'EPSG:31983', 'E0': float(E0), 'N1': float(N1), 'px': PX_MDT, 'nx': nx, 'ny': ny,
        'fonte': 'GeoSampa/PMSP LiDAR 2017 (s3://laz-m3dc-pmsp), pontos classe 2, média por célula',
        'origem_jogo': {'lat': lidar.LAT0, 'lon': lidar.LON0}}
np.save(os.path.join(OUT, 'mdt.npy'), mdt_f)
np.save(os.path.join(OUT, 'mdt_preenchido.npy'), buraco)
json.dump(meta, open(os.path.join(OUT, 'mdt.json'), 'w'), indent=1)

mds = smax.reshape(ny2, nx2)
mds[~np.isfinite(mds)] = np.nan
mds_buraco = np.isnan(mds)
mds = preencher(mds)
# pontos isolados muito acima dos vizinhos (pássaros, ruído não classificado; há z até 1156 m nos cabeçalhos)
from scipy.ndimage import median_filter
med = median_filter(mds, size=5)
pico = (mds - med) > 30.0
print(f'MDS: {int(pico.sum())} picos isolados (>30 m acima da mediana 5x5) trocados pela mediana')
mds = np.where(pico, med, mds).astype(np.float32)
meta2 = dict(meta, px=PX_MDS, nx=nx2, ny=ny2, fonte='GeoSampa/PMSP LiDAR 2017, maior retorno por célula (sem ruído)')
np.save(os.path.join(OUT, 'mds.npy'), mds)
json.dump(meta2, open(os.path.join(OUT, 'mds.json'), 'w'), indent=1)
mdt1 = mdt_f[:ny2 * 2, :nx2 * 2].reshape(ny2, 2, nx2, 2).mean((1, 3))
copa = np.clip(mds - mdt1, 0, None).astype(np.float32)
np.save(os.path.join(OUT, 'copa.npy'), copa)
json.dump(dict(meta2, fonte='mds - mdt (1 m), altura acima do terreno'), open(os.path.join(OUT, 'copa.json'), 'w'), indent=1)
json.dump(blocos, open(os.path.join(OUT, 'blocos.json'), 'w'), indent=1)
print(f'MDS: {100 * mds_buraco.mean():.2f}% células vazias (preenchidas); gravado mdt/mds/copa em {OUT}')
