# Imola (Autodromo Internazionale Enzo e Dino Ferrari) — dados da pista

Fontes reais usadas na geração do circuito (`id: "imola"`, sentido anti-horário, 19 curvas):

| O quê | De onde | Para quê |
|---|---|---|
| Linha central | OpenStreetMap (`highway=raceway`) + correção manual da Variante Bassa | traçado base (`build_track.py`) |
| Larguras + bordas | Foto aérea Esri World Imagery `0,25 m` (`sat.npy`) | `widthLeft/Right`, `imola-surfaces.json` |
| Altitude e relevo | Regione Emilia-Romagna LiDAR `Dtm1x1PST` `1 m` (bordas externas completadas com `Dtm5x5`) | `points[].y`, terreno (`imola-terrain.json`) |
| Copas e alturas urbanas | LiDAR `DsmAgea2008` (`dsm2m.npy` − `dem1m.npy`) | 5.500 árvores reais (`imola-canopy.json`) + alturas `imola-osm.json` |
| Camber | LiDAR lateral no traçado | `bank` (rad) |
| Brita e superfícies | Foto Esri `0,25 m` + polígonos `osm.gravel` | `imola-surfaces.json` (`sandL`/`sandR`) |
| Água (Rio Santerno) | OpenStreetMap (`riverLine` seguindo a calha do DEM + lagos planos `water[]`) | fita contínua terreno-dependente |
| Telemetria de referência | 3 voltas Garage 61 (iRacing, 60 Hz) | `data/reference/imola-{m4,mustang,amg}.json` |
| Referência visual | Vídeo LMU (`IMOLA-LMU-LMGT3.mp4`, 205 frames em `build/compare/lmu_imola/scan/`) | perfil `visual_profile.json`, comparação frame a frame |

## Regenerar (de `REPOS/gt3-godot`)

```powershell
python tools/tracks/imola/download.py         # fontes → build/imola/ (não versionado)
python tools/tracks/imola/build_track.py      # → imola.json (traçado) e imola-terrain.json
python tools/tracks/imola/build_osm.py        # → imola-osm.json (prédios, muros, brita, Santerno, pit...)
cd tools
npx.cmd vite-node pista.ts -- imola           # → data/tracks/imola/{track,terrain,osm}.json
npx.cmd vite-node referencia.ts -- imola      # → data/reference/imola-{m4,mustang,amg}.json
cd ..
python tools/tracks/imola/build_surfaces.py   # → imola-surfaces.json (brita × grama/escape)
python tools/tracks/imola/build_canopy.py     # → imola-canopy.json (5.500 árvores DSM − DTM)
cd tools
node props_imola.mjs                          # → assets/props/imola/{torre_imola,portico_imola,marshal_post}.glb
node cenario.mjs --track=imola                # → assets/tracks/imola/cenario.glb + arvores_pos.json + props.json
node arredores.mjs --track=imola              # → assets/tracks/imola/horizonte.png + horizonte.json + torres.json
```

Pré-visualização rápida WebGL (6 ângulos em `build/compare/imola/preview/`, sem GLTFExporter):

```powershell
cd tools
node cenario.mjs --track=imola --preview
```

Importação e testes no Godot:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/tests/imola.gd
Godot_v4.7.2-stable_win64_console.exe --path . --script res://scripts/tests/capture_compare.gd -- --track=imola --out=build/compare/imola/q2 --quality=2 --cam=0 --time=tarde --bench
```

## Cenário e Hero Props

- Com `--track=imola`, [tools/cenario/vite.config.ts](../../cenario/vite.config.ts) substitui os módulos de Interlagos pelos de [tools/cenario/imola/](../../cenario/imola/) (`trackView`, `trackDetails`, `trackside`, `scenery`, `surroundings`, `osmScenery`) guiados declarativamente por [visual_profile.json](visual_profile.json).
- Zebras tricolores italianas (`#008c45`, `#f4f5f0`, `#cd212a`, `#f4f5f0`), escapes sintéticos verdes (`wideRunoffs`), caixas de brita em grade de `4 m` seguindo `heightAt` (`brita.gdshader`), pit lane à direita com mureta, chevrons e pavimento de paddock (`osm.paved`), além de Rio Santerno contínuo ao longo de `riverLine`.
- Marcas 100% fictícias de temática italiana (zero logotipos reais).
- Três hero props modulares gerados por `tools/props_imola.mjs` ([props_imola.ts](../../cenario/props_imola.ts)) em `assets/props/imola/` e instanciados via `props.json` (`>= Leve`; ocultos no preset `0 Mínimo`):
  - `torre_imola.glb` — `500` tris (`27.3 KB`)
  - `portico_imola.glb` — `408` tris (`38.3 KB`)
  - `marshal_post.glb` — `358` tris (`16.7 KB`)
- Peso dos artefatos de Imola:
  - `assets/tracks/imola/cenario.glb`: `18.1 MB`
  - `assets/tracks/imola/horizonte.png`: `124.2 KB`
  - `data/tracks/imola/*.json`: `track.json` `273.6 KB`, `terrain.json` `648.9 KB`, `osm.json` `992.7 KB`, `arvores_pos.json` `334.4 KB`, `props.json` `0.4 KB`

## Conferências medidas

- Comprimento: `4.890 m` (`4.909 m` oficial, diferença `< 0,4%`); desnível: `34,3 m`; maior descida: `-9,3%` em `s=2542` (Acque Minerali); `10` trechos nomeados.
- Correlação física (`build_track.py`): MAE de `VertAccel` `0,123 g` (M4), `0,135 g` (Mustang), `0,136 g` (AMG).
- Piloto automático (`RefBot`) com cenário carregado (`imola.gd`):
  - `bmw-m4-gt3` (`imola-m4`): `1:42.012` (iRacing `1:40.117`), erro máx. linha `1,58 m`, pior diferença de curva `8,5 km/h`.
  - `audi-r8-lms-gt3` (`imola-amg`): `1:41.974` (iRacing `1:39.467`), erro máx. linha `1,45 m`, pior diferença de curva `9,8 km/h`.
  - `ferrari-488-gt3` (`imola-m4`): `1:41.950` (iRacing `1:40.117`), erro máx. linha `2,22 m`, pior diferença de curva `8,1 km/h`.
  - `acura-nsx-gt3` (`imola-m4`): `1:42.020` (iRacing `1:40.117`), erro máx. linha `2,16 m`, pior diferença de curva `7,6 km/h`.
- Benchmark no Godot (NVIDIA GTX 1650, `capture_compare.gd --bench`):
  - `q=0` (Mínimo): `161–238` draw calls, `358k–387k` triângulos (`16.3–33.4 ms/frame`).
  - `q=1` (Leve): `277–429` draw calls, `424k–472k` triângulos (`16.6–16.7 ms/frame`, `~60 FPS`).
  - `q=2` (Médio): `291–594` draw calls, `433k–511k` triângulos (`18.9–21.8 ms/frame`, `45.9–53.0 FPS`).
