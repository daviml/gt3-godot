# Interlagos — fonte própria da pista (Fase 2B: traçado D2 + integração no jogo E)

Até a 2B, Interlagos vinha do jogo web (`../gt3-time-attack/data/tracks/interlagos.json` → `tools/prep.ts`). Esta
pasta passa a ter a fonte própria, no processo de Laguna/Imola (`GUIA-PISTAS.md` §2). Desde a etapa E o jogo usa
esta pista: `tools/pista.ts -- interlagos` exporta para `data/track/` (o `prep.ts` não toca mais em pista, relevo,
OSM nem referências de Interlagos). A pista antiga (exportada do web, 4.294 m) fica em `build/interlagos/`
(`track_antigo.json`, `terrain_antigo.json`, `osm_antigo.json`, `interlagos-r8_antigo.json`, `paridade-web_antigo.json`);
se sumir: `git show f92abf5:data/track/track.json > build/interlagos/track_antigo.json`.

| Arquivo | O quê | Gerado por |
|---|---|---|
| `interlagos.json` | TrackData: `origin`, `points` (a cada 4 m), `widthLeft/Right`, `kerbLeft/Right`, `wallLeft/Right`, `wallMinGap`, `runLeft/Right`, `arcLengthDivisions`, `sections`, `medicao` (de onde veio cada trecho; o Track ignora) | `build_track.py` |
| `s_antigo_novo.json` | **mapa de s definitivo**: s do track.json antigo (a cada 2 m) → s do `data/track/track.json` novo + lateral do centro antigo (unidades do jogo; a etapa F remapeia perfil, cenário e atlas com ele) | `mapa_s.py` (depois do `pista.ts`) |
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

## Passo a passo até o jogo (etapa E; de `REPOS/gt3-godot`)

```powershell
python tools/tracks/interlagos/build_track.py --lidar        # 1. fonte: interlagos.json (relevo + bank do LiDAR; ~1 min)
cd tools
npx vite-node pista.ts -- interlagos                          # 2. data/track/track.json, terrain.json, osm.json
cd ..
python tools/tracks/interlagos/mapa_s.py                      # 3. s_antigo_novo.json (mapa de s definitivo)
cd tools                                                      # 4. as 6 referências do Garage 61 (≈ 20 s cada)
npx vite-node referencia.ts -- interlagos "../garage61/<arquivo Acura NSX ... José Carlos Pace ...>.csv" ../data/reference/interlagos-nsx.json "iRacing — Acura NSX GT3 EVO 22 (Gatis Petrovskis, 1:29.742)"
#   idem: interlagos-ferrari (Ferrari 296), -mclaren (720S), -m4 (BMW M4), -corvette (Z06 GT3.R), -porsche (992)
npx vite-node paridade.ts                                     # 5. data/tests/paridade-web.json (≈ 1 min)
cd ..
# 6. testes (headless): interlagos.gd, paridade.gd, cronometragem.gd, ... (lista no relatório da etapa E)
& "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://scripts/tests/interlagos.gd
```

`pista.ts` acha a pasta de saída pelo `data_dir` de `data/tracks.json` (Interlagos: `data/track/`); `--saida=<pasta>`
grava em outra (para comparar). Laguna e Imola saem idênticas byte a byte (conferido na etapa E).

### LiDAR ligado (etapa E, 23/11/2026)

`build_track.py --lidar` é o padrão desde então (sem a opção, volta a altitude antiga levada por projeção, sem
`bank`, só para comparar). `altitude_e_camber()` usa `lidar.perfil()`: piso real (classes 2 + 20, registro
LiDAR × mundo aplicado), mediana de 65 m contra passarelas, altitude σ 6 m; camber = `lidar.camber_bruto` (reta
robusta a ±3,5 m) + mediana curta + σ 10 m. `bank` + = lado direito mais alto (convenção de `tools/tracks/bank.ts`
e `track.gd`). A linha central não mudou com isso, então o piso (`download_lidar.py --piso`) não precisa ser refeito.

