# Plano de Melhoria Visual da Pista (Interlagos) — Comparativo LMU

Este plano define as etapas para elevar a qualidade visual e a atenção aos detalhes da pista de Interlagos no `gt3-godot`, usando como referência o vídeo real de um Porsche em Interlagos no **Le Mans Ultimate (LMU)** (`INTERLAGOS-IN-LE-MANS-ULTIMATE-LMGT3-Track.mp4`).

**Princípios desta etapa:**
- **Atenção máxima ao básico ao redor da pista:** cores do asfalto, mato/grama, caixas de brita bem diferenciadas da pista, faixas verdes e vermelhas de escape, zebras, muros/barreiras, faixas brancas e placas de frenagem têm que ficar **bem feitas em todos os modos** (inclusive no **Mínimo**).
- **Não** mexer em sombras avançadas, iluminação global, SSR/SSIL ou pós-processamento pesado agora.
- **Celular primeiro:** **Mínimo**, **Leve** e **Médio** devem rodar bem no celular, com orçamento claro por nível.
- **Extremo** será uma **cópia do Médio** quanto aos detalhes da pista por enquanto.

---

## Status Atual do Código (o que já veio vs. o que falta)

Verificação direta no repositório (`gt3-godot` + gerador `gt3-time-attack/src/render/*` via `tools/cenario/cenario.ts`):

- **Já implementado / veio no código:**
  - `build/compare/lmu/lmu_01.png` .. `lmu_25.png` e `build/compare/lmu_scan/sheet_01..03.png`: frames de referência do vídeo do LMU já extraídos.
  - `scripts/tests/capture_compare.gd`: script de captura automática em 15 checkpoints de Interlagos pronto para rodar.
  - `scripts/track/surroundings_view.gd`: `DETAIL[0]` já oculta árvores, torcida e torres no `Mínimo` (`0.0`), com culling configurado para `Leve`, `Médio` e `Extremo`.
  - `scripts/track/track_view.gd`: suporte a `fast_mode` nos shaders, desativação de normal maps no `Mínimo` e sistema de culling por distância.
  - `shaders/asfalto.gdshader` e `shaders/grama.gdshader`: já possuem ramificação `fast_mode`.
- **O que ainda NÃO foi feito / problemas identificados no código atual:**
  1. `build/compare/godot_atual/` ainda não foi gerado localmente (`build/` é ignorado no Git).
  2. **Brita ausente / confundida com a pista:** `gt3-time-attack/src/render/trackView.ts` (que gera o `assets/track/cenario.glb`) **não gera caixas de brita reais** com textura/cor de pedrisco — as áreas de escape (`runL`/`runR`) são todas asfalto pintado, e onde falta cor/contraste ou há faixas cinzentas/amarronzadas ao lado da pista, parece brita da mesma cor do asfalto.
  3. **Cores opacas de grama, asfalto, faixas verdes/vermelhas e zebras:**
     - `shaders/asfalto.gdshader` usa multiplicador neutro (`vec3(1.06, 1.01, 0.92)`), distante do cinza-amarronzado quente e da borracha visível do LMU.
     - `shaders/grama.gdshader` (`fast_mode` e completo) multiplica `base_color` por tons que deixam o mato apagado/amarronzado em vez do verde-oliva vivo + palha seca alaranjada do LMU.
     - `runoffTexture` em `trackView.ts` usa verde (`#1f6b42`), verde-água (`#22625a`) e vermelho (`#b3262b`) muito escuros e sujos pelo `weather(..., 30)` — no LMU as faixas verdes e a área vermelha da Curva do Sol são vibrantes e limpas, com faixas brancas bem definidas.
     - `kerbTexture` aplica `weather(..., 40)` excessivo, apagando o amarelo/verde/branco das zebras.
  4. **Placas de frenagem e barreiras sendo escondidas no Mínimo:**
     - `tools/cenario/cenario.ts` mescla malhas secundárias do mesmo material em blocos de 250 m.
     - `scripts/track/track_view.gd` (linhas 131–133) envia para `_minimal_hide_meshes` qualquer malha secundária com `maxf(ext.x, ext.z) > 12.0 or ext.y > 3.5`, o que acaba **ocultando blocos mesclados de placas de frenagem, guard-rails, pneus e postes no Mínimo**.

---

## Matriz de Detalhes por Preset Gráfico

Referência: `Game.QUALITY_LEVELS` (`scripts/game.gd`), `Main._set_quality()` (`scripts/main.gd`), `TrackView.set_detail()` (`scripts/track/track_view.gd`) e `SurroundingsView.DETAIL` (`scripts/track/surroundings_view.gd`).

