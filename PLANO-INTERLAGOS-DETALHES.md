# Plano Interlagos — Detalhes da Pista por Metragem (referência LMU)

Plano novo, só de Interlagos, focado em **comparar o vídeo do LMU com a nossa pista no mesmo metro de pista** e
corrigir os detalhes trecho a trecho. Substitui `PLANO-VISUAL-PISTA.md` como plano ativo de Interlagos e absorve a
parte de Interlagos do `PLANO-ARVORES.md`.

Status: **aprovado pelo Davi em 20/11/2026**, em execução por fases (decisões no §8). Fases 0 e 1 concluídas (folha da Fase 1
aprovada); Fases 2 e 2B feitas, aguardando o Davi olhar as folhas; próxima: **4** (ordem dos setores, §8).

---

## 1. Por que os planos anteriores não bastaram

Conferido no repositório e nos prints (`build/compare/lmu_30` × `build/compare/interlagos_30_v2`):

1. **Os pares não mostram o mesmo lugar.** Os 30 pontos têm `s` escolhido no olho. Exemplo: no par 01 o LMU está
   depois da placa de 50 m e o nosso print está na placa de 150 m; no par 09 o LMU mostra a faixa vermelha da Curva
   do Sol e o nosso já está em outro trecho. Comparar detalhe com 50–100 m de erro não funciona, e é aí que os
   detalhes se perdem.
2. **Câmera diferente.** O LMU usa FOV vertical de 50° (aparece escrito no vídeo) e outra distância de perseguição.
   A nossa câmera de jogo (5,3 m / 1,55 m / 55°) foi ajustada de propósito e não deve mudar, mas para comparar
   precisa existir uma câmera de captura igual à do vídeo.
3. **30 pontos em 4.294 m = 1 a cada ~143 m.** Zebra, mudança de barreira, início de faixa pintada e placas duram
   20–60 m. A maioria nunca apareceu em print nenhum.
4. **Correção "no atacado".** As fases anteriores calibraram cor e preset para a volta inteira e marcaram como
   concluído com 4–5 prints conferidos. Não houve lista de itens por trecho com critério de pronto.
5. **A base lateral da pista é genérica.** No `track.json` os muros ficam a ~22,3 m do centro em quase toda a volta
   (mediana 22,3 m, máximo 23,9 m), a zebra tem largura única (0 ou 2,2 m) e o escape é 0–12 m por regra. As
   exceções foram empilhadas à mão em `trackDetails.ts` (1.521 linhas de casos especiais).
6. **Problemas globais mascaram os locais.** Grama (a nossa é verde-viva; a do LMU é palha/oliva seca), zebras (as
   nossas têm blocos largos e longos; as do LMU são estreitas, com faixa verde pintada atrás e "salsicha" amarela),
   asfalto (o nosso é mais frio e escuro), luz (a nossa é chapada, sem a sombra forte do sol) e a parede de árvores
   iguais que tampa o horizonte da cidade.

---

## 2. Ideia central: atlas de referência indexado por metro de pista

O vídeo tem **a mesma volta (1:33.525) duas vezes**: perseguição (0–~96 s) e onboard (~96–193 s), com velocímetro
e marcha na tela nas duas. Isso permite saber em que metro da pista está cada quadro, sem olhar para o tempo.

**Como achar o `s` de cada quadro (script, sem IA olhando prints):**

1. Ler a velocidade do velocímetro em todos os quadros (60 fps) por comparação de dígitos (fonte e posição fixas).
2. Integrar a velocidade: distância = soma de v·dt. Dá `s(t)` da volta inteira.
3. Corrigir o desvio com âncoras de `s` conhecido: linha de chegada, placas de 200/150/100/50 m, início e fim de
   zebras medidos no satélite. Entre duas âncoras, corrigir por escala linear.
4. Conferir contra o perfil de velocidade do Garage 61 (`data/reference/interlagos-r8.json`): os pontos de freada e
   as velocidades mínimas de curva têm que cair no mesmo `s` (tolerância ±10 m).
5. Extrair **1 quadro a cada 10 m** nas duas câmeras: ~430 + ~430 quadros em `build/ref/interlagos/chase/s0000.jpg`
   … e `onboard/s0000.jpg` …, mais `atlas.json` (s → tempo do vídeo, velocidade, marcha).

Ninguém analisa os 860 quadros de uma vez. Eles viram um **índice**: cada fase abre só os quadros do trecho dela.

**Do nosso lado**, o `capture_compare.gd` ganha o modo `--atlas`:

- recebe `--s0`, `--s1`, `--passo` e fotografa nesses metros;
- posiciona o carro **sobre a linha da referência** (RefBot / Garage 61), com a direção dela, em vez de `d` e `yaw`
  chutados por ponto;
- usa uma **câmera de comparação** própria (FOV 50°, distância e altura acertadas uma vez contra 3 quadros do
  LMU), sem tocar na câmera do jogo;
- grava com o mesmo nome (`s1340.png`) e monta a folha lado a lado sozinho (`tools/ref/folha.py`).

**Portão da Fase 0:** em 10 pontos sorteados, o mesmo objeto fixo (placa, início de zebra, ponta de muro) aparece
nos dois lados com erro ≤ 10 m. Sem isso, nenhuma fase de detalhe começa.

