# Plano de Implementação — WeatherTech Raceway Laguna Seca (`gt3-godot`)

Este documento define o plano completo para adicionar **WeatherTech Raceway Laguna Seca (EUA)** ao `gt3-godot`, estruturando o suporte multi-pista no projeto e garantindo alta fidelidade já na **primeira versão** (elevação real, traçado, zebras, brita, referências de freada, telemetria do Garage 61 e comparação visual com vídeo do Le Mans Ultimate).

---

## Princípios desta Implementação

1. **Precisão geométrica e altimétrica antes do polimento visual:** usar dados reais de **LiDAR/DEM 1 m (USGS 3DEP)** + **OpenStreetMap** + **telemetria do Garage 61** para fechar comprimento (~3.602 m), elevação do *Corkscrew* e larguras antes de congelar o cenário.
2. **Suporte multi-pista limpo:** sair do acoplamento atual a uma única pista (`data/track/*`, `assets/track/*`) para `data/tracks/<id>/*` e `assets/tracks/<id>/*`, mantendo Interlagos intacta.
3. **Bioma e referências fiéis ao LMU:** adaptar terreno, vegetação, caixas de brita, placas de frenagem e horizonte ao vale árido de Monterey (Califórnia), validando frame a frame contra vídeo onboard do LMU.
4. **Celular primeiro:** respeitar o orçamento dos presets `Mínimo`, `Leve`, `Médio` e `Extremo` já usados no projeto (placas de frenagem, zebras, brita e barreiras sempre visíveis no `Mínimo`).

---

## Fase 0 — Coleta de Dados Reais e Referências (Pré-construção)

Antes de gerar arquivos, reunir e validar as fontes que alimentam o pipeline:

1. **Elevação de Alta Resolução (USGS 3DEP — 1 metro):**
   - Área: WeatherTech Raceway Laguna Seca, Monterey County, CA (`~36.584° N, -121.753° W`).
   - Baixar o recorte DEM 1 m (GeoTIFF) cobrindo a pista + `PAD` de ~800 m–1.000 m ao redor (importante porque os morros do vale em volta da pista são muito visíveis).
   - Pontos críticos a conferir no perfil altimétrico:
     - Subida da saída da **Curva 6** até a crista da **Curva 8 (Corkscrew)** (~33 m de ganho acumulado no setor).
     - Queda do **Corkscrew (T8 → T8A)**: ~18 m de desnível em ~140 m (~16% de inclinação) + transição de compressão na saída para a **Rainey Curve (T9)**.
     - Declive de **T9 → T10** e reta principal plana/leve subida até a crista cega da **Curva 1**.
2. **Traçado, Larguras e Entorno (OpenStreetMap / Overpass API):**
   - Extrair centerline, pit lane, caixas de brita, prédios do paddock, torre de controle, arquibancadas, pontes de pedestres e áreas de vegetação/árvores.
   - Conferir largura real da pista (~12 m a 15 m dependendo do trecho) e posições exatas dos muros e barreiras de pneus.
3. **Telemetria de Referência (Garage 61 — iRacing GT3):**
   - Coletar 1–3 voltas limpas de GT3 em Laguna Seca (CSV/JSON do Garage 61) com: distância (`s`), coordenadas/velocidade, throttle, brake, marcha e traçado.
4. **Vídeo Referência (Le Mans Ultimate — LMGT3):**
   - Extrair frames-chave do vídeo onboard do LMU (mesmo fluxo de `build/compare/lmu/` usado em Interlagos) cobrindo todos os setores: Reta/T1, Andretti Hairpin (T2), T3, T4, T5, T6, Topo do Corkscrew (T8), Descida do Corkscrew (T8A), Rainey Curve (T9), T10 e T11.

---

## Fase 1 — Arquitetura Multi-Pista no `gt3-godot` e Pipeline