Conferido na pista exportada (`data/track/track.json`): desnível 43,1 m; lado de fora mais alto em 98% das
amostras em curva (S do Senna +8,1°, Subida dos Boxes +5,7°, Mergulho +4,5°, Ferradura −2,5°); VertAccel das 6
voltas × previsão pela geometria (σ 15 m): 0,032 g rms, 100% a ±0,15 g (sem LiDAR: 0,212 g, 60%). A crista falsa
da Ferradura (−0,25 a −0,41 g previstos contra +0,1 a +0,27 g medidos) sumiu (resíduo −0,05 a −0,02 g).

Paridade: o `paridade.ts` aplica o `bank` na pista do web (`applyBank`), e o `paridade.gd` monta o RefBot sem o termo de camber do `v_cap` (só o do Godot tem; o do web não), para comparar o mesmo piloto: R8 91,930 s nos dois.
### Decisões da etapa E (em `build_track.py` e `tools/tracks/fonte.ts`)

- **Comprimento**: o Track do web mede a curva com 200 cordas (4.300 m, amostras de 2,00–2,07 m). A fonte traz
  `arcLengthDivisions: 20000`, que o `fonte.ts` aplica só durante a construção do Track (o web não muda; Laguna e
  Imola, sem o campo, ficam iguais): 4.308 m (oficial 4.309, −0,02%), amostras a 2,000 ± 0,001 m ao longo da curva.
- **Muros**: `wallMinGap` 1,5 (1,3 desde a etapa F, só pela Goodyear do Lago) (o `applyWalls` padrão força 2,5 m, o que afastaria o muro dos boxes e outros colados
  na pista em 18%/8% da volta). Na física o muro é só um limite lateral (`track.gd`), então muro próximo não quebra
  nada; o `build_track.py` garante ≥ borda + 1,5 m, ≥ borda + zebra + 0,5 m e ≥ GPS das 6 voltas + 1,5 m (meio
  carro + folga), para a linha real (RefBot) não encostar.
- **Muros corrigidos na etapa F** (conferência do GLB, `build/interlagos/perfil_2b/conferencia_glb.json`; janelas
  em s antigo, rampa nas pontas, nunca a menos de meio carro além do GPS das voltas; `medicao.muroEtapaF`):
  separador da saída dos boxes (esq. 564–734) = borda + 4,4 m (guard-rail do `buildPitExit`; antes 10,3–17,0 m do
  centro); Goodyear do Lago (esq. 1385–1580) = borda + 1,35 m (antes 8,6–13,8 m; por isso `wallMinGap` 1,3);
  S do Senna (esq. 333–428) = cerca do OSM, que coincide com o guard-rail da saída dos boxes no satélite (12–27 m;
  antes 8,0–13,0 m); Bico de Pato (dir. 2713–2796, dentro do grampo, sem barreira a 30 m no satélite) ≤ 14 m
  (antes 21,8–23,4 m, maior que o raio da curva). O perfil "desenhado à mão" que entra nos muros não medidos é o
  da pista antiga, congelado em `build/interlagos/visual_profile_antigo.json` (o de `data/track/` agora usa o muro
  da física).
- **Muros corrigidos na Fase 4** (setor 4, `MURO_F` em `build_track.py`; medidos no satélite desenrolado
  `build/interlagos/fase4/sat_510_800_cru.png` e conferidos no LMU): separador da saída dos boxes (esq., s antigo
  564–734) deixou de ser borda + 4,4 m e passou ao fim da grama (`SEPARADOR_F4`: borda + 9,0 → 6,5 → 7,3 m); saída da
  Curva do Sol (dir., s antigo 722–766, rampa 6 m) = borda + 15 m (muro MOTUL; antes 5,5–8 m). A pista no
  `track.json` mudou só em `wallL` (s novo 566–748), `wallR` (722–780) e `runR` (728–780, escape automático até o
  muro); o relevo (`terrain.json`) mudou em 181 células perto desses muros (até 0,43 m).
- **Saída dos boxes** (s antigo 800–1000, esq.): faixa de aceleração = escape asfaltado (`runLeft`, aplicado pelo
  `applyRunoffMin` do `bank.ts`) até 0,5 m do guard-rail, e muro ≥ borda + zebra + 5,5 m (vídeo s0860/s0940: ~4–5 m
  de asfalto antes do guard-rail). A borda esquerda ali (pulava 5,0 ↔ 8,2 m entre a linha branca e a faixa) foi
  alisada.