---

## 3. Remontar do zero: perfil lateral declarativo

Em vez de continuar remendando `trackDetails.ts`, a descrição das laterais passa para **dados**:
`data/track/visual_profile.json` (ideia já anotada no `GUIA-PISTAS.md` §9.4 e nunca feita).

Para cada fatia `[s0, s1]` e cada lado, da linha branca para fora:

```json
{ "s0": 1340, "s1": 1420, "lado": "esq",
  "faixas": [
    { "tipo": "zebra", "larg": 1.2, "padrao": "amarelo-verde-branco", "salsicha": false },
    { "tipo": "pintura", "cor": "verde", "larg": 2.0 },
    { "tipo": "grama", "larg": 4.5 }
  ],
  "barreira": { "tipo": "tecpro2", "dist": 7.7, "banner": "goodyear", "alambrado": true } }
```

- **Fonte dos números:** foto de satélite 0,25 m (Esri, mesmo processo de Laguna Seca: `build_surfaces.py`) para
  larguras, início/fim de zebra, brita × grama × asfalto de escape e distância dos muros; vídeo para tipo de
  barreira, cores, banners e alambrado.
- **O gerador** (`tools/cenario/interlagos/`) lê o perfil e constrói zebras, faixas, brita, barreiras e alambrados.
  Os casos especiais que sobrarem (ponte, pórtico, entrada/saída dos boxes) continuam em código.
- **Física:** o perfil nasce visual. As larguras de zebra, escapes e posição de muro medidas entram também no
  `track.json` na Fase 2B (geometria refeita, recordes zerados — aprovado no §8).
- **Migração sem regressão:** primeiro gerar o perfil a partir do que existe hoje (resultado idêntico ao atual,
  conferido por print), depois corrigir setor por setor.

---

## 4. Fases

Cada fase cabe em **uma sessão**, termina com folha lado a lado para o Davi aprovar e não depende de analisar a
volta inteira. Limite por sessão: **no máximo ~24 pares** abertos pela IA.

### Fase 0 — Atlas por metragem e captura alinhada (fundação)
- `tools/ref/atlas_video.py`: leitura do velocímetro, integração, âncoras, quadros a cada 10 m, `atlas.json`.
- `capture_compare.gd --atlas` + câmera de comparação + `tools/ref/folha.py`.
- Overlay opcional de régua (marcas de `s` a cada 10 m e de `d` a cada 2 m) para medir no print.
- **Pronto quando:** portão dos 10 pontos (§2) passa; folha da volta inteira a cada 50 m gerada (86 pares, só
  para arquivo e para o Davi folhear).

**Resultado (20/11/2026) — concluída, com uma ressalva:**
- `tools/ref/atlas_video.py` (velocímetro lido em 100% dos quadros; congelamento do vídeo em 74,8–76,5 s tratado;
  escala global 1,022) ancorado na volta do Porsche 911 GT3 R do Garage 61 (`tools/ref/ref_garage61.py`), 19 âncoras,
  resíduo rms 3,8 m. Perseguição × onboard concordam em ≤ 2 m.
- Erro estimado de `s`: ±5 m na maior parte da volta; **±10–15 m entre a Junção e a freada do S (s 3276 → 186)**,
  trecho sem âncora de velocidade. Fechar essa ressalva na Fase 2 com âncoras do satélite (entrada dos boxes,
  linha de chegada, pórtico).
- `capture_compare.gd --atlas` (`--s0 --s1 --passo --cam --regua`, sempre com `--track=interlagos`): câmera de
  comparação 6,8 m atrás / 2,14 m de altura / 12° para baixo / FOV 50°; onboard com FOV 43° (estimado).
- `tools/ref/folha.py`; folhas da volta inteira em `build/ref/interlagos/folhas/fase0_chase|fase0_onboard`.
- Portão: 7 de 10 pontos batem. Os outros 3 são **achados de cenário**, não erro do atlas: placas de freada do S
  (s≈150) e pórtico Rolex (s≈250) estão 20–30 m fora do lugar; entrada dos boxes (s≈3950) a confirmar no satélite.

### Fase 1 — Aparência global (o que aparece em todo quadro)
Corrigir antes dos setores, senão todo par "parece errado" pelo mesmo motivo.
- **Cor medida, não no olho:** amostrar a cor média de asfalto, grama, zebra, faixa verde e céu em ~12 quadros do
  LMU (regiões marcadas) e nos nossos; ajustar até a diferença ficar pequena (meta ΔE ≤ 8 por material). Vídeo tem
  compressão e desfoque, então é alvo aproximado, mas tira o chute.
- **Grama:** palha/oliva seca com manchas de terra alaranjada, no `grama.gdshader` (modo completo e `fast_mode`).
- **Asfalto:** tom mais quente e claro, faixa de borracha, emendas e remendos.
- **Zebra padrão de Interlagos:** largura e passo reais (medidos no satélite), sequência amarelo/verde/branco,
  faixa verde pintada atrás, perfil baixo; "salsicha" amarela como tipo separado.
