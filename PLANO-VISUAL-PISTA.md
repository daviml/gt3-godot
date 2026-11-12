# Plano de Melhoria Visual da Pista (Interlagos) — Comparativo LMU

Este plano define as etapas para aproximar o visual da pista de Interlagos no `gt3-godot` ao do **Le Mans Ultimate (LMU)**, usando como referência um vídeo real de um Porsche em Interlagos no LMU.

**Escopo desta etapa:**
- Foco em **detalhes visuais e fidelidade da pista e arredores** (cores do asfalto, zebras, muros, paredes, faixas, áreas de escape, gramado/mato, prédios e objetos externos).
- **Não** mexer em sombras, iluminação global, SSR/SSIL ou pós-processamento pesado agora.
- Garantir que os modos **Mínimo**, **Leve** e **Médio** rodem bem no **celular**, com orçamento claro do que aparece ou não em cada nível.
- **Extremo** será uma **cópia do Médio** quanto aos detalhes da pista por enquanto (melhorias gráficas pesadas de GPU/PC ficam para o futuro).

---

## Matriz de Detalhes por Preset Gráfico

Referência atual no código: `Game.QUALITY_LEVELS` (`scripts/game.gd`), `Main._set_quality()` (`scripts/main.gd`), `TrackView.set_detail()` (`scripts/track/track_view.gd`) e `SurroundingsView.DETAIL` (`scripts/track/surroundings_view.gd`).

| Elemento da Pista / Ambiente | 0 — Mínimo (Celular) | 1 — Leve (Celular) | 2 — Médio (Celular / PC) | 3 — Extremo (PC — cópia do Médio) |
| :--- | :--- | :--- | :--- | :--- |
| **Asfalto, faixas e grid** | Sim (shader `fast_mode`, cor/contraste calibrados ao LMU) | Sim (shader `fast_mode` ou intermediário calibrado) | Sim (shader completo: 2 escalas, manchas 18m/45m, normal/ARM) | Igual ao Médio |
| **Zebras e pintura de pista** | Sim (cores fiéis, alto contraste, sem normal map) | Sim (cores fiéis, sem normal map pesado) | Sim (com normal map e rugosidade do asfalto) | Igual ao Médio |
| **Muros, barreiras, guard-rails e paredes** | Sim (cores e texturas base fiéis ao LMU) | Sim | Sim (com normal maps completos) | Igual ao Médio |
| **Grama / mato e áreas de escape** | Sim (shader `fast_mode` com paleta de verde/palha/terra fiel ao LMU) | Sim | Sim (shader completo com variação de palha, terra e normal map) | Igual ao Médio |
| **Prédios (boxes, paddock, arquibancadas, torres)** | **Não** (oculto para máximo FPS) | **Sim** (boxes, arquibancadas e torres com culling de distância) | **Sim** (todos visíveis com alcance amplo) | Igual ao Médio |
| **Detalhes externos da pista (pórticos, placas, passarela, postes)** | Apenas essenciais de referência (ex.: placas de frenagem principais, se necessário) | **Sim** (culling médio ~450–550 m) | **Sim** (completos: cones, fiscais, câmeras de TV, placas, postes) | Igual ao Médio |
| **Árvores (`Arvores` impostores)** | **Não** (oculto; hoje ainda desenha até 300 m — corrigir para oculto) | **Não** ou apenas muito próximas (a definir na comparação) | **Sim** (todas as células, alcance amplo) | Igual ao Médio |
| **Torcida (`Torcida`)** | **Não** | **Não** (ou alcance curto se não pesar) | **Sim** | Igual ao Médio |
| **Horizonte distante (`Horizonte`)** | Sim (cilindro leve sem sombra) | Sim | Sim | Igual ao Médio |

> **Nota sobre o código atual:** Em `scripts/track/surroundings_view.gd`, o preset `0` (`Mínimo`) atualmente configura `"trees": 300.0`. Como parte deste plano, no `Mínimo` as árvores serão totalmente ocultadas (`visible = false`), mantendo apenas pista, zebras, muros, paredes e mato muito bem resolvidos visualmente.

---

## Fases de Execução

### Fase 0 — Captura dos ~90 Prints (LMU vs. Jogo Atual) e Diagnóstico
Objetivo: ter base visual objetiva segundo a segundo de uma volta completa (~90s) em Interlagos.

1. **Extração dos frames do vídeo do LMU:**
   - Vídeo de referência: `INTERLAGOS-IN-LE-MANS-ULTIMATE-LMGT3-Track.mp4` (na raiz do projeto, já ignorado pelo `.gitignore`).
   - Usar `ffmpeg` para extrair **1 frame por segundo** (`-vf fps=1`) do vídeo da Porsche em Interlagos no LMU, gerando ~90 imagens numeradas (`lmu_001.png` ... `lmu_090.png`) em `build/compare/lmu/` (também ignorada pelo `.gitignore` via `build/`).
2. **Captura automática da volta com Bot no `gt3-godot`:**
   - Criar uma cena/script de captura automatizada (usando `RefBot` com `data/reference/interlagos-r8.json` ou `Bot` em `scripts/track/bot.gd`) para dar 1 volta limpa em Interlagos com a câmera padrão de jogo (`chase_camera.gd`), capturando **1 print a cada 1,0 segundo** de simulação (`get_viewport().get_texture().get_image().save_png(...)`) em `build/compare/godot_atual/`.
   - Garantir que o tempo de volta bata ~90 segundos para alinhar os trechos com o vídeo do LMU.