- **Calombos da borda direita** em s antigo 1472–1498 e 3644–3664 (borda presa no escape turquesa / piso do
  TUMFTM): reta entre as pontas (`ALISAR`).
- **Bico de Pato, borda esquerda** (s antigo 2676–2742, aviso do LiDAR): a borda medida (6,7–7,7 m) passava por
  cima de um muro baixo (linha cinza clara em `cima_bico_mergulho.jpg`) até o asfalto do traçado antigo; o LiDAR
  mostra muro + degrau de 0,9 m a ~4 m. Borda limitada a 4,2 m (nunca a menos de 1 m além do GPS das voltas, que
  vão até 2,9 m), rampa de 10 m (`LIMITAR`). O muro da física fica a borda + 1,5 m (`wallMinGap`).
- **Subida dos Boxes, borda esquerda** (s antigo 3641–3666): fim do piso do TUMFTM (9,4 m) seguido de borda de
  confiança média 1,5 m para dentro (7,4 m) por 15 m, onde as 6 voltas passam a 8,6–9,2 m. Com o LiDAR, o RefBot
  na volta da Ferrari freava ali (170 × 191 km/h, linha cortada pela borda). Reta entre as pontas (`ALISAR`):
  nenhuma volta passa mais de 1 m além da borda + zebra.
- **Larguras de 9,2–10,5 m** (Reta Oposta, subida do Lago, entrada da Junção): mantidas. As duas medidas do
  satélite (Fase 2 e detector próprio) concordam, as voltas não chegam perto da borda e os quadros do vídeo
  (s0940, s1000, s1200, s1700, s3140) dão ~9,5–10,5 m de asfalto pela largura do carro.
- **`name`**: continua "Interlagos (Fase 2B)" (o Track do web reescala larguras e põe muros por nome "Interlagos").

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
7. **Altitude e camber**: LiDAR (`--lidar`, ver acima). Sem a opção: a do `track.json` antigo levada por projeção, sem `bank`.

## LiDAR (relevo e camber)

Fonte: GeoSampa/PMSP, levantamento a laser 2017 (36 folhas LAZ do bucket público `laz-m3dc-pmsp`, SIRGAS 2000 /
UTM 23S), em `build/interlagos/lidar/` (fora do git).

```powershell
python tools/tracks/interlagos/download_lidar.py           # baixa (se faltar) e rasteriza MDT/MDS/copa (~min)
python tools/tracks/interlagos/download_lidar.py --piso    # só o piso perto da pista (~15 s; refazer se a linha mudar)
python tools/tracks/interlagos/lidar.py --conferir         # conferências, gráficos, interlagos-terrain.json (~30 s)
```

**Classes da nuvem** (medido 23/11/2026 nas folhas da pista): 2 = só o envelope inferior do solo (~7–11% dos
pontos, os mais baixos de cada vizinhança: ~0,14 m abaixo do plano local; espalhados por igual na largura da pista,
não ficam em valetas/bordas); 20 = o resto do solo (37% de toda a nuvem; asfalto, grama, ruas; 0…0,4 m acima da
classe 2, nunca em telhado); 19 = objetos baixos 0,4–8 m (muros, alambrados, carros, pessoas; mediana +1,2 m);
5/6 = vegetação alta e prédios/passarela. Ruído do laser no asfalto σ ≈ 9 cm por passada; duas passadas diferem
~3 cm. O chão real é a média de 2 + 20; o MDT só com a classe 2 fica ~0,12 m baixo (0,17 m no asfalto) e
interpola 64% da linha central.

**Piso** (`piso.npy`, 0,5 m, grade alinhada ao MDT): classes 2 + 20 a até 44 m das linhas centrais nova
(`interlagos.json`) e antiga (`data/track/track.json`); rejeita ponto a mais de 0,25 m da mediana local 5,5 m
(2,4%: carros/pessoas/bordas de muro já são classe 19); média ponderada por gaussiana σ 0,75 m; buracos (passarela,
pórticos, sombras; 3,9% da faixa) por gaussianas mais largas (2, 5, 12 m) e por fim MDT + offset. Peso 1 até 34 m
das linhas, smoothstep até 0 aos 40 m, onde vira MDT + offset (0,115 m) — sem degrau. `piso_n.npy` = pontos por
célula, `piso_int.npy` = intensidade (para medir o registro).