- **Linha branca:** largura e continuidade.
- **Sol e sombra:** direção e altura do sol iguais às do vídeo (sombra do carro para a esquerda/frente), contraste
  de sombra visível do Médio para cima, névoa de distância. Sem custo novo no Mínimo/Leve.
- **Pronto quando:** 8 pares de trechos diferentes aprovados pelo Davi + metas de cor + `--bench` sem piora.

**Resultado (20/11/2026) — feita, aguardando aprovação da folha pelo Davi:**
- **Medição:** `tools/ref/cores.py` + `cores_interlagos.json` (13 pares, ΔE00 por material; `--godot <pasta>` para
  remedir). Linha de base: os 10 materiais fora da meta. Final no Médio: asfalto 4,6 · sombra 4,3 · grama 3,6 ·
  céu 2,9 · zebra amarela 4,6 · verde 0,9 · branca 0,7 · linha branca 0,9 · vermelho 1,6 · verde de escape 2,6 ·
  verde atrás da zebra 3,3. Mínimo e Leve também ≤ 8 (exceto sombra no Mínimo, que não tem sombra do sol).
- **Luz (só Interlagos, em `data/tracks.json → visual.luz|ceu|decalques`):** sol de azimute 124° → 345° e
  elevação 48° → 45° (medido pela sombra da asa no vídeo); razão sombra/sol 0,26 → 0,06 (LMU 0,07); céu limpo em
  degradê; grama dourada com manchas de terra; asfalto mais claro e quente, borracha mais discreta. Laguna e
  Imola: diferença zero nos pixels.
- **Zebra padrão / linha branca (`trackView.ts`, constante `BORDA`):** zebra 1,0 m (1,6 m nas saídas), blocos de
  0,8 m amarelo/branco/verde; linha branca 0,18 m contínua com vão de 0,10 m; faixa verde atrás e salsicha como
  tipos próprios (aplicadas em Curva do Sol, Ferradura e Pinheirinho). Blocos medidos no satélite Esri z19.
- **Tintas (`tools/cenario/interlagos/tintas.ts`, tabela `TINTA`):** a cena multiplica o albedo por ~4 antes do
  AgX, então a cor do LMU usada direto como albedo estoura e desbota. Os albedos foram calibrados pela inversa
  (`scripts/tests/calib_tinta.gd` + `tools/ref/calib_tinta.py`). Banners compensados por `PLACA_GANHO`.
- **Bench (30 pontos, `--disable-vsync --track=interlagos`), antes → depois:** Mínimo 5,25 → 5,16 ms (150 draw
  calls); Leve 5,48 → 5,43 ms (295); Médio 14,13 → 14,39 ms (346 → 349 draw calls, 536k → 543k triângulos).
- **Folha de aprovação:** `build/ref/interlagos/folhas/fase1_final/folha_01.jpg` e `folha_02.jpg` (8 pares).
- **Pendências:**
  - A calibração vale para o Forward+. No `gl_compatibility` (Web) as cores divergem (asfalto ΔE 12, grama 16,
    céu 10); o renderizador `mobile` (Android) não foi medido. Calibrar por renderizador antes de publicar.
  - Zebra visual 0,6 m mais estreita que a física em 14 saídas de curva → some na Fase 2B.
  - Para os setores: escape verde-vivo onde o LMU tem verde-água ou grama (S do Senna, Pinheirinho, Mergulho),
    zebra + vermelho na saída da Curva do Sol, muro DHL da Ferradura pálido, segunda linha branca na Reta Oposta.
  - Emendas e remendos do asfalto não foram mexidos; manhã de Interlagos não calibrada; árvores acinzentadas (§5).

### Fase 2 — Perfil lateral a partir do satélite
- Baixar satélite 0,25 m da área (em `build/interlagos/`, fora do git) e classificar asfalto/zebra/pintura/brita/
  grama por cor, perpendicular à pista a cada 1 m.
- Gerar `visual_profile.json` v1 (larguras, zebras, escapes, distância de muro) e o mapa de diferenças contra o
  que o gerador faz hoje.
- Refatorar o gerador para ler o perfil (migração sem regressão, §3).
- **Pronto quando:** imagem de cima (perfil desenhado sobre o satélite) bate em toda a volta; todas as zebras com
  início e fim a ≤ 3 m do satélite.

**Resultado (20/11/2026) — feita, aguardando o Davi olhar a folha:**
- **Satélite (`tools/tracks/interlagos/download.py`, `build_perfil.py` → `interlagos-perfil-sat.json`):** mosaico
  Esri z19 de 184 tiles (volta + pit lane, 0,1% sem imagem), perfil por metro e por lado (borda, zebra, pintura,
  escape, muro, confiança). Confiança baixa em ~14% da volta por lado (sombra, copa, escape da cor do asfalto).
- **Achado principal: a linha central do `track.json` erra 2–5 m em várias curvas** (S do Senna, Descida do Lago,
  Mergulho, Junção, Café, reta dos boxes; sinais alternados = curva "cortada") e o asfalto real é ~0,7 m mais
  estreito por lado (12,8 × 13,55 m). O mosaico tem deslocamento global de ~3 m contra a pista (dx +2,32, dz −1,96;
  corrigido na medição; não se sabe se o erro é da Esri ou do traçado). Tudo isso é entrada da Fase 2B.
