# Plano: Horário nas Pistas, Iluminação Leve e Faróis dos Carros

Objetivo: implementar seleção de **horário nas pistas** (**automático** pelo relógio do usuário como padrão + escolha manual nas configurações), **iluminação noturna sem perda de FPS** (focada em textura/shader, sem excesso de luzes dinâmicas ou reflexos) e **faróis dos carros**.

---

## 1. Diagnóstico Atual (Pistas e Carros)

### Pistas (`Interlagos` e `Laguna Seca`)
- **GLBs (`assets/track/cenario.glb` e `assets/tracks/laguna-seca/cenario.glb`):** não possuem extensão `KHR_lights_punctual` (apenas um material sem nome com `emissiveFactor` vermelho baixo `[0.0331, 0, 0]`).
- **OSM (`data/track/osm.json` e `data/tracks/laguna-seca/osm.json`):** não possuem postes nem torres de iluminação (`buildings, water, forest, grass, treeRows, pitLane, kart, corners, waterTower`, além de `walls, gravel, paved, roads` em Laguna Seca).
- **O que já existe e pode brilhar à noite sem custo de luz dinâmica:**
  - `shaders/torre.gdshader` (torres residenciais em Interlagos) e `shaders/fachada.gdshader` (prédios do OSM) já calculam proceduralmente a máscara de janelas (`glass`) e hash por célula.

### Carros (`13 modelos GT3`)
- Todos os 13 `.glb` em `assets/cars/` possuem materiais dedicados para luzes/faróis (ex.: `HEADLIGHT`/`BRAKELIGHT`, `light_HL`/`tail_light`, `lights_hl`/`lights_tl`, `BMWMAT_Lights1`, `LIGHTS`, etc.).
- Todos os `data/cars/<id>.json` contêm `model.length`, `model.width`, `model.height` e `model.wheels`, permitindo posicionar os faróis na dianteira de cada carro automaticamente.

---

## 2. Arquitetura Zero-Queda de FPS (Foco em Textura e Shader)

- **Manhã / Tarde / Pôr do sol:** custo **0 ms** extra — altera apenas parâmetros do `DirectionalLight3D` (`sun`) existente, `Environment` (`fog`, `ambient`) e uniforms em `sky.gdshader` / `horizonte.gdshader`.
- **Sem novos reflexos ou pós-processamento pesado:** não ativar `SSR`, `SSIL` ou `glow` nos presets `Mínimo` e `Leve` (mantém a regra atual de `scripts/main.gd`).
- **Sem `OmniLight3D` espalhados pela pista:** evita múltiplas avaliações por pixel em `asfalto`, `grama` e muros (crítico no mobile e em `gl_compatibility`). A atmosfera noturna vem de textura/shader e iluminação ambiente calibrada.

---

## 3. Etapas de Implementação

### Etapa 1 — Configuração e Cálculo de Horário (`scripts/game.gd`)
1. Persistir em `user://jogo.cfg` (`seção "video"`, `chave "horario"`):
   - `"auto"` (**padrão**): lê `Time.get_time_dict_from_system().hour` ao entrar na pista.
   - Presets fixos: `"manha"`, `"tarde"`, `"por_do_sol"`, `"noite"`.
2. Faixas do modo `"auto"`:
   - `06:00 – 11:59` → `manha`
   - `12:00 – 16:59` → `tarde`
   - `17:00 – 18:59` → `por_do_sol`
   - `19:00 – 05:59` → `noite`
3. Expor helpers `Game.get_time_of_day_setting()` e `Game.resolve_time_of_day()` (incluindo suporte opcional a `--time=<preset>` na linha de comando para testes).

### Etapa 2 — Interface nas Configurações (`scripts/ui/lmu_menu.gd` e `scripts/ui/pause_menu.gd`)
1. Na aba de configurações do `LmuMenu` (compartilhada entre Garagem e Menu de Pausa), adicionar `OptionButton` **"Horário da Pista"**:
   - `Automático (Relógio)` (mostrando na descrição o período detectado no momento, ex.: *"Segue o relógio do sistema (agora: Noite)"*).
   - `Manhã`, `Tarde`, `Pôr do sol`, `Noite`.
2. Emitir sinal `time_of_day_changed(preset: String)`, propagado pelo `PauseMenu` para o `main.gd` aplicar **ao vivo na pista** sem recarregar a cena.

