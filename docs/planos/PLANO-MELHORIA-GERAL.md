# Plano de Melhoria Geral — `gt3-godot`

Este documento consolida a próxima etapa de evolução do `gt3-godot` após a conclusão das Fases 1–4 (`PLANO-MELHORIAS-E-FERRAMENTAS.md`), aproveitando **Godot MCP**, **Blender MCP** e o **pipeline de áudio (`FFmpeg` + `audio_prep.py`)**, com foco em corrigir pontos onde a IA costuma errar e entregar ganhos reais de pilotagem, som, visual e performance (PC, Android e Web).

---

## 0. Correção Imediata Aplicada (Sirene Aguda nas Freadas)

- **Causa raiz identificada:** em `tools/gen_fx_sources.py`, `brake_squeal.wav` (2680 Hz + 3390 Hz) e `gearbox_whine.wav` (920/1840/2760 Hz) foram gerados sinteticamente com senoides puras e um bug clássico de modulação FM (`sin(2*pi*(f + vib) * t)` em vez de integrar a fase), fazendo o desvio de frequência crescer com o tempo — produzindo literalmente uma **sirene aguda** ao frear (`brake_out > 0.5` entre 60 e 220 km/h).
- **Ação tomada:** `brake_squeal` e `gearbox_whine` foram desativados em `scripts/audio/car_audio.gd`, removidos de `data/sounds.json` e deletados de `assets/sounds/fx/` (os pipocos `backfire_1..3.wav` são graves/curtos e foram mantidos).
- **Regra permanente de áudio:** **nunca** sintetizar loops tonais contínuos agudos com senoides (`turbo`, freio, câmbio). Esse tipo de camada só entra no jogo com **gravação real CC0** validada no ouvido.

---

## 1. Pilar de Áudio Realista & Mixagem

**Objetivo:** elevar a imersão sonora sem nunca mais introduzir ruídos artificiais/incômodos.

- [x] **1. Mixer de Volumes no Menu e Pausa (`lmu_menu.gd`, `pause_menu.gd`, `game.gd`):**
  - Sliders persistidos em `user://jogo.cfg` para **Master**, **Motor**, **Pneus/Superfície** e **Efeitos/UI**.
- [x] **2. Redução de Marchas Mais Grossa / Encorpada (`car_audio.gd`, `gear_shift1`, `backfire_1..3`):**
  - Corrigido o timbre agudo na redução de marchas: diferenciação upshift vs. downshift (`gear_shift1`), `backfire_1..3` reprocessados com passa-baixa em `1350 Hz` e sub-thump grave, e corpo médio-grave no blip de RPM na bus `Engine`.
