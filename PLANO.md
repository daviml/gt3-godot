# Plano de Migração: GT3 Time Attack (Web) -> GT3 Godot

Este documento registra o plano fechado para concluir a migração do jogo Web (`gt3-time-attack`) para o projeto Godot 4.7 (`gt3-godot`), preservando as melhorias já implementadas no Godot.

## Regras e Decisões Fechadas

1. **Telas de Loading e Updater intocáveis (com exceção pontual no fallback de carro):**
   - As telas em `scenes/loading.tscn`, `scripts/ui/loading_screen.gd`, `scenes/updater.tscn` e `scenes/updater.gd` já estão melhores no `gt3-godot` e **não serão modificadas** na UI/fluxo — **única exceção autorizada:** trocar o fallback `_initial_car_id = "porsche-992-gt3r"` em `scripts/ui/updater.gd` (linhas 263 e 943) pelo novo carro padrão (`"corvette-c6r-gt3"`).
   - Todo o ciclo chamado por `loading_screen.gd` sobre `scenes/garagem.tscn` (`manual_setup = true`, `setup_step_studio()`, `setup_step_ui()`, `setup_step_car()`, `finish_loading()`) será preservado.
2. **Ordem de entrega separada:**
   - **Entrega 1 (Fases 1–3):** Menu estilo LMU para Desktop e Mobile, Garagem 3D no layout LMU, Configurações em 5 abas com busca, Recordes + DR/SR, Ajuda, ocultação Touch / auto-hide por Gamepad e substituição do menu de pausa na pista pelo `LmuMenu` unificado.
   - **Entrega 2 (Fase 4 — posterior):** Multiplayer Online (salas, fantasmas, lobby UI, largada com 5 luzes, classificação ao vivo e colisão entre carros).
3. **Garagem 3D + Layout LMU:**
   - Manter o estúdio 3D interativo já pronto em `scripts/ui/garagem.gd` (turntable, iluminação e prefetch assíncrono dos GLBs) dentro do layout LMU da aba de carros, em vez de usar imagens estáticas `.webp`.
4. **Menu de Pausa na Pista Unificado:**
   - Substituir o modal simples atual de `scripts/ui/pause_menu.gd` pelo mesmo componente `LmuMenu` unificado, garantindo interface Desktop/Mobile e acesso idêntico a Recordes, Configurações e Ajuda dentro e fora da pista.

---

## Inventário: Pronto vs. Faltante

### Já migrado e OK no `gt3-godot`
- Carros GLB em `assets/cars/` (passando de 13 para 16 carros leves no plano abaixo), física Simulador/Arcade (`MODE_GRIP`) e HUD de pista (`scripts/ui/hud.gd`).
- Estúdio 3D e prefetch assíncrono em `scripts/ui/garagem.gd` (com flags CLI `--car=`, `--shot=`, `--auto`, `--vitrine=`).
- Persistência e sincronização de recordes em `scripts/ui/records.gd` (`Records`).
- Controles Touch em 4 modos (`scripts/input/touch_controls.gd`).
- Telas de atualização e carregamento (`updater.gd`, `loading_screen.gd`).

### O que falta migrar
1. **Menu LMU Unificado (`LmuMenu`) + Design Responsivo Desktop vs. Mobile:**
   - **Desktop (`vp.x >= 960` e `vp.y > 560`):** barra superior de `56px` com bloco central (circuito, navegação e busca), Home 2 colunas (`380px` destaque + grade 2x2 + cartão DR/SR), Garagem com painel direito (`330px`) de Ficha Técnica (5 linhas) + Personal Best + grade 7 colunas (`52px`) com filtros de tração/motor.
   - **Mobile Landscape (`vp.y <= 560` ou mobile compacto):** barra superior de `42px` sem bloco central, Home compacta (`52%`/`44%`) sem scroll vertical, painel lateral da Garagem reduzido (`235px`) ocultando *Downforce*, Personal Best horizontal, chips `36px` (7 colunas) e respeito à *safe area*.
   - **Mobile Portrait (fallback `vp.x < vp.y`):** layout empilhado para evitar quebras em retrato.
2. **Metadados completos em `data/cars.json`:**
   - Adicionar `brand`, `engine`, `power`, `weight` e `gears` aos 16 carros do elenco atualizado (hoje só existem `id`, `name`, `short`, `layout`, `color`) + distribuição de peso por layout (`dianteiro` 49%, `central` 43%, `traseiro` 39%).
3. **Configurações em 5 abas + Busca + Touch/Gamepad:**
   - Abas `Controles`, `Gráficos`, `Assistências`, `Áudio` e `Piloto` com filtro de busca em tempo real.
   - Preferência `hide_touch_controls` e ocultação automática quando um gamepad físico é conectado/ativo.