**Registro**: o mundo do jogo (OSM) fica deslocado do terreno georreferenciado. `lidar.REGISTRO = (+1,50, −1,75)` m
(ponto do LiDAR = ponto do mundo + REGISTRO), medido pelo contraste de intensidade do laser asfalto × faixa além
das bordas da pista nova; pela cor da nuvem (+1,75, −1,75); satélite Esri (+2,1, −2,2); GPS do iRacing (+2,5, −2,8).
`--conferir` mede o resíduo (hoje ≤ 0,25 m na volta, ≤ 1 m por quarto). Sem o registro, centro e ±3,5 m caíam ~2,3 m
fora do lugar (ex.: no Bico de Pato o degrau de 0,9 m ficava a 2 m do centro em vez de 4 m).

**API** (`import lidar`): `altura(x, z)` (piso perto da pista, MDT + offset fora; `fonte='mdt'` = antigo),
`copa`, `superficie`, `jogo_para_utm` (com REGISTRO; `registro=False` = conversão pura), `camber_bruto(P, R)`
(reta robusta Theil–Sen + Tukey pelas alturas a cada 0,5 m entre ±3,5 m: ignora degrau/muro num dos lados),
`perfil(P, passo, secoes)` (altitude + camber + tabela por curva, como no `--conferir`).

**Suavização ao longo da pista** (conferida com o VertAccel das 6 voltas do Garage 61): altitude σ 6 m (σ 4 m
também passa; abaixo de 4 m piora: VertAccel a σ 3 m erra 0,075 g com σ 6–8 m, 0,084 g com σ 4, 0,117 g com σ 2);
camber σ 10 m (4–15 m dá o mesmo; ruído do camber bruto 0,15°). Resultado com o piso na linha antiga: 0,035 g
rms (VertAccel σ 15 m; 0,045 g a σ 8 m, 98,7% da volta a ±0,15 g); o `track.json` antigo (SRTM) erra 0,21 g rms;
sem camber, 0,068 g. Pior ponto: s ≈ 4038 (Arquibancadas), medido +0,24 g acima do previsto.
A linha antiga (n = 2147) está congelada em `build/interlagos/lidar/track_antigo.json` (o `data/track/track.json`
passou a receber a pista nova).

**Ligar na pista:** `altitude_e_camber()` em `build_track.py` é o único ponto (`--lidar` usa `lidar.altura`). Para
o camber, trocar a diferença de 2 pontos por `lidar.camber_bruto(P, Rr)` (mesma mediana curta + σ 10 m depois).
Pendência do traçado: em s ≈ 2680–2730 (Bico de Pato) o LiDAR 2017 mostra muro + degrau de 0,9 m a ~4 m à
esquerda do centro novo, dentro de `widthLeft` (6,7–7,2 m).

## Etapa F — cenário na pista nova (23/11/2026)

O gerador do cenário monta a MESMA pista da física e tudo o que era metro da pista antiga foi levado pelo mapa
`s_antigo_novo.json` para continuar no mesmo lugar físico.

- **Pista do gerador**: `tools/cenario/vite.config.ts` → `DATA.interlagos` troca o `interlagos.json`/OSM/relevo/
  referência do web pela fonte daqui (`interlagos.json`, `interlagos-osm.json`, `interlagos-terrain.json` do LiDAR,
  `data/reference/interlagos-porsche.json` reconvertida). `cenario.ts`/`arredores.ts` montam com
  `tools/tracks/montaPista.ts` (o mesmo do `pista.ts`, agora sem nada do Node; `fonte.ts` reexporta) + `applyBank`.
  O `cenario.mjs` confere amostra a amostra contra `data/track/track.json` antes de gravar (n 2.154, posição máx
  0,01 cm, larguras/zebras/escapes/muros ≤ 0,5 cm = arredondamento do track.json); diverge → erro.