- **Perfil declarativo:** `data/track/visual_profile.json` lido por `tools/cenario/interlagos/perfil.ts` (esquema
  no topo do arquivo). Migrados do código: zebra, pintura verde, salsicha, escape, tipo/distância de barreira,
  banner e alambrado (`trackView.ts` 904 → ~700 linhas). A migração foi conferida com o GLB idêntico byte a byte
  ao anterior (`tools/cenario/interlagos/impressao.mjs` compara malha a malha). Continuam em código: ponte,
  pórticos, grid, entrada/saída dos boxes, faixas da Reta Oposta, barreira Goodyear do Lago, muro da Ferradura e
  6 outdoors. **Não rodar `cenario.mjs --extrair-perfil`**: regenera a v1 do código antigo e apaga as edições.
- **Zebras (`tools/tracks/interlagos/perfil_zebras.py`, tabelas de decisão):** 19 zebras no perfil; 15 a ≤ 3 m do
  satélite e 4 decididas pelo vídeo do LMU (saída da Curva do Sol começa ~50 m antes; fim do Mergulho ~20 m
  antes; Lago dir 1506–1534 e Ferradura esq 2176–2222 existem no LMU e o satélite não vê). Ferradura dir virou
  faixa verde + salsicha até 2196. 24 segmentos curtos do satélite não aplicados (lista com motivo no
  `diferencas.md`). Largura pelas classes da Fase 1 (`visual: normal|saida`), não pela largura do satélite.
- **Picos de muro/escape** nas transições (defeito antigo): 7 corrigidos (esq 376–394, 580–594, 2242–2266,
  4010–4034; dir 2178–2270, 2468–2510, 3428–3460). Efeito colateral: 280 das 7.052 árvores mudaram de lugar,
  porque o sorteio usa a distância do muro (separar o sorteio por tentativa antes dos setores).
- **Conferência:** `build/interlagos/overlay_perfil/` (perfil final sobre o satélite, desenrolado e de cima, por
  setor) e `build/interlagos/perfil/diferencas.md` (zebra a zebra + o que não foi aplicado, por setor, para as
  Fases 3–10). Folha: `build/ref/interlagos/folhas/fase2_final/folha_01..04.jpg` (16 pares).
- **Bench (`--disable-vsync --track=interlagos`), Fase 1 → agora:** Mínimo 5,16 → 5,18 ms (150 draw calls);
  Leve 5,43 → 5,40 ms (295); Médio 14,39 → 14,23 ms (349 draw calls, 543k → 540k triângulos).
- **Testes:** 10 de 10 OK. O `arredores.gd` falhava em 4 itens porque o teste estava desatualizado em relação
  à tabela `DETAIL` do `surroundings_view.gd` (Leve: torcida 260 m; Extremo igual ao Médio, 400 m / 2.400 m; a
  torcida já vem em 10 blocos do gerador). Nada a ver com as Fases 1 e 2. As 4 expectativas do teste foram
  atualizadas para os valores do código.
- **Pendências:**
  - Visual × física divergentes até a 2B: 12 trechos com zebra só no visual, 23 com zebra da física escondida.
  - Muro medido no satélite não é confiável (só candidato); distâncias de muro e larguras de escape ficam para a
    2B e os setores, já com a linha central corrigida.
  - Âncoras medidas × cenário: passarela 292–297 × 264,6; pórtico da Reta Oposta 988–1001 × 1038,5; saída dos
    boxes 830–895 × 734–794. Linha de chegada não é visível no satélite; a ressalva de `s` da Fase 0
    (3276 → 186) continua aberta e fecha no remapeamento do atlas da 2B.
  - Zebras só do satélite, sem conferência no vídeo: esq 2738, 3352–3412, 3660–3696; dir 2750–2810, 3240–3252,
    3334–3364. Possível zebra não detectada em esq 3290–3352 (Fase 9).
  - As listas de transição do perfil guardam valores da física antiga: refazer na 2B.

### Fase 2B — Geometria física refeita (aprovada: zera o placar)
Mesmo processo de Laguna Seca (`GUIA-PISTAS.md` §1–4), antes dos setores para não refazer detalhe duas vezes.
- Relevo e camber pelo LiDAR do GeoSampa (confirmar cobertura; se não cobrir, manter o relevo atual e refazer só
  larguras, zebras, escapes e muros pelo satélite).
- Linha central recentralizada pelas bordas do asfalto medidas; `wl`/`wr`, `kerbL`/`kerbR`, `runL`/`runR`,
  `wallL`/`wallR` reais; `bank` no `track.json`.
- Nova versão dos recordes (`recordes-interlagos-v4`), referência do Garage 61 reconvertida, testes de paridade e
  de pista atualizados; o `atlas.json` é remapeado para o novo `s` pelas mesmas âncoras.
- **Pronto quando:** comprimento a ≤ 0,5% do oficial (4.309 m), RefBot dá volta válida a ≤ 3% do tempo real,
  velocidade mínima por curva a ≤ 10 km/h do Garage 61, suíte de testes verde.

