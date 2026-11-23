# Interlagos — fonte própria da pista (Fase 2B, etapa D2: traçado em planta)

Até a 2B, Interlagos vinha do jogo web (`../gt3-time-attack/data/tracks/interlagos.json` → `tools/prep.ts`). Esta
pasta passa a ter a fonte própria, no processo de Laguna/Imola (`GUIA-PISTAS.md` §2).

| Arquivo | O quê | Gerado por |
|---|---|---|
| `interlagos.json` | TrackData: `origin`, `points` (a cada 4 m), `widthLeft/Right`, `kerbLeft/Right`, `wallLeft/Right`, `sections`, `medicao` (de onde veio cada trecho; o Track ignora) | `build_track.py` |
| `s_antigo_novo.json` | s do `data/track/track.json` atual (a cada 2 m) → s novo + lateral do centro antigo | `build_track.py` |
| `interlagos-osm.json` | o `interlagos-osm.json` do web **sem mudança** + `raceway`, `raceName`, `walls`, `fences`, `pitLaneOsm`, `finishLine` | `build_osm.py` |
| `interlagos-perfil-sat.json`, `perfil_zebras.py` | Fase 2 (bordas medidas, zebras decididas) — entrada, só leitura | Fase 2 |
| `lidar.py`, `download_lidar.py`, `interlagos-terrain.json` | LiDAR GeoSampa (outra etapa) | — |

Conferência (fora do git): `build/interlagos/tracado/` — `faixa_*.png` (desenrolado, 400 m por imagem),
`cima_*.jpg` (de cima, por trecho), `volta_cima.jpg`, `diag.json` (todos os números), `log.txt`.
Cores: verde = centro novo, ciano = centro antigo, vermelho/laranja/roxo = borda com confiança alta/média/baixa,
azul = borda aberta pelo GPS, amarelo = zebra, muro magenta = OSM, laranja = satélite, branco/cinza = perfil atual
(não medido), pontos azul-claros = as 6 voltas do Garage 61.

## Regenerar (de `REPOS/gt3-godot`)

```powershell
python tools/tracks/interlagos/build_osm.py          # baixa build/interlagos/osm/osm.xml se faltar (--baixar força)
python tools/tracks/interlagos/build_track.py        # ~15 s; --sem-imagens; --lidar (ver abaixo)
```

## Método

1. **Referencial** = o do mundo de hoje (linha atual = OSM a 0,4 m). O satélite é registrado nele pelo deslocamento
   global medido (Esri = mundo + (+2,1…2,3, −2,0…−2,2) m). O GPS do iRacing também fica a ~2–3 m (para leste/norte)
   do OSM; o cenário **não** foi movido.
2. **Bordas** = as da Fase 2 (`interlagos-perfil-sat.json`, conf ≥ 1) como pontos do mundo, projetadas na linha.
3. **Centro** = linha atual + R·δ(s); δ = mediana (31 m) do meio das bordas, suavizada σ = 15 m (`SIGMA_DELTA`), no
   máximo 6 m; onde só um lado mede, esse lado + meia-largura vizinha; sem nenhum, interpolação. σ final 2 m.
   σ menor (8–10 m) segue o ruído da borda e cria cotovelos (raio 30–100 m em retas a 200 km/h).
4. **Larguras**: percentil 40 em 15 m, σ 2 m; depois (a) dois tons → até a linha branca (`dois_tons`), (b) piso
   = largura crua do TUMFTM onde a nossa ficou > 1,5 m mais estreita (borda presa em degrau de tom de asfalto
   recapeado), (c) borda de confiança ≤ média aberta até o GPS das voltas (meio carro além da zebra).
5. **Zebras** = `perfil_zebras.ZEBRAS` (não redetectadas), s antigo → novo; largura física pela classe (normal
   1,2 m, saída 2,2 m; "fisica" = a da física atual naquele ponto).
6. **Muros**: OSM `barrier=wall|fence` (contínuo ≥ 10 m e até 3 m além do muro desenhado hoje) > candidato do
   satélite (conf. alta, a ≤ 1,5 m do perfil) > muro desenhado hoje (`visual_profile.json`, "não medido"). Nunca
   dentro da zebra nova.
7. **Altitude**: a do `track.json` atual levada por projeção. Sem `bank`.

## Ligando o LiDAR (próxima etapa)

`altitude_e_camber()` em `build_track.py` é o único ponto: com `--lidar` usa `lidar.altura(x, z)` (mediana contra
pontes, σ 4 m; camber a ±3,5 m, σ 10 m) e grava `bank`. Conferir VertAccel × v²·curvatura vertical antes de adotar.

## Antes de rodar `pista.ts` com esta pista

- `pista.ts` recusa `interlagos` (`if (id === 'interlagos') throw`) e grava em `data/tracks/<id>/`; Interlagos lê
  `data/track/`. Decidir id/destino.
- O `name` **não pode ser "Interlagos"**: a classe `Track` do web reescala as larguras (`realWidth`) e força os muros
  da reta (`pitStraightWalls`) por esse nome. Aqui está `"Interlagos (Fase 2B)"`.
- `applyWalls` empurra o muro para ≥ w + 2,5 m: o muro dos boxes e outros colados na pista (perfil: 1,4 m) ficam
  mais longe na física (esq 19%, dir 8% da volta).
- O Track mede a curva com 200 cordas (`getLength`): comprimento 4.300 m para uma curva de 4.308,6 m; espaçamento
  real das amostras 2,00–2,07 m (mesmo defeito de hoje: 4.294 × 4.301,6).
- `maxRunoff` não foi definido (escapes automáticos do Track, limitados pelo muro).