Atualmente, `tools/prep.ts`, `tools/cenario.mjs`, `tools/arredores.mjs`, `scripts/main.gd`, `scripts/track/track_view.gd`, `scripts/track/surroundings_view.gd` e `scripts/ui/records.gd` apontam diretamente para caminhos fixos (`res://data/track/...` e `res://assets/track/...`).

### 1.1 Estrutura de Dados por Pista
- Criar índice `data/tracks.json` com metadados de cada pista:
  - `id` (`"interlagos"`, `"laguna-seca"`)
  - `name`, `short`, `country`, `length_m`, `corners`
  - `sun_u`, `sun_elev` (iluminação adequada à latitude/vídeo de referência)
  - `biome` / parâmetros visuais (cores de grama/terra, presença ou não de torres distantes)
  - `refs`: mapa `car_id -> reference_file` (ex.: `laguna-seca-r8`)
- Organizar arquivos por pista:
  - `data/tracks/<track_id>/track.json`, `terrain.json`, `osm.json`, `arvores.json`, `arvores_pos.json`, `horizonte.json`, `torres.json`
  - `assets/tracks/<track_id>/cenario.glb`, `horizonte.png`
  - `data/reference/<track_id>-<car>.json`

### 1.2 Adaptação dos Scripts GDScript e UI
- **`scripts/game.gd`:**
  - Adicionar `static var track_id := _load_track()` (padrão `"interlagos"`, persistido em `user://jogo.cfg`, com override por `--track=<id>` na linha de comando).
  - Helpers `Game.get_tracks_list()`, `Game.get_track_info(id)`, `Game.track_data_path(file)` e `Game.track_asset_path(file)`.
- **`scripts/main.gd`:**
  - Carregar `Track.new(Game.track_data_path("track.json"))` e configurar `sun` (`SUN_U`, `SUN_ELEV`) a partir de `data/tracks.json`.
  - Selecionar referência automática do piloto automático usando `track_id` + `car_id`.
- **`scripts/track/track_view.gd` e `scripts/track/surroundings_view.gd`:**
  - Substituir constantes fixas (`GLB`, `TREES`, `TOWERS`, `HORIZON`, `HORIZON_TEX`) por caminhos dinâmicos baseados em `Game.track_id` (e permitir `torres.json` vazio sem erro quando a pista não tiver prédio residencial ao redor).
- **`scripts/ui/records.gd`:**
  - Isolar chaves de recordes locais e remotos por `(track_id, car_id, mode)` para não misturar tempos de Interlagos com Laguna Seca.
- **`scripts/ui/garagem.gd` / `scripts/ui/lmu_menu.gd`:**
  - Adicionar seletor de pista (Interlagos / Laguna Seca) antes de iniciar a sessão.

### 1.3 Parametrização das Ferramentas (`tools/`)
- Atualizar `tools/prep.ts`, `tools/cenario.mjs` e `tools/arredores.mjs` para aceitar `--track=<id>` (padrão `interlagos`), lendo a pista correspondente e escrevendo em `data/tracks/<id>/` e `assets/tracks/<id>/`.

---

## Fase 2 — Geometria, Elevação (LiDAR) e Suporte a Camber

### 2.1 Construção do Traçado Base (`track.json`)
- Gerar amostras a cada `STEP = 2.0 m` no formato `stride = 16` (`P`, `T`, `R`, `wl`, `wr`, `kerbL`, `kerbR`, `runL`, `runR`, `wallL`, `wallR`) + `sections` oficiais:
  1. Start/Finish & Turn 1 (kink rápido em crista cega)
  2. Turn 2 — **Andretti Hairpin** (grampo duplo / freada forte)
  3. Turn 3 & Turn 4 (curvas médias para a direita)
  4. Turn 5 (curva para a esquerda em subida leve, com banking favorável)
  5. Turn 6 (curva rápida cega para a esquerda antes da subida principal)
  6. Rahal Straight (subida forte até o Corkscrew)
  7. Turn 8 / 8A — **The Corkscrew** (freada em subida cega → esquerda fechada → queda acentuada para a direita)
  8. Turn 9 — **Rainey Curve** (curva longa e rápida em descida para a esquerda)
  9. Turn 10 (direita média com brita externa próxima)
  10. Turn 11 (grampo final de 90°+ para a esquerda antes da reta)