- [x] **3. Troca de FX sintéticos por gravações reais CC0 (`tools/audio_prep.py`):**
  - Substituídos `backfire_1..3` (Freesound CC0 #105351 e #675723) e `bottom_scrape` (Freesound CC0 #877948) por gravações reais CC0 processadas via `audio_prep.py` (`dominant_hz` entre `193.8 Hz` e `602.9 Hz`, sem picos agudos).
- [x] **4. Camada de Trava de Roda vs. Escorregamento Lateral (`car_audio.gd`):**
  - Diferenciação entre o som de freada no limite do ABS / trava longitudinal (mais grave com pulsação sutil do ABS) e o canto lateral em curva.
- [x] **5. Ambiência Sutil de Pista (Opcional nos presets Médio/Extremo):**
  - Reverb curto e leve (`AudioEffectReverb` na bus `Engine`, ativo apenas em `quality_level >= 2`) modulado pela proximidade dos muros (`wall_l`/`wall_r`) e velocidade.

---

## 2. Pilar Visual — Carros & Pistas (Blender MCP + Shaders)

**Objetivo:** aproximar o acabamento visual do **Le Mans Ultimate (LMU)** mantendo 60 FPS no celular (`Mínimo`/`Leve`).

- [x] **1. Auditoria de Peso e Texturas pós-Blender (`assets/cars/`):**
  - Removidas 439 texturas órfãs + 439 `.import` (~22,12 MB economizados) e `tools/debug.log`; validado via `audit_cars.gd` nos 13 carros.
- [x] **2. Efeitos Visuais de Pilotagem (~0 ms no mobile):**
  - **Disco de freio incandescente** em freadas fortes (`car_view.gd`, proporcional à energia de frenagem).
  - **Faíscas de fundo raspando** (`bottom_scrape`) e **fumaça leve de trava de roda** (`CPUParticles3D`, desligados no preset `Mínimo`).
- [x] **3. Hero Props Modulares via Blender MCP (`assets/props/*.glb`):**
  - Modelados em Blender (`tools/gen_hero_props.py` → `assets/props/*.glb`, 316 KB total): `marshal_post.glb`, `crane.glb`, `ambulance.glb`, `gantry_tower.glb` e `corkscrew_bridge.glb`, exportados via `propsRegistry.ts` → `props.json` e instanciados em `TrackView.build_props()` com culling por preset.
- [x] **4. Asfalto Vivo (`shaders/asfalto.gdshader` + `tools/cenario/`):**
  - Faixa emborrachada sutil na linha ideal e marcas de frenagem nas zonas de freada forte derivadas da telemetria real do Garage 61 (`liveAsphalt.ts` → `UV2` na malha do asfalto + `shaders/asfalto.gdshader` com brilho sutil de borracha no `Médio`/`Extremo`).

---

## 3. Pilar de Pilotagem, HUD & Telemetria (Game Feel)

**Objetivo:** fazer o jogador sentir melhor o carro e ter motivação clara para melhorar tempos de volta.

- [x] **1. Barra de Delta em Tempo Real + Inputs no HUD (`scripts/ui/hud.gd`, `lap_timer.gd`):**
  - Delta ao vivo (`-0.24s` verde / `+0.18s` vermelho) agora ativo desde a **Volta 1** contra o PB salvo (ghost) ou volta de referência do Garage 61.
  - Barras de acelerador, freio e indicadores visuais de **ABS** e **TC** atuando.
- [x] **2. Carro Fantasma (Ghost Car) (`scripts/track/ghost_car.gd`):**
  - Gravação leve da melhor volta pessoal (`pos + rot` a ~12 Hz em `user://ghosts/`) renderizada com material translúcido barato, toggle no menu e atalho **`H`**.
- [x] **3. Ajustes Rápidos de Carro (Setup Simplificado):**
  - Balanço de freio (`Brake Bias`), `TC` e `ABS` ajustáveis no menu/pausa e em pista (`[` / `]` para Brake Bias, `1`/`2` para ABS/TC), persistidos em `user://jogo.cfg` e afetando diretamente `scripts/physics/car.gd`.
- [x] **4. Câmeras Mais Vivas (`scripts/render/chase_camera.gd`):**
  - Micro-vibração de zebra, antecipação de rampa/força G e FOV dinâmico suave já ativos.

---

## 4. Pilar de Conteúdo & Rejogabilidade

- [ ] **1. Corrida Rápida contra IA (Grid de 4–8 carros):**
  - Aproveitar `RefBot` / `Bot` já existentes para montar uma sessão de corrida curta (3–5 voltas) com largada lançada, detecção simples de ultrapassagem/colisão e classificação no HUD.
- [ ] **2. Terceira Pista GT3 Clássica (`GUIA-PISTAS.md`):**
  - Adicionar uma nova pista de alto apelo (ex.: **Monza**, **Spa-Francorchamps** ou **Brands Hatch**) usando o pipeline LiDAR + OSM + Garage 61 já consolidado em Laguna Seca.

---

## 5. Pilar de Engenharia, Performance & Workflow com MCPs

- [ ] **1. Uso Disciplinado dos MCPs (contínuo):**
  - **Godot MCP:** inspeção de árvore de nós em tempo real, validação de UI (`LmuMenu`, `Hud`) e leitura de erros/warnings do debugger.
  - **Blender MCP:** apenas em carros (`assets/cars/`) e props modulares (`assets/props/`), nunca diretamente em `cenario.glb` gerado por script.
- [x] **2. Portão de Regressão Obrigatório:**
  - Rodados e aprovados: `audio.gd`, `paridade.gd`, `laguna_seca.gd`, `horario_e_farois.gd`, `lmu_menu_test.gd`, `cronometragem.gd` e `melhorias_etapa1_2.gd`.
- [x] **3. Controle de Tamanho (APK / Web PCK):**
  - Auditoria executada (`assets/` = `240,21 MB` após remover `22,12 MB` de texturas órfãs).

---

## Ordem Sugerida de Execução

| Etapa | Foco | Impacto | Risco | Status |
| :---: | :--- | :---: | :---: | :---: |
| **1** | Limpeza pós-Fases 1–4 (auditoria de texturas dos carros + commit organizado) + Mixer de volumes no Menu | Alto | Baixo | 🔄 Feito (falta commit) |
| **2** | HUD de Pilotagem (Delta ao vivo, indicadores de ABS/TC) + Ghost Car da melhor volta | Muito Alto | Baixo | ✅ Concluído |
| **3** | Visual de pista/carros (disco de freio quente, marcas de freada, hero props no Blender MCP) | Alto | Médio | ✅ Concluído |
| **4** | Áudio CC0 real (redução de marchas mais grossa/encorpada + substituir FX sintéticos restantes + ambiência de muro) | Alto | Baixo | ✅ Concluído |
| **5** | Setup rápido (Brake Bias / TC / ABS) + Corrida Rápida contra IA ou 3ª Pista | Muito Alto | Médio | 🔄 Parcial (Brake Bias ok; falta Corrida IA / 3ª pista) |