### Etapa 3 — Céu, Sol e Atmosfera (`scripts/main.gd`, `shaders/sky.gdshader`, `shaders/horizonte.gdshader`)
1. Parametrizar `shaders/sky.gdshader` sobre o `ceu_2k.hdr` atual com uniforms (`sky_tint`, `sky_exposure`, `horizon_color`, `horizon_mix`, `night_amount`) — sem carregar 4 HDRIs novos na memória:
   - **Manhã:** luz mais fria/suave, elevação solar ~28°, neblina matinal leve.
   - **Tarde:** configuração atual próxima de `sun_elev` da pista (~48°–58°, `light_energy = 2.8`).
   - **Pôr do sol:** elevação baixa (~8°–12°), sol alaranjado/dourado, horizonte âmbar/avermelhado.
   - **Noite:** céu escuro azulado (com estrelas procedurais sutis no shader), luz direcional da lua fraca e fria (`light_energy ~ 0.22`), `ambient_light_energy` calibrado para manter pista e referências visíveis.
2. Atualizar `shaders/horizonte.gdshader` com uniform de brilho/tint para o horizonte acompanhar o escurecimento no pôr do sol e à noite.
3. Extrair `_apply_time_of_day(preset)` em `scripts/main.gd`, chamado em `_build_env()` e na troca via `PauseMenu`.

### Etapa 4 — Iluminação Noturna da Pista via Shaders (~0 ms)
1. **Janelas acesas (`shaders/torre.gdshader` e `shaders/fachada.gdshader`):**
   - Adicionar uniform `night_amount` (`0.0` dia, `0.4` pôr do sol, `1.0` noite).
   - Reaproveitar a máscara `glass` e o hash da célula já existentes para somar `EMISSION` quente (amarelo/âmbar/branco-quente) em ~35–50% das janelas à noite. **Zero draw calls extras e zero luzes dinâmicas.**
2. **Legibilidade do asfalto (`shaders/asfalto.gdshader`):**
   - Garantir que o asfalto, zebras e faixas (`pinta`) não fiquem pretos demais à noite calibrando o `ambient_light` + um leve ajuste de contraste/nível mínimo por `night_amount`, preservando o detalhe da textura sem precisar de `OmniLight3D` na pista.

### Etapa 5 — Faróis dos Carros (`scripts/render/car_view.gd`)
1. **Material emissivo nas lentes (todos os presets, 0 ms):**
   - Identificar materiais de faróis dianteiros e lanternas traseiras em `fix_materials()`.
   - Quando `headlights_on = true`, ativar `emission_enabled` (branco-frio na dianteira, vermelho suave na traseira).
   - Bots usam **apenas** esse emissivo (nunca `SpotLight3D`).
2. **Feixe iluminando a pista à frente (escalado por preset):**
   - **`Mínimo` e `Leve` (Mobile / PC fraco):** feixe projetado no chão via malha plana leve (`MeshInstance3D` rente ao asfalto na frente do carro com shader/textura de gradiente suave aditivo) — sem `SpotLight3D` dinâmico, custo próximo de **0 ms**.
   - **`Médio` e `Extremo` (PC):** 2 `SpotLight3D` sem sombra (`shadow_enabled = false`) posicionados na dianteira usando `data.model.length`, `trackFront` e `wheels[0].y`, com alcance ~90 m e ângulo ~35°.
3. **Ativação:**
   - Ligam automaticamente em `por_do_sol` e `noite` (com opção de alternar manualmente por tecla, ex. `L`).
   - Na garagem (`car_studio_view.gd`), manter desligados por padrão.

---

## 4. Testes e Validação

1. Criar `scripts/tests/horario_e_farois.gd` validando:
   - Resolução das faixas de horário no modo `"auto"`.
   - Persistência de `video/horario` em `user://jogo.cfg`.
   - Atualização de `sun`, `sky.gdshader` e `night_amount` ao trocar o horário.
   - Criação/ativação dos faróis (emissivo + feixe por preset) em `CarView` nos 13 carros.
2. Benchmark comparativo de FPS (Interlagos e Laguna Seca) entre **Tarde** e **Noite com farol ligado** nos presets `Leve` e `Extremo` para confirmar que não há perda relevante de desempenho.