### 2.2 Qualidade da Elevação e Transições Verticais
- Projetar o centerline no DEM USGS 1 m e aplicar suavização controlada (spline/Savitzky-Golay ou janela adaptativa) apenas para remover ruído de amostragem do DEM **sem achatar** a crista do T1, a compressão do fundo da T6 nem a queda do Corkscrew.
- Manter precisão de `0,1 mm` (`r4`) nas exportações, evitando micro-degraus a cada 2 m que causam quique na suspensão.

### 2.3 Camber / Banking das Curvas (Ponto Crítico de Física)
- Em `scripts/track/track.gd` (linha 60), `R` atualmente é projetado no plano horizontal (`Vector3(s[o + 6], 0, s[o + 7]).normalized()`), o que zera qualquer inclinação lateral (*camber*).
- Laguna Seca depende muito de camber positivo nas curvas **T5, T6, Rainey Curve (T9), T11** e da inclinação lateral composta no **Corkscrew (T8/T8A)**.
- **Ação no plano:** avaliar e habilitar `R.y` opcional (ou campo de camber/inclinação lateral no `track.json`) em `Track._init` e na geração da malha do asfalto, validando que Interlagos (`R.y = 0`) permanece idêntica.

### 2.4 Zebras, Escapes e Caixas de Brita
- Mapear lado a lado (`kerbL`, `kerbR`) a partir do vídeo do LMU e fotos aéreas:
  - Zebras pintadas planas vs. zebras elevadas (`KERB_H` / `KERB_RIPPLE`) e zebras tipo "salsicha" internas onde existirem (como T6 / T8A / T11, se presentes no LMU).
- Configurar `runL`/`runR` e `wallL`/`wallR` distinguindo claramente:
  - Faixa de asfalto/concreto de escape imediato
  - **Caixas de brita grandes** (característica marcante de Laguna Seca — quase toda curva tem brita larga logo após a zebra)
  - Grama/terra seca até os muros de concreto e barreiras de pneus.

---

## Fase 3 — Validação Física com Logs do Garage 61

Antes de investir tempo no acabamento visual fino, validar a dirigibilidade e os tempos de volta:

1. Converter a volta de referência do **Garage 61** para `data/reference/laguna-seca-<carro>.json` alinhada ao `s` da pista.
2. Rodar o piloto automático (`ref_bot.gd` / `bot.gd`) em Laguna Seca e comparar:
   - Comprimento total da volta (meta: dentro de ~0,5% dos **3.602 m** oficiais).
   - Perfil de elevação `y(s)` vs. altitude do log do Garage 61.
   - Velocidades mínimas por curva (T2 Andretti, T3, T4, T5, T6, T8/T8A Corkscrew, T9 Rainey, T10, T11) e pontos de freada.
   - Comportamento de suspensão/fundo de carro na saída do Corkscrew e na compressão da T6/T9.
3. Ajustar geometria (`P.y`, camber, `wl`/`wr`, `kerbL`/`kerbR`) até o carro acompanhar a telemetria sem raspar indevidamente nem perder aderência artificial.

---

## Fase 4 — Visual, Bioma Californiano e Comparação com o LMU

### 4.1 Terreno e Horizonte (`terrain.json` e `horizonte.png`)
- Gerar `terrain.json` usando o DEM USGS 1 m com margem ampla para capturar os morros ao redor do autódromo (especialmente atrás de T2–T5 e acima do Corkscrew).
- Gerar `horizonte.png` específico de Laguna Seca (silhueta dos morros californianos sob céu claro/seco, sem o skyline urbano de São Paulo).
- **Sem torres residenciais:** `torres.json` vazio (`[]`), pois a região é reserva/vale aberto.