| Elemento da Pista / Ambiente | 0 — Mínimo (Celular) | 1 — Leve (Celular) | 2 — Médio (Celular / PC) | 3 — Extremo (PC — cópia do Médio) |
| :--- | :--- | :--- | :--- | :--- |
| **Asfalto, borracha, faixas brancas e grid** | Sim (`fast_mode`, cor/contraste calibrados ao LMU) | Sim (`fast_mode` calibrado) | Sim (shader completo: 2 escalas, manchas 18m/45m, normal/ARM) | Igual ao Médio |
| **Zebras (amarelo/verde/branco)** | Sim (cores vivas e nítidas, sem normal map) | Sim (cores vivas, sem normal map pesado) | Sim (com normal map e rugosidade do asfalto) | Igual ao Médio |
| **Escapes pintados (faixas verdes, verde-água e vermelha)** | Sim (cores vibrantes fiéis ao LMU) | Sim | Sim (com relevo/rugosidade) | Igual ao Médio |
| **Caixas de brita (gravel traps)** | Sim (cor/granulação bege-terracota bem distinta da pista) | Sim | Sim (com textura/relevo completo) | Igual ao Médio |
| **Grama / mato ao redor da pista** | Sim (`fast_mode` com verde-oliva + palha seca fiel ao LMU) | Sim | Sim (shader completo com palha, trilhas e normal map) | Igual ao Médio |
| **Muros, barreiras (azul/laranja), guard-rails e pneus** | Sim (sempre visíveis; cores base fiéis) | Sim | Sim (com normal maps completos) | Igual ao Médio |
| **Placas de frenagem (200/150/100/50 m) e pórtico de largada** | **Sim** (sempre visíveis, alcance ≥ 400 m, sem mesclar com props ocultáveis) | **Sim** (alcance ≥ 500 m) | **Sim** (completos) | Igual ao Médio |
| **Prédios (boxes, paddock, arquibancadas, torres)** | **Não** (oculto para máximo FPS) | **Sim** (com culling de distância) | **Sim** (todos visíveis com alcance amplo) | Igual ao Médio |
| **Detalhes externos (banners patrocinadores, passarela, postes, cones, fiscais, câmeras)** | **Não** (ocultos) | **Sim** (culling ~450–550 m) | **Sim** (completos) | Igual ao Médio |
| **Árvores (`Arvores`) e Torcida (`Torcida`)** | **Não** (ocultos) | Árvores 1200 m / Torcida 180 m | Árvores 2400 m / Torcida 400 m | Igual ao Médio |
| **Horizonte distante (`Horizonte`)** | Sim (cilindro leve sem sombra) | Sim | Sim | Igual ao Médio |

---

## Fases de Execução

### Fase 0 — Captura Atual e Diagnóstico Lado a Lado
Objetivo: gerar os prints do jogo atual alinhados aos 25 frames já extraídos do LMU (`build/compare/lmu/`).

1. **Gerar baseline atual:**
   - Rodar `scripts/tests/capture_compare.gd` para `--quality=0` (`build/compare/godot_atual_min/`) e `--quality=2` (`build/compare/godot_atual_med/`).
   - Conferir câmera/FOV (`chase_camera.gd`) e iluminação base (`scripts/main.gd`: `tonemap_mode = AGX`, `tonemap_exposure = 1.05`, `sun.light_color`, `sun.light_energy`) para garantir que o comparativo não distorça cores nem proporções.
2. **Montar diagnóstico visual por setor:**
   - Comparar lado a lado os prints atuais com `build/compare/lmu_scan/sheet_01..03.png` nos trechos-chave (S do Senna, Curva do Sol, Reta Oposta, Descida do Lago, Ferradura, Laranjinha, Pinheirinho, Bico de Pato, Junção, Subida dos Boxes).
   - Listar exatamente onde a brita, o mato, as faixas verdes/vermelhas, as zebras e as placas de frenagem divergem da referência.

---

### Fase 1 — O Básico Impecável (Preset **Mínimo** + Base de Todos os Presets) — ✅ CONCLUÍDA (validação inicial)
Objetivo: resolver tudo o que hoje faz a pista parecer "mal feita" — cores, contrastes, britas, faixas, zebras, mato e placas de frenagem — garantindo que o modo **Mínimo** já tenha visual limpo, nítido e fiel ao LMU.

**Registro do que foi aplicado:**
- **`shaders/grama.gdshader`:** corrigido `base_color` (`vec3(0.44, 0.70, 0.26)`) e mistura `olive`/`straw` no `fast_mode` para eliminar o aspecto de areia/terra amarela e entregar verde-oliva vivo com manchas sutis de palha seca.
- **`shaders/asfalto.gdshader`:** calibrado o tom cinza-amarronzado (`vec3(1.16, 1.08, 0.93)`) e variação de ruído no `fast_mode`.
- **`gt3-time-attack/src/render/trackView.ts`:**
  - Cores vivas e limpas em `runoffTexture` (`verde` `#0c8a46`, `agua` `#16826b`, `vermelho` `#cc2226` com faixas brancas) e `kerbTexture` (amarelo/verde/branco), com `lift = 0.002`.
  - Adicionada textura/material próprio `gravelTexture` (pedrisco bege-terracota distinto do asfalto) nas áreas de escape externas das curvas principais (`GRAVEL_ZONES`, alinhadas por `S[i].curv > 0 ? -1 : 1`).