3. **Comparação lado a lado por setor/segundo:**
   - Mapear os principais pontos da volta (Reta Principal, S do Senna, Curva do Sol, Reta Oposta, Descida do Lago, Ferradura, Laranjinha, Pinheirinho, Bico de Pato, Mergulho, Junção, Subida dos Boxes).
   - Documentar em tabela as diferenças encontradas em:
     - Tom/cor do asfalto, manchas e emborrachamento.
     - Cores, largura e padrão das zebras.
     - Cores e acabamento dos muros, guard-rails, pneus e paredes.
     - Cores do mato/grama, terra e áreas de escape.
     - Presença/cor/escala de prédios, arquibancadas, pórticos, placas e árvores.

---

### Fase 1 — Implementação do Preset **Mínimo** (Básico bem detalhado)
Objetivo: deixar o modo mais leve com visual limpo, fiel nas cores e bem detalhado apenas com os elementos essenciais da pista.

1. **Ocultar elementos pesados no Mínimo (`scripts/track/track_view.gd` e `scripts/track/surroundings_view.gd`):**
   - Ocultar `Arvores` (`visible = false`), `Torres` (`visible = false`), `Torcida` (`visible = false`) e malhas classificadas como prédios/decoração externa no nível `0`.
2. **Calibração de cores e shaders `fast_mode`:**
   - `shaders/asfalto.gdshader` (`fast_mode = true`): ajustar multiplicadores de cor/contraste e variação sutil de tonalidade sem adicionar leituras pesadas de textura, aproximando do cinza-amarronzado/asfalto do LMU visto nos prints.
   - `shaders/grama.gdshader` (`fast_mode = true`): ajustar `base_color` e mistura verde/palha barata para reproduzir fielmente o tom do mato de Interlagos no LMU.
   - Materiais de **zebras**, **muros**, **paredes** e **faixas** (`tools/cenario/cenario.ts` -> `assets/track/cenario.glb` e `TrackView._material`): corrigir cores base (albedo), saturação e contraste para ficarem fiéis mesmo sem normal map nem sombras.
3. **Validação da Fase 1:**
   - Rodar novamente o Bot tirando ~90 prints no modo **Mínimo** e comparar com o LMU.

---

### Fase 2 — Implementação do Preset **Leve** (Prédios e detalhes de fora)
Objetivo: manter o desempenho no celular (60 FPS) adicionando profundidade e contexto externo ao redor da pista.

1. **Habilitar estruturas externas e prédios (`SurroundingsView` / `TrackView`):**
   - Exibir prédios do entorno, boxes, paddock, arquibancadas (sem torcida densa se necessário) e `Torres` com `visibility_range_end` calibrado.
   - Habilitar detalhes de pista próximos (pórticos, passarela, placas de frenagem, barreiras e postes) com culling de distância adequado.
2. **Ajuste visual dos prédios e fachadas (`shaders/fachada.gdshader`, `shaders/torre.gdshader`):**
   - Comparar cores, contraste e escala de prédios/arquibancadas com os prints do LMU e ajustar materiais/texturas base.
3. **Validação da Fase 2:**
   - Rodar o Bot tirando ~90 prints no modo **Leve** e comparar com o LMU e com o Mínimo.

---

### Fase 3 — Implementação do Preset **Médio** (Tudo habilitado) e **Extremo** (Cópia do Médio)
Objetivo: entregar o nível completo de detalhes da pista e entorno no Médio, e espelhar no Extremo.

1. **Habilitar todos os detalhes no Médio:**
   - `fast_mode = false` em `asfalto.gdshader`, `grama.gdshader` e `impostor.gdshader`.
   - Normal maps e ORM/roughness ativos nos materiais de pista (`pinta`, `ph:*`, muros, zebras).
   - `Arvores`, `Torcida`, `Torres` e todos os props secundários (cones, postos de fiscal, câmeras de TV, placas, marcas de pneu/borracha completas) ativos com alcance amplo.
2. **Espelhar Médio → Extremo (detalhes da pista):**
   - Garantir que `TrackView.set_detail(3)` e `SurroundingsView.DETAIL[3]` usem exatamente os mesmos detalhes de pista do nível `2` (Médio), sem adicionar novos custos de sombra/pós-processamento nesta etapa.
3. **Validação Final:**
   - Rodar o Bot tirando ~90 prints no modo **Médio** (e checar paridade no **Extremo**) comparando lado a lado com os ~90 prints do vídeo do LMU.

---

## Ordem de Execução Recomendada

1. **Fase 0:** Extrair os ~90 prints do vídeo do LMU + gerar os ~90 prints do Bot no jogo atual + montar comparativo.
2. **Fase 1:** Implementar e validar o **Mínimo** (cores da pista, zebras, muros, paredes, mato; sem árvores/prédios).
3. **Fase 2:** Implementar e validar o **Leve** (adiciona prédios, boxes, arquibancadas e detalhes externos com culling).
4. **Fase 3:** Implementar e validar o **Médio** (tudo ativo) e replicar a configuração de pista no **Extremo**.