4. **Multiplayer Online (Entrega 2):**
   - `NetRoom`, `Ghosts`, `RaceManager`, `LobbyUi` e colisão carro-a-carro.

---

## Entrega 1 — Fases 1 a 3

### Fase 1: Dados, Tokens LMU e Componente `LmuMenu`
- **`data/cars.json`** `[MODIFY]`
  - Completar os 16 registros com `brand`, `engine`, `power`, `weight` e `gears` equivalentes ao `src/cars.ts` atualizado.
- **`scripts/ui/lmu_theme.gd`** `[NEW]`
  - Tokens de cor, tipografia, estilos de cards/botões LMU e função `compute_layout_profile(viewport_size, is_mobile)` retornando dimensões e margens de *safe area* para `desktop`, `tablet`, `mobile_landscape` e `portrait`.
- **`scripts/ui/lmu_menu.gd`** `[NEW]`
  - Componente único reutilizável nos contextos `GARAGE` e `PAUSE`, com as 5 vistas:
    - `home`: destaque da sessão/carro, atalhos 2x2, cartão Piloto com cálculo DR/SR; em `PAUSE` inclui `Continuar`, `Reiniciar Volta`, `Ir para Garagem 3D` e `Sair`.
    - `cars`: filtros (`Todos`, `Dianteiro`, `Central`, `Traseiro`), seletor `Simulador` / `Arcade`, Ficha Técnica, Melhor Pessoal e grid 7x2 de chips (deixando o centro transparente para o estúdio 3D na Garagem).
    - `settings`: barra de busca + abas `Controles`, `Gráficos`, `Assistências`, `Áudio`, `Piloto`.
    - `records`: Top 15 por modo (`Simulador` / `Arcade`) via `Records.top()` + comparação pessoal e setores.
    - `help`: 3 cards informativos (Controles, Modos de Física, Pista/Regras).

### Fase 2: Integração na Garagem 3D
- **`scripts/ui/garagem.gd`** `[MODIFY]`
  - Preservar integralmente o estúdio 3D, prefetch assíncrono, flags CLI e os métodos `setup_step_studio()`, `setup_step_ui()`, `setup_step_car()` e `finish_loading()`.
  - Instanciar `LmuMenu` em `setup_step_ui()` no contexto `GARAGE`: transparente no centro durante a seleção de carro para exibir o estúdio 3D interativo ao vivo, e com backdrop suave nas demais abas (`home`, `settings`, `records`, `help`).

### Fase 3: Menu de Pausa Unificado & Touch/Gamepad
- **`scripts/ui/pause_menu.gd`** `[MODIFY]` e **`scripts/main.gd`** `[MODIFY]`
  - Substituir o modal simples atual de `pause_menu.gd` pelo `LmuMenu` em contexto `PAUSE`, mantendo todos os sinais já conectados em `main.gd` (`resumed`, `garage`, `quit`, `nick_changed`, `mode_changed`, `quality_changed`, `volume_changed`, `assist_changed`, `touch_mode_changed`, `hud_gauge_changed`, `recenter_tilt`) e adicionando `restart_requested`, `car_selected` e `hide_touch_changed`.
- **`scripts/game.gd`**, **`scripts/input/touch_controls.gd`**, **`scripts/input/input_reader.gd`** `[MODIFY]`
  - Persistir `hide_touch_controls` em `user://jogo.cfg`.
  - Ocultar automaticamente os controles Touch ao detectar gamepad físico conectado (`Input.get_connected_joypads()` / `joy_connection_changed`) ou quando `hide_touch_controls` estiver ativo.

---

## Entrega 2 — Fase 4 (Etapa Posterior: Multiplayer Online)

- **Fase 4.1 (`scripts/net/net_room.gd`):** Cliente WebSocket conectado a relay leve substituindo o mesh WebRTC/Nostr do Web, com mensagens `oi`, `pose` (20 Hz), `volta`, `lobby` e `corrida`.
- **Fase 4.2 (`scripts/net/ghosts.gd`):** Interpolação (~120 ms), carros fantasma translúcidos vs. sólidos em corrida, rótulo flutuante de apelido e marcadores no minimapa do `hud.gd`.
- **Fase 4.3 (`scripts/net/race_manager.gd`, `scripts/ui/lobby_ui.gd`, colisão no `car.gd`):** Salas, semáforo de 5 luzes vermelhas, grid de largada, tabela ao vivo de gaps/posições, pódio e colisão elástica com atrito entre carros.