**Resultado (23/11/2026) — feita, aguardando o Davi olhar a folha:**
- **Fonte própria:** Interlagos deixou de vir do jogo web (`../gt3-time-attack`, TUMFTM alisado + SRTM 30 m, sem
  camber). Agora é `tools/tracks/interlagos/` como Laguna e Imola: `build_track.py --lidar` → `interlagos.json` →
  `tools/pista.ts -- interlagos` → `data/track/`. O `prep.ts` não grava mais pista/relevo/OSM/referências de
  Interlagos. Passo a passo completo em `tools/tracks/interlagos/LEIA-ME.md`.
- **Traçado (satélite + GPS):** linha central recentralizada pelas bordas do satélite; borda × satélite mediana
  ~0,1–0,2 m, p95 ~1 m (antes 1,3–1,5 m / ~4 m). Comprimento **4.308 m** (oficial 4.309; antes 4.294), amostras a
  2,00 m. Asfalto mediano 12,9 m. Deslocamento da linha: mediana 0,9 m, máximo 4,5 m (Lago); `s` muda até 16 m
  (`s_antigo_novo.json`). Linha de chegada no mesmo ponto; referencial do mundo mantido (GPS e satélite ficam
  ~3 m deslocados do OSM: só anotado). Zebras da física = tabela da Fase 2. Correções locais: saída dos boxes com
  escape asfaltado, Bico de Pato estreitado (muro baixo), Subida dos Boxes e dois calombos alisados.
- **Relevo e camber (LiDAR GeoSampa/PMSP 2017):** 36 folhas LAZ (bucket público `laz-m3dc-pmsp`), piso pelas
  classes 2 + 20 (a classe 2 sozinha fica ~0,15 m abaixo do asfalto), registro LiDAR × mundo (+1,50, −1,75) m.
  Desnível 43,1 m. Camber com o lado de fora mais alto em 98% das amostras em curva (S do Senna 8,1°, Subida dos
  Boxes 5,7°, Mergulho 4,5°, Ferradura −2,5°). Aceleração vertical das 6 voltas × pista: **0,032 g rms** (relevo
  antigo 0,21 g); a crista falsa da Ferradura sumiu. Altura de copa (`copa.npy`) pronta para as árvores (§5 B).
- **Muros:** medidos (OSM, satélite, barreiras desenhadas); mínimo de 1,5 m da borda em Interlagos (1,3 m na
  Goodyear do Lago), Laguna/Imola seguem 2,5 m. Nenhuma das 6 voltas passa além do muro. Corrigidos depois da
  conferência do GLB: separador da saída dos boxes, Goodyear do Lago, S do Senna (cerca a ~27 m, grama larga como
  no LMU) e Bico de Pato.
- **Referências e recordes:** 6 voltas do Garage 61 → `data/reference/interlagos-{nsx,ferrari,mclaren,m4,
  corvette,porsche}.json` (a antiga `interlagos-r8` foi substituída); os 6 carros do jogo têm referência (R8 usa a
  do NSX). Recordes zerados: `recordes-interlagos-v4` (sim) e `recordes-interlagos-arcade-v4`, fantasma
  `interlagos-v4`, placar online em `interlagos-v4-godot.json` / `interlagos-v4-godot-arcade.json` (os antigos
  ficam no `gt3-tempos` como histórico).
- **RefBot (`scripts/tests/interlagos.gd`):** os 6 carros fazem volta válida a **+1,07% a +1,50%** do iRacing
  (antes +3,3–3,4%, e NSX/488/720S rodavam na Ferradura); mínimas por trecho a ≤ 6,7 km/h; câmera com folga
  ≥ 0,17 m. Nenhuma pendência no teste.
- **Cenário na pista nova:** o gerador monta a mesma pista da física (posição 0,01 cm) e para com erro se
  divergir. Perfil, 45 posições fixas do código e atlas do vídeo remapeados para o `s` novo
  (`tools/cenario/interlagos/sNovo.ts`, `migrarPerfil2B.ts`; atlas em `atlas_v2.json`, quadros `chase_v2/`, nome =
  s novo). Zebras visual = física amostra a amostra; barreiras do perfil no muro da física. Conferência do GLB
  (`tools/cenario/interlagos/conferir_glb.py`): asfalto a ≤ 4 cm da física, nenhuma árvore/prop no asfalto ou
  dentro do muro, barreira dentro do limite da física ≤ 0,35 m (amostragem). Laguna e Imola byte a byte iguais.
- **Folha:** `build/ref/interlagos/folhas/fase2b_muros/folha_01..04.jpg` (16 pares, s novo).
- **Bench (`--disable-vsync --track=interlagos`, 1ª rodada × 1ª rodada da Fase 2):** Mínimo 5,36 → 5,20 ms
  (150 draw calls); Leve 5,38 → 5,44 ms (293); Médio 14,21 → 14,51 ms (348, 543k triângulos). Zebras e linhas
  visíveis no Mínimo.