### 4.2 Materiais e Bioma Árido
- Calibrar `shaders/asfalto.gdshader` e `shaders/grama.gdshader` (ou parâmetros por pista) para o visual do LMU em Laguna Seca:
  - **Asfalto:** cinza-claro/médio gasto pelo sol, com trilho de borracha bem marcado nas zonas de freada (T2, T5, T8, T11).
  - **Solo/Grama:** tons de palha dourada, ocre e verde-oliva seco (típico da Califórnia), com variação de manchas no terreno.
  - **Brita:** textura e cor bege-acinzentada/arenosa bem distinta do asfalto e do mato seco (garantir visibilidade clara inclusive no `Mínimo`).

### 4.3 Marcos Visuais e Pontos de Referência de Pilotagem
Priorizar os elementos que o piloto usa para frear e se localizar:
- **Placas de frenagem** (`400 / 300 / 200 / 100` conforme referência do LMU) em T2, T5, T8 (Corkscrew), T10 e T11 — sempre visíveis em todos os presets, incluindo `Mínimo`.
- **Pontes e pórticos:** ponte/pórtico da reta principal, ponte antes da T5/T6 e ponte após a T8A/T9 (conforme layout atual no LMU).
- **Paddock e boxes:** torre de controle característica de Laguna Seca, garagens/boxes, tendas de paddock e arquibancadas principais.
- **Detalhes icônicos:** bandeira americana no alto do Corkscrew, barreiras de pneus vermelhas/brancas/azuis, guard-rails e cones de referência.
- **Vegetação (`arvores_pos.json`):** carvalhos californianos (*California live oak*) esparsos nos morros e em torno do paddock (muito menos denso que a mata de Interlagos).

### 4.4 Comparação Lado a Lado (LMU vs. Godot)
- Adaptar `scripts/tests/capture_compare.gd` para aceitar a lista de checkpoints de Laguna Seca.
- Gerar os prints em `build/compare/laguna_seca/` e comparar lado a lado com os frames extraídos do vídeo do LMU, ajustando cores, contraste de brita/grama, posição de placas e altura de barreiras.

---

## Fase 5 — Otimização, Testes e Checklist de Entrega

- [ ] **Multi-pista:** Interlagos continua carregando e rodando normalmente (sem regressão).
- [ ] **Seleção & CLI:** possível escolher Laguna Seca na UI e via `--track=laguna-seca`.
- [ ] **Recordes:** tempos locais/remotos separados por pista.
- [ ] **Física & Garage 61:** volta completa validada contra log do Garage 61 (comprimento, elevação do Corkscrew, velocidades de curva e camber).
- [ ] **Visual LMU:** frames comparados com o vídeo do LMU aprovados; brita, zebras e placas de frenagem nítidas em todos os presets (`Mínimo` a `Extremo`).
- [ ] **Desempenho Mobile:** `Mínimo` e `Leve` dentro do orçamento de FPS/draw calls (árvores esparsas + sem torres distantes ajudam Laguna Seca a ser ainda mais leve que Interlagos).
- [ ] **Testes automatizados:** rodar a suíte em `scripts/tests/` após as alterações finais e validar carregamento das duas pistas.

---

## O que você pode enviar quando formos começar

1. **Vídeo de referência do LMU** em Laguna Seca (LMGT3) — pode colocar na raiz ou em `build/compare/` como fez com Interlagos.
2. **Log(s) do Garage 61** (CSV/JSON) de alguma volta GT3 em Laguna Seca.
3. Assim que enviar (ou confirmar o início), eu já puxo os dados de **elevação USGS 1 m** e **OpenStreetMap** para começarmos pela **Fase 1 e Fase 2**.