---

## Checklist de Verificação (Entrega 1)

- [ ] `git diff` vazio em `scenes/loading.tscn`, `scripts/ui/loading_screen.gd` e `scenes/updater.tscn` (e em `scripts/ui/updater.gd`, apenas a troca do fallback `_initial_car_id` para `"corvette-c6r-gt3"`).
- [ ] `scripts/tests/garagem_fase3.gd` passando sem regressões nos ganchos do loading.
- [ ] Novo teste headless validando `data/cars.json` (16 carros com ficha completa) e responsividade/vistas do `LmuMenu` em `1920x1080`, `844x390` e `390x844`.
- [ ] Validação visual na Garagem 3D (Desktop e Mobile Landscape) sem scroll indesejado na Home e na aba de Carros.
- [ ] Validação dentro da pista confirmando paridade total entre o menu de pausa (`ESC` / touch) e o menu da Garagem.

---

## Plano de Atualização do Elenco de Carros (13 → 16 Carros Leves / Redução de APK)

Objetivo: enxugar o APK Android (de **370,4 MB** para **~215–240 MB** estimados) removendo os 6 modelos mais pesados e adicionando 9 carros GT3 leves/selecionados, mantendo `gt3-time-attack` como fonte única de dados sincronizada via `tools/prep.ts`.

### Decisões Fechadas

1. **Saem (6 carros pesados — liberam ~232,27 MB do APK):**
   - `aston-vantage-gt3` (59,82 MB)
   - `ford-mustang-gt3` (48,77 MB)
   - `corvette-c8r-gt3` (42,79 MB)
   - `mercedes-amg-gt3` (32,31 MB)
   - `ferrari-296-gt3` (27,79 MB)
   - `porsche-992-gt3r` (20,79 MB)
2. **Permanecem (7 carros atuais leves — 60,61 MB no APK):**
   - `bmw-m4-gt3` (10,35 MB), `bmw-m6-gt3` (6,71 MB), `ferrari-488-gt3` (7,42 MB), `audi-r8-lms-gt3` (9,71 MB), `lamborghini-huracan-gt3` (9,30 MB), `mclaren-720s-gt3` (8,49 MB), `nissan-gtr-gt3` (8,63 MB).
3. **Entram (6 carros novos no Sketchfab):**
   - **Chevrolet Corvette C6.R** (`corvette-c6r-gt3`) — UID `bf18bb0effd54728a32a06aa1da75a54` (Dave Love SketchFab, 257.114 faces, CC Attribution) — **novo carro padrão do jogo**
   - **Chevrolet Corvette C7 Gr.3** (`corvette-c7-gr3`) — UID `c0039978bbfc47f89cbff8dd4aca570d` (kevin (ケビン), 261.078 faces, CC Attribution)
   - **Acura NSX GT3 Evo** (`acura-nsx-gt3`) — UID `93a1dcff8da24d2ea6d5f912fbccc7e6` (amogusstrikesback2, 31.560 faces, CC Attribution)
   - **Bentley Continental GT3 (Gen 2 - 2020)** (`bentley-continental-gt3-2020`) — UID `ad6f9523a86a4c75a87b3c891cdb8d2b` (OUTPISTON, 46.166 faces, CC Attribution-NonCommercial-ShareAlike)
   - **Lamborghini Gallardo LP560 GT3** (`lamborghini-gallardo-gt3`) — UID `85d82c5f3da041378c8807a448d26022` (Ddiaz Design, 33.792 faces, CC Attribution-NonCommercial-ShareAlike)
   - **Aston Martin V12 Vantage GT3** (`aston-v12-vantage-gt3`) — UID `2673986fc0484af28291d85548f3c976` (OUTPISTON, 28.191 faces, CC Attribution-NonCommercial-ShareAlike)
   - *(Excluídos do plano: SLS AMG GT3, McLaren 650S GT3, Renault R.S. 01 e BMW Z4 GT3.)*
4. **Carro padrão do jogo:** `corvette-c6r-gt3` (`bf18bb0effd54728a32a06aa1da75a54`) substitui `porsche-992-gt3r` como carro inicial/fallback. (Para testes e piloto automático que exigem telemetria iRacing gravada, usar `audi-r8-lms-gt3` com `interlagos-r8`).
5. **Fallback em `updater.gd`:** autorizada a troca de `_initial_car_id = "porsche-992-gt3r"` para `"corvette-c6r-gt3"` nas linhas 263 e 943.
6. **Ranking online (`api/_lib/tempos.js`):** remover os 6 IDs que saem de `CARROS` e manter apenas os 16 IDs do novo elenco.
7. **Estimativa de peso do APK (16 carros):** ~77,6 MB (base) + ~60,6 MB (7 atuais) + ~59,5 MB (7 novos leves) + ~9 MB (C7 Gr.3) + ~20 MB (C6.R) = **~227 MB** (faixa **~210–240 MB**).