- **Testes:** os 23 scripts de `scripts/tests` passam (paridade web × Godot na pista nova, com camber).
- **Pendências:**
  - Goodyear do Lago: a barreira desenhada (e agora o muro da física) fica colada na zebra em s ~1394–1582; no
    quadro do LMU em s 1407 há grama e guard-rail baixo. Conferir a posição real na Fase 6.
  - Âncoras ainda fora do lugar (setores): passarela, pórtico da Reta Oposta, saída dos boxes (Fase 2).
  - Bico de Pato dir: muro de 14 m é limite geométrico, não barreira medida.
  - Pior resíduo de aceleração vertical em s ≈ 4038 (Arquibancadas, +0,24 g): causa não identificada.
  - `maxRunoff` não definido; pontos do bench (`CHECKPOINTS`) ainda nos metros antigos; `atlas_video.py` e
    `ref_garage61.py` seguem na pista antiga (o atlas v2 é derivado pelo mapa).
  - A pista do jogo web (`gt3-time-attack`) continua a antiga.

### Fases 3 a 10 — Setores, um por sessão

| Fase | Setor | `s` (m) | Destaques a resolver |
|:---:|:---|:---:|:---|
| 3 | Reta dos boxes + freada do S | 3884–4294, 0–250 | grid, muro dos boxes, alambrado, pórtico, placas 200–50, arquibancadas |
| 4 | S do Senna + Curva do Sol | 250–776 | zebras internas e salsichas, escape verde/amarelo, tendas, saída dos boxes |
| 5 | Reta Oposta | 776–1362 | faixa vermelha + verde, banners, guard-rail, morro com carros, placas |
| 6 | Descida do Lago + subida | 1362–1976 | barreira azul dupla colada na zebra, lago, caixa d'água, escapes |
| 7 | Ferradura + Laranjinha | 1976–2278 | muro com banner, costas das arquibancadas, grama seca, zebra amarela |
| 8 | Esse + Pinheirinho + Bico de Pato | 2278–2868 | zebras de ápice, postos de fiscal, barrancos, banners |
| 9 | Mergulho + Junção + Café | 2868–3578 | zebra de saída, tendas brancas, prédios da cidade ao fundo, alambrado |
| 10 | Subida dos Boxes + arquibancadas | 3578–3884 | atenuador laranja, entrada dos boxes, telão, torcida, guard-rail |

**Roteiro fixo de cada setor:**

1. Folha lado a lado do setor a cada 25 m na perseguição (≤ 16 pares) + até 8 pares onboard nos pontos-chave.
2. **Ficha do setor** (`build/ref/interlagos/fichas/setor-N.md`): lista item a item, por lado, da linha branca
   para fora — zebra → pintura/brita/grama → barreira → alambrado → o que está atrás (tendas, prédios, árvores,
   placas). Cada item com `s`, o que o LMU mostra, o que temos e a correção.
3. Corrigir no `visual_profile.json` e nos geradores. Iterar com `node cenario.mjs --preview` (segundos, já
   existe) e só no fim exportar o GLB e capturar no Godot.
4. Árvores do setor (§5).
5. Fechar: folha final, ficha com todos os itens marcados, `--bench` no Mínimo e no Leve, testes da pista.
6. **Pronto quando:** o Davi aprova a folha e não sobra item "gritante" aberto na ficha. O que ficar de fora vai
   escrito na ficha como pendência, com motivo.

Ordem sugerida: 4 → 6 → 5 → 3 → 7 → 8 → 9 → 10 (começa pelos trechos onde a diferença é mais visível).
Desde a Fase 2B os setores usam o **s novo** (pista de 4.308 m); converter os limites da tabela por
`tools/tracks/interlagos/s_antigo_novo.json` (setor 4: 250–783).

**Resultado da Fase 4 (23/11/2026) — feita, aguardando o Davi olhar a folha:**
- Ficha `build/ref/interlagos/fichas/setor-4.md`; folhas `build/ref/interlagos/folhas/fase4_ini_*` (22 pares de
  perseguição + 8 onboard) e `fase4_fim_*` (mesmos pontos). Perfil do setor por `tools/cenario/interlagos/
  setor4_perfil.py` (reescreve só 250–783).
- **Escapes:** verde-água até o muro ROLEX nos dois lados do S (250–326 esq, 250–518 dir); ápice do S com verde de
  6 m e saída com 8 m; grama sem pintura onde o LMU não tem escape; faixa verde-água de 0,5 m atrás da zebra
  interna da Curva do Sol; saída da Curva do Sol com zebra larga + vermelho liso + faixa verde junto do muro MOTUL
  (tipo novo `escape.fora` no `perfil.ts`).
- **Física (muros pelo satélite):** separador da saída dos boxes recuado para o fim da grama (borda + 9,0 → 6,5 →
  7,3 m, s 566–748); muro MOTUL da saída da Curva do Sol a borda + 15 m (s 722–779). RefBot igual à 2B
  (+1,07–1,50%), paridade 0,00%.
- **Passarela:** s 264,6 → 294,6 (satélite + pilar no vídeo). **Tendas:** 7 brancas em pirâmide atrás do muro +
  14 contêineres.