- **`gt3-time-attack/src/render/scenery.ts`, `tools/cenario/cenario.ts`, `scripts/track/track_view.gd`:**
  - Placas de frenagem marcadas com `ess_` para nunca serem ocultadas no Mínimo (`_minimal_hide_meshes`) e manterem alcance de `450 m`.
  - Corrigido `porscheRef` -> `r8Ref` em `scenery.ts` e erro de inferência `Variant` em `track_view.gd`; `assets/track/cenario.glb` regenerado (`25.6 MB`).
- **Proteção de Build / APK (`build/.gdignore` e `export_presets.cfg`):**
  - Criado `build/.gdignore` e atualizado `exclude_filter="data/tests/*, build/*, scripts/tests/*, tools/*"` nos presets para impedir que prints de comparação (`build/compare/`) inflem o APK.
- **Validação:** prints `build/compare/fase1_min_v2/` (`01_senna_entrada`, `03_curva_do_sol`, `08_ferradura`, `14_subida_boxes`) conferidos lado a lado com o LMU.

1. **Corrigir geração e classificação das malhas (`gt3-time-attack/src/render/*`, `tools/cenario/cenario.ts`, `scripts/track/track_view.gd`):**
   - **Separar tags/nomes de material ou nó** no export (`cenario.ts`) para que:
     - **Placas de frenagem (`brake_board`), guard-rails, pneus e muros** nunca entrem em `_minimal_hide_meshes` no `TrackView._fix()`.
     - **Prédios, arquibancadas, banners e decoração externa** continuem ocultos no `Mínimo`.
   - **Caixas de Brita reais (separadas do asfalto e do escape pintado):**
     - Adicionar/separar geometria e material próprios para **brita (`brita` / `gravel`)** nas áreas de escape de brita reais de Interlagos (lado de fora do S do Senna, Curva do Sol após o escape, Descida do Lago, Ferradura, Laranjinha, Pinheirinho, Bico de Pato, Mergulho, Junção), com textura granulada e cor **bege-alaranjada / terracota clara** bem distinta do asfalto e do verde/vermelho.
     - Eliminar qualquer faixa lateral cinza sem pintura que se confunda com a cor da pista.
2. **Calibrar cores base de Pista, Escapes, Zebras e Mato:**
   - **Asfalto (`shaders/asfalto.gdshader`):** ajustar multiplicador de cor e contraste (`fast_mode` e completo) para o cinza-amarronzado médio do LMU, mantendo visível a faixa de borracha do traçado e a linha branca de borda (35 cm).
   - **Faixas Verdes, Verde-Água e Vermelha (`runoffTexture` em `trackView.ts`):** aumentar vivacidade e fidelidade de cor ao LMU (verde esmeralda vivo nas áreas verdes, vermelho vivo com faixas brancas nítidas na saída da Curva do Sol), reduzindo o desgaste excessivo (`weather`) que deixa a tinta suja/apagada.
   - **Zebras (`kerbTexture` em `trackView.ts`):** calibrar amarelo, verde e branco para ficarem vibrantes e bem recortados (reduzir `weather`), com contraste claro em relação ao asfalto e à grama.
   - **Grama / Mato (`shaders/grama.gdshader`):** ajustar `base_color` e mistura `olive` / `straw` (tanto no `fast_mode` quanto no completo) para o verde-oliva vivo com manchas de palha seca vistas no LMU, evitando o aspecto cinzento/lamacento.
   - **Muros e Barreiras (`TrackView._material`):** ajustar albedo e contraste dos muros de concreto e barreiras azuis/laranjas para boa leitura mesmo sem normal map no `Mínimo`.
3. **Caprichar nas Placas de Frenagem e Referências de Pilotagem (`scenery.ts`):**
   - Conferir posições, lado (externo/visível na abordagem) e cores das placas (`200`, `150`, `100`, `50` m) nas freadas principais comparando com `sheet_01..03.png`.
   - Garantir fonte legível, borda bem definida, poste com base no chão e `visibility_range_end` amplo (≥ 400 m) no `Mínimo`.
4. **Reexportar e Validar Fase 1:**
   - Rodar `node cenario.mjs` em `tools/` para regenerar `assets/track/cenario.glb`.
   - Rodar `capture_compare.gd` no **Mínimo** e comparar com `lmu_01..25.png`.