### Execução por Etapas

1. **Etapa 1 — Download, Escala e Build 3D (`gt3-time-attack`)**
   - `scripts/download-cars.mjs`: trocar lista `CARS` pelos 16 carros finais e rodar `node scripts/download-cars.mjs` (atualiza `models-src/` e `data/models/creditos.json`).
   - `scripts/build-cars.mjs`: atualizar `LENGTH` com o comprimento real (m) de cada um dos 9 novos carros, remover os 6 antigos e rodar `node scripts/build-cars.mjs` (gera `public/models/<id>.glb` com alvo de 120k tris e `data/models/<id>.json`).
   - `CREDITOS.md`: atualizar a tabela de créditos dos modelos Sketchfab.
2. **Etapa 2 — Cadastro, Física, Câmera, Ranking e Testes (`gt3-time-attack`)**
   - `src/cars.ts`: colocar `corvette-c6r-gt3` primeiro em `CARS`, remover os 6 antigos e cadastrar os 9 novos (`layout`, `color`, `sound` usando bancos de `data/sounds.json`, `brand`, `engine`, `power`, `weight`, `gears`).
   - `src/render/camera.ts`, `src/render/carView.ts`, `src/ui/hud.ts`, `src/main.ts`, `src/render/scenery.ts`: remover referências aos 6 carros antigos (limpar `MATTE` e `DASH_CARS`, ajustar offsets de câmera de capô dos 9 novos, atualizar `scenery.ts` / `main.ts` para usar `interlagos-r8` onde apontava `interlagos-porsche`).
   - `api/_lib/tempos.js`: substituir `CARROS` pelos 16 IDs finais (removendo os 6 que saem).
   - `tests/` e `scripts/`: atualizar `porsche-992-gt3r` / `ferrari-296-gt3` / `ford-mustang-gt3` para `corvette-c6r-gt3` ou `audi-r8-lms-gt3` em `tests/collision.test.ts`, `tests/raceManager.test.ts`, `tests/tempos.test.js`, `scripts/envelope.ts`, `scripts/tune-physics.ts`, `scripts/film-lap.mjs`.
3. **Etapa 3 — Limpeza e Sincronização (`gt3-godot`)**
   - Apagar arquivos órfãos dos 6 carros removidos em `gt3-time-attack` (`public/models/<id>.glb`, `data/models/<id>.json`, `data/cars/<id>.json`) e em `gt3-godot` (`assets/cars/<id>/`, `data/cars/<id>.json`, e referências `interlagos-porsche.json` / `interlagos-mustang.json` / `interlagos-amg.json` não mais usadas).
   - Rodar `npx vite-node prep.ts -- carros` em `gt3-godot/tools` para exportar os 16 GLBs (`car_fix.ts`), `data/cars.json`, `data/cars/*.json` e `assets/cars/creditos.json`.
   - Atualizar IDs hardcoded em `gt3-godot`:
     - `scripts/game.gd` (carro padrão `"corvette-c6r-gt3"` e fallback seguro caso `user://jogo.cfg` antigo aponte para um carro removido),
     - `scripts/main.gd` (`REFS` apenas `"audi-r8-lms-gt3": "interlagos-r8"` e fallback `"corvette-c6r-gt3"`),
     - `scripts/audio/car_audio.gd`, `scripts/render/car_view.gd`, `scripts/ui/hud.gd`, `scripts/ui/lmu_menu.gd`, `scripts/ui/updater.gd` (linhas 263 e 943),
     - `tools/paridade.ts` e `scripts/tests/*.gd` (`arcade_e_limites.gd`, `audio.gd`, `cambio_superficies.gd`, `camera.gd`, `controles.gd`, `cronometragem.gd`, `garagem_fase3.gd`, `hud.gd`, `loading_fase2.gd`, `paridade.gd`, `qualidade_blur.gd`).
4. **Etapa 4 — Verificação e Medição do APK**
   - Rodar `--vitrine` na Garagem 3D do Godot para validar visualmente orientação, normais, escala, rodas e pinças dos 9 novos carros.
   - Rodar suíte de testes headless no Godot (`scripts/tests/*.gd`) e `npm test` no `gt3-time-attack`.
   - Gerar novo APK via `Build-Android.bat` e confirmar tamanho final (~210–240 MB esperados) e distribuição por carro dentro do ZIP.