- **Árvores:** sorteio agora local (`sorteio.ts`: semente por tentativa/polígono/posição), então editar um setor
  não mexe no resto (mudança única: todas as árvores trocaram de lugar uma vez). Etapa A no setor
  (`arvoresSetor.ts` + bloco `arvores` do perfil: zonas por s/lado, espaçamento ≥ 5 m, copa do LiDAR): 1.035 →
  323 árvores no setor; volta 7.050 → 6.197. Escala mantida em ~2,1–3,25× (base 2,6 × 0,8–1,25), porque os
  modelos têm 3–5 m; decidir na Etapa C com a altura de copa do LiDAR.
- **Conferências:** `conferir_glb.py` sem regressão (asfalto ≤ 4 cm, zebras = física, nada dentro do muro);
  Laguna e Imola byte a byte iguais; 24 testes headless passam.
- **Bench:** Mínimo ~5,0–5,1 ms, igual a antes. **Leve e Médio sem conclusão:** a máquina estava com BlueStacks
  e o Le Mans Ultimate abertos e as rodadas iguais variaram 2–3× (Médio 26–64 ms no mesmo ponto). Draw calls e
  triângulos iguais aos do GLB anterior. O Davi decidiu pular a nova medição; repetir na próxima fase com a
  máquina parada.

**Resultado da Fase 6 (23/11/2026) — feita, aguardando o Davi olhar a folha:**
- Ficha `build/ref/interlagos/fichas/setor-6.md`; folhas `build/ref/interlagos/folhas/fase6_ini_*` e `fase6_fim_*`
  (s novo 1369–1982). Perfil do setor por `tools/cenario/interlagos/setor6_perfil.py`; funções comuns dos setores
  em `perfil_setor.py` (o setor 4 regenera byte a byte igual).
- **Barreira Goodyear (pendência da 2B):** não fica colada na zebra em 1394–1488 — ali o LMU tem zebra, grama
  larga e guard-rail baixo (muro da física a borda + 9 m). A barreira azul dupla vai de **s 1490 a 1658**, com a
  face a borda + 2,6 m (vídeo + satélite; ±0,5 m), e segue simples, sem faixa DHL, até ~1802. Agora vem do
  perfil (`tecpro2`); `buildDescidaLagoGoodyear` removida; `wallMinGap` voltou a 1,5 m. As barreiras azuis
  passaram a `ess_` (sumiam no Mínimo).
- **Física:** muro esq como acima; muro dir na beira do lago (borda + 15–27 m em 1446–1690); zebra dir do Lago
  1478–1527 (vídeo). RefBot igual (+1,07–1,50%), paridade 0,00%.
- **Escapes:** verde-água estreito atrás da zebra esq (1370–1488); verde até a Goodyear; verde / verde-água até a
  margem do lago à direita; grama onde o LMU não pinta; verde-água largo na subida (1840–1900).
- **Árvores:** 958 → 177 no setor (talude gramado no LMU e copa ≈ 0 no LiDAR); volta 6.197 → 5.416; as 5.239 de
  fora do setor não mudaram (`arvores.ancora` congela o muro antigo como âncora do sorteio).
- **Infraestrutura:** marcas de pneu com sorteio por curva (`trackside.ts`); as 15 da volta trocaram de lugar uma
  vez, e daqui em diante mudar um setor não mexe nas outras.
- **Conferências:** `conferir_glb.py` sem regressão (zebras visual = física; nada dentro do muro); Laguna e Imola
  byte a byte iguais; 24 testes headless passam.
- **Bench:** BlueStacks e LMU abertos de novo; draw calls e triângulos iguais ao GLB anterior, Mínimo 5,0 ms;
  Leve/Médio sem conclusão.
- **Pendências:** fim da zebra esq (~1630–1645); ponteira laranja (~1795); outdoor Goodyear ~25 m adiante; emenda
  de grama de 2 m em 1528; texto Goodyear pequeno; cone em ~1960; faixa verde-água de 1370–1488 talvez larga; a
  volta do M4 passa 1,14 m além da borda + zebra em s 1525 (fim da zebra no limite do vídeo).
- **Pendências do setor:** muro esq 440–480 parece perto demais (conferir no satélite antes de mexer na
  física); emenda do vermelho com a Reta Oposta em 779–790 (Fase 5); logo ROLEX e faixas amarelas pintadas no
  ápice; muro de arrimo/estacionamento à direita (450–600) e torre de concreto (650–730); remendo escuro no
  asfalto em s 480 e cones em s 300.

### Fase 11 — Passada final da volta inteira
- Volta completa em movimento (`--mover`) nas duas câmeras, folha a cada 50 m, nos 4 presets.
- Vídeo curto lado a lado (ffmpeg) LMU × jogo, sincronizado por `s`, para o Davi assistir.
- Atualizar `AGENTS.md` e `GUIA-PISTAS.md` com o processo (vira o padrão para Laguna e Imola).

---

## 5. Árvores (revisão do `PLANO-ARVORES.md` para Interlagos)

O plano de árvores continua válido na parte de modelos e shader, mas a ordem muda: **primeiro onde e quantas,
depois como são**. Nos pares, o problema maior não é o billboard e sim a parede contínua de árvores iguais onde o
LMU mostra campo aberto, morro, estacionamento e os prédios da cidade.