---

### Fase 2 — Preset **Leve** (Contexto Externo + Desempenho Mobile) — ✅ CONCLUÍDA
Objetivo: adicionar profundidade ao redor da pista (prédios, arquibancadas, banners de patrocinadores, postes, pórticos, passarela, torres) mantendo 60 FPS no celular.

**Registro do que foi aplicado:**
- **`shaders/fachada.gdshader`:** corrigido uso de `UV2.x` (`aWin`) para distinguir parede lisa (`0`), casa (`1`), prédio (`2`) e teto (`-1`), e reduzido o ganho do reboco (`0.45 + 0.40 * pl.g` / `0.50 + 0.35 * pl.r`) para eliminar o aspecto estourado dos prédios do OSM.
- **`shaders/torre.gdshader`:** calibrado `v_col * 0.70`, telhados e lajes de varanda (`0.70, 0.69, 0.67`) para integrar o anel de 1.400 torres ao horizonte sem estourar em branco.
- **`scripts/track/track_view.gd`:** calibrado `ph:concrete_wall*` (`0.56, 0.55, 0.53`) e paredes lisas claras sem textura (`order == 0`, `nm != "pinta"`, luminância `> 0.55` multiplicada por `0.65`) para evitar estouro de branco no fundo dos boxes/paddock sob `sun.light_energy = 2.8`.
- **`scripts/track/surroundings_view.gd`:** ajustado alcance da torcida no `Leve` (`DETAIL[1].crowd`) de `180.0` para `260.0` para evitar corte brusco na reta principal.
- **`scripts/tests/capture_compare.gd`:** adicionado `--bench` para medição de frame time por checkpoint (`08_ferradura` ~28.5 ms, `15_arquibancadas` ~29.0 ms em Intel Iris Xe no preset Leve).
- **Validação:** prints `build/compare/fase2_leve_v2/` e `build/compare/fase2_leve_v4/` conferidos (`01_senna_entrada`, `03_curva_do_sol`, `08_ferradura`, `14_subida_boxes`, `15_arquibancadas`).

1. **Habilitar estruturas externas com culling calibrado (`TrackView` e `SurroundingsView`):**
   - Exibir boxes, paddock, arquibancadas, `Torres` e detalhes externos (banners Rolex/Motul/Goodyear/DHL/TotalEnergies/Avis, passarela, postes, câmeras, fiscais, cones) com `visibility_range_end` ajustado.
2. **Calibrar fachadas e banners:**
   - Ajustar `shaders/fachada.gdshader`, `shaders/torre.gdshader` e cores dos banners/muros para baterem com o contraste e a paleta do LMU.
3. **Validação da Fase 2 (Visual + FPS):**
   - Rodar `capture_compare.gd` no **Leve** e comparar com o LMU e com o Mínimo.
   - Medir frame time nos trechos mais densos (Reta Principal / Boxes).

---

### Fase 3 — Preset **Médio** (Completo) e **Extremo** (Cópia do Médio) — ✅ CONCLUÍDA
Objetivo: entregar o nível completo de detalhes no Médio e espelhar no Extremo.

**Registro do que foi aplicado:**
- **`scripts/track/track_view.gd`:** `fast_mode = false` nos shaders (`asfalto`, `grama`, `impostor`), normal maps e filtragem anisotrópica ativos para `level >= 2`, e mesma lógica de visibilidade/culling para `Médio` (`2`) e `Extremo` (`3`).
- **`scripts/track/surroundings_view.gd`:** alinhado `DETAIL[3]` (`Extremo`) exatamente com `DETAIL[2]` (`Médio`: `crowd: 400.0`, `trees: 2400.0`, `towers: 0.0`).
- **Validação:** prints `build/compare/fase3_medio/` (`01_senna_entrada`, `03_curva_do_sol`, `08_ferradura`, `14_subida_boxes`, `15_arquibancadas`) e paridade em `build/compare/fase3_extremo/` conferidos.

1. **Habilitar todos os detalhes no Médio:**
   - `fast_mode = false` em `asfalto.gdshader`, `grama.gdshader` e `impostor.gdshader`.
   - Normal maps e ORM/roughness ativos nos materiais de pista (`pinta`, `ph:*`, `brita`, muros, zebras).
   - `Arvores`, `Torcida`, `Torres` e todos os props secundários ativos com alcance amplo.
2. **Espelhar Médio → Extremo (detalhes da pista):**
   - Garantir que `TrackView.set_detail(3)` e `SurroundingsView.DETAIL[3]` usem exatamente os mesmos detalhes de pista do nível `2` (Médio).
3. **Validação Final:**
   - Rodar `capture_compare.gd` no **Médio** (e checar paridade no **Extremo**) comparando lado a lado com `build/compare/lmu/`.