- **Metros da pista antiga**: `tools/cenario/interlagos/sNovo.ts` (`sNovo`, `sAntigo`, `dNovo`; `sNovo4300`/`iNovo4300`/
  `s4300` para a convenção antiga "s numa volta de 4.300 m"). Nos módulos `trackDetails/trackside/scenery/osmScenery/
  trackView.ts` cada constante continua escrita com o valor antigo dentro da função (auditável). Passarela, pórticos,
  saída/entrada dos boxes etc. ficam onde estavam (não foram para as âncoras do satélite: isso é dos setores).
- **Perfil lateral** (`data/track/visual_profile.json` v2, 2.154 amostras, 4.308 m): `tools/cenario/interlagos/
  migrarPerfil2B.ts` (lê a v1 congelada em `build/interlagos/visual_profile_antigo.json` + `track_antigo.json`;
  relatório em `build/interlagos/perfil_2b/`). Fatias esq 98 → 85, dir 84 → 68. Zebras: `larg: "fisica"` em todas
  (a física já é a tabela `ZEBRAS`): visual = física, 1.186 m à esquerda e 518 m à direita (antes: 1.168/498 m de
  listrada; diferenças só de 1 amostra nas pontas e a largura do Pinheirinho esq 2514–2560, 1,24 → 1,0 m).
- **Decisão de muro**: barreira do perfil = muro da física (`dist: "fisica"`) em toda a volta. Critério: o carro não
  atravessa muro visual nem bate em muro invisível; o muro da física é medido (OSM > satélite > perfil antigo). O
  escape pintado é cortado no muro (304 amostras). Onde o muro da física e o do perfil antigo diferem > 2 m (ex.: S do
  Senna esq ~380, Reta Oposta, Ferradura esq, Bico de Pato esq, pit straight), quem manda é a física; os trechos estão
  em `build/interlagos/perfil_2b/relatorio.json` (`muro.por_fatia`) para os setores.
- **Atlas**: `tools/ref/atlas_s_novo.py` → `build/ref/interlagos/atlas_v2.json` + `chase_v2/`, `onboard_v2/`
  (**sNNNN = s novo**; `chase/` e `onboard/` da Fase 0 continuam no s antigo). `capture_compare.gd --atlas` sempre
  fotografa no s da pista atual. `folha.py --lista` para metros livres.
- **Conferência do GLB**: `python tools/cenario/interlagos/conferir_glb.py` (asfalto × bordas, zebras × física,
  barreiras × muro da física, árvores/props × asfalto). Laguna e Imola saem idênticas byte a byte.

## Pendências depois da etapa F

- `maxRunoff` não foi definido (escapes automáticos do Track, limitados pelo muro).
- Física (não mexida na etapa F): o separador da saída dos boxes (guard-rail a borda + 4,4 m, s novo 574–742 esq) e a
  barreira dupla Goodyear da Descida do Lago (borda + 1,35 m, s novo 1394–1582 esq) ficam até 5,2 m e 3,7 m DENTRO do
  muro da física: o carro passa através deles. O muro da física ali deveria vir para essas barreiras (build_track.py).
  Dentro de curvas fechadas, barreiras a 10–25 m do centro ficam até 0,75 m para dentro do limite (amostragem de 2 m);
  no Bico de Pato dir (s novo 2778–2790) o muro da física (23 m) passa do raio da curva e o guard-rail dobra sobre si.
- As ferramentas da Fase 0 (`tools/ref/atlas_video.py`, `tools/ref/ref_garage61.py`) continuam na pista antiga
  (`build/interlagos/track_antigo.json`); o atlas novo é derivado delas pelo mapa.
- Os pontos do bench (`CHECKPOINTS` do capture_compare.gd) continuam com os metros de antes (agora s novo: até ~16 m
  de diferença física); só para comparar desempenho.
- Recordes zerados: `user://recordes-interlagos-v4.json` (simulador) e `user://recordes-interlagos-arcade-v4.json`
  (arcade); fantasma com chave `interlagos-v4` (`data/tracks.json` → `ghost_key`). O ranking compartilhado (repo
  `gt3-tempos`) passou para `interlagos-v4-godot.json` / `interlagos-v4-godot-arcade.json` (`REMOTE_FILES` em
  `scripts/ui/records.gd`); os arquivos antigos ficam no repositório como histórico da pista antiga.
