# Laguna Seca — dados da pista

Fontes reais, nada desenhado à mão:

| O quê | De onde | Para quê |
|---|---|---|
| Linha central | OpenStreetMap (trechos `highway=raceway`, 3.605 m) | traçado |
| Larguras + correção do centro | foto de satélite Esri 0,25 m (borda do asfalto cinza × brita/terra/faixa branca) | `widthLeft/Right` |
| Altitude | USGS 3DEP 1 m (LiDAR, terreno nu) | `points[].y`, relevo em volta |
| Camber | LiDAR a ±3,5 m do centro | `bank` (rad, + = lado direito mais alto) |
| Linha de chegada, sentido | voltas do Garage 61 (`garage61/*.csv`) | s = 0 |
| Telemetria de referência | Garage 61 (iRacing, 60 Hz) | `data/reference/laguna-seca-*.json` |

## Regenerar (de `REPOS/gt3-godot`)

```
python tools/tracks/laguna-seca/download.py      # fontes → build/laguna-seca/ (não versionado)
python tools/tracks/laguna-seca/build_track.py   # → laguna-seca.json (traçado) e laguna-seca-terrain.json
python tools/tracks/laguna-seca/build_osm.py     # → laguna-seca-osm.json (prédios, muros, brita, pit...)
cd tools
npx vite-node pista.ts -- laguna-seca            # → data/tracks/laguna-seca/{track,terrain,osm}.json
npx vite-node referencia.ts -- laguna-seca ../garage61/<volta>.csv ../data/reference/laguna-seca-<carro>.json "<rótulo>"
cd .. && python tools/tracks/laguna-seca/build_surfaces.py && cd tools   # → laguna-seca-surfaces.json (brita × mato)
node cenario.mjs --track=laguna-seca             # → assets/tracks/laguna-seca/cenario.glb + árvores
node arredores.mjs --track=laguna-seca           # → horizonte
```

Depois: `godot --headless --path . --script res://scripts/tests/laguna_seca.gd` (pista + piloto automático × iRacing).
Prints lado a lado com o LMU: `godot --path . --script res://scripts/tests/capture_compare.gd -- --track=laguna-seca
--out=build/compare/laguna_seca/godot_chase --quality=2 --cam=0` (`--cam=1` = capô, para a volta onboard).

## Cenário

O cenário sai do código do jogo web, como o de Interlagos, mas com `--track=laguna-seca` o
`tools/cenario/vite.config.ts` troca os módulos com coisa fixa de Interlagos por cópias adaptadas em
`tools/cenario/laguna/` (trackView, trackDetails, trackside, scenery, surroundings) e os dados pelos daqui. O web não
muda e, sem `--track`, a exportação de Interlagos sai byte a byte igual.

- Zebras vermelho/branco, faixa verde pintada de 2,5 m atrás delas (`maxRunoff` em laguna-seca.json, vale também
  para a física), brita/areia até o muro onde o satélite mostra areia (`build_surfaces.py`), mato seco no resto.
- Muro de concreto com alambrado na volta toda, placas fictícias nas curvas, pneus por fora das curvas fechadas.
- Pontes nas estruturas vistas no satélite (as sombras caem ~10 m ao norte): arco treliçado com faixa vermelha
  "LAGUNA SECA" em s ≈ 912 (entre T3 e T4, como no LMU), passarelas treliçadas em 1376, 2602 (placa branca
  "LAGUNA SECA RACEWAY", chegada da Rainey) e −8 (antes da linha), viaduto de estrada em 1824. Nomes genéricos.
- Placas de freada 3/2/1 achadas na telemetria; borracha forte no traçado real e marcas de freada nas freadas fortes.
- Paddock: tendas brancas, carretas e 2 guindastes nas áreas asfaltadas do OSM perto da pista (só do Leve para cima).
- Carvalhos mais densos (e tom verde-escuro, `visual.impostor`) nos morros da T6, do Corkscrew e da Rainey.
- Faixa verde larga por dentro da Andretti, da T8, da Rainey e da T10 (só pintura: a física continua com 2,5 m).
- Bandeira no alto do Corkscrew, torre de controle "LAGUNA SECA" atrás dos boxes, "salsicha" amarela no ápice da T8
  (a única que o vídeo do LMU mostra), só visuais.
- Galpões sem altura no OSM ficam com 7 m (`build_osm.py`): o cenário do web os transformaria em torres.
- Boxes e pit lane à esquerda da reta, arquibancadas à direita da reta e no morro da T4 (OSM).
- Sem anel de prédios; horizonte de morros secos. Cores de asfalto, grama e brita no Godot: `data/tracks.json` →
  `visual` (os shaders têm como padrão os valores de Interlagos).

## Conferências (13/11/2026)

- Comprimento 3.598 m (oficial 3.602 m); desnível 54,9 m (oficial 55 m); maior descida 18,6% no Corkscrew.
- As 4 voltas do iRacing cabem entre as bordas medidas em ~99% do tempo (o resto é erro de GPS de 1–3 m).
- A altitude reproduz o acelerômetro vertical do iRacing (±0,1–0,2 g) na volta quase toda.
- Camber medido: T1 +5,7°, T6 +5,5°, T8 +7,2°, T8A −6,8°, Rainey +6,7°, T10 −5,8° (sempre o lado de fora mais alto).
- Piloto automático (RefBot) × iRacing: voltas válidas a +1,2–1,8 s; mínimas por curva a ≤9 km/h, exceto a T6
  (o GT3 do iRacing faz 3,2 g ali a 175 km/h; aqui ~145–150) — ajuste de física pendente.