- **Etapa A (dentro de cada setor, barata):** zonas de exclusão e de mata declaradas por `s` e lado no perfil,
  tiradas do vídeo e do satélite; espaçamento mínimo entre troncos; escala 0,8–1,25 em vez de 2–3,5×. Meta da
  volta: de 7.052 para ~3.500–4.500.
- **Etapa B (depois da Fase 6, uma sessão):** posição e altura reais das copas pelo LiDAR do GeoSampa (superfície
  menos terreno), se a cobertura de Interlagos se confirmar. Substitui o plantio por regra.
- **Etapa C (depois da Fase 10):** espécies novas e shader (Etapas 1–4 do `PLANO-ARVORES.md`): 4 espécies para
  Interlagos em vez de 7 de uma vez, 3D perto da pista + impostor sem imagem dupla, atlas menor (20 MB → < 8 MB).

---

## 6. Ferramentas (todas gratuitas)

**Já temos e vamos usar**
- **FFmpeg + Python (Pillow, NumPy):** atlas do vídeo, folhas, medição de cor. Instalados.
- **`cenario.mjs --preview`:** preview do cenário em segundos, sem exportar GLB. Já existe.
- **Blender 4.5 + Blender MCP:** instalado (`C:\Users\davim\Tools\blender-mcp`), mas **não está ligado a esta
  sessão do Claude Code** (estava no Antigravity). Ligar com um `.mcp.json` no repo. Uso: props sob medida dos
  marcos de Interlagos (torre, telão, atenuador, posto de fiscal, caixa d'água) e árvores. Nunca no `cenario.glb`.
- **Godot MCP:** mesma situação (`C:\Users\davim\Tools\godot-mcp`). Útil para inspecionar a cena viva e erros.

**Recomendo acrescentar**
- **OpenCV (`pip install opencv-python`):** alinhamento e diferença entre quadros, máscara por cor para medir
  zebras e faixas no satélite. Opcional; o básico sai com Pillow/NumPy.
- **Satélite Esri 0,25 m** e **LiDAR do GeoSampa** (Prefeitura de SP): larguras, zebras, relevo e altura das
  copas. Mesmo processo de Laguna Seca.
- **Mais um vídeo de referência (yt-dlp):** este vídeo tem texto grande cobrindo o terço de cima em vários
  trechos. Um replay do LMU com câmeras de TV/externas, sem legenda, ajuda nos prédios e fundos.
- **Mapillary / fotos de solo:** conferir cor de muro, placas e detalhes de paddock.
- **Poly Haven / ambientCG (CC0):** texturas de grama seca, brita, concreto e folhagem.

**Não recomendo**
- **Higgsfield e geradores de vídeo/imagem por IA:** criam imagem bonita, mas não geometria nem medida de pista, e
  o plano grátis é limitado. Não ajudam neste objetivo.
- **Fotogrametria do vídeo (COLMAP/Meshroom):** grátis, mas vídeo de jogo com desfoque e HUD dá reconstrução
  ruim. Só como experimento isolado para um marco específico, se sobrar tempo.

**Garage 61:** não é bloqueio. Hoje só há uma volta de Interlagos (R8) e o CSV bruto não está em `garage61/`.
Ajudaria ter **2–3 voltas de carros diferentes com GPS**: melhora a linha de borracha, as marcas de freada e o
posicionamento das placas, e dá margem para o item do §8.

---

## 7. Regras que continuam valendo

- Celular primeiro: Mínimo e Leve sem luz dinâmica, sem pós pesado; `--bench` em todo fechamento de fase.
- Zebras, brita, faixas, muros e placas (`ess_`) visíveis no Mínimo.
- Pista só por gerador (`tools/cenario/`), nunca editando o GLB.
- Brutos (satélite, LiDAR, quadros, fichas) em `build/`; só JSON processado vai para o git.
- Câmera do jogo não muda (a de comparação é só da captura).
- Sem commit/push sem o Davi pedir.

---

## 8. Decisões do Davi (20/11/2026)

1. **Geometria física:** pode refazer tudo e zerar o placar → Fase 2B.
2. **Marcas reais nos banners e placas:** sim, o mais próximo possível do vídeo; o jogo não será comercializado
   (`GUIA-PISTAS.md` atualizado).
3. **Ordem dos setores:** a sugerida (4 → 6 → 5 → 3 → 7 → 8 → 9 → 10).
4. **MCPs:** Blender MCP e Godot MCP ligados no Claude Code (`.mcp.json`).
5. **Modelos:** Fable 5.2 planeja e confere; Opus 5.5 executa.
6. Folhas comparadas no Médio; Mínimo e Leve conferidos no fechamento de cada fase.

---

## 9. Estimativa

| Bloco | Sessões |
|:---|:---:|
| Fase 0 (atlas + captura alinhada) | 1 |
| Fase 1 (aparência global) | 1–2 |
| Fase 2 (perfil pelo satélite + gerador) | 2 |
| Fase 2B (geometria física + recordes) | 2 |
| Fases 3–10 (8 setores) | 8 |
| Árvores B e C | 2–3 |
| Fase 11 (final) | 1 |

Cada sessão entrega algo visível e aprovado; dá para parar entre quaisquer duas.
