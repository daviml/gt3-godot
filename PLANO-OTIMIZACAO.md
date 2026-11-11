# Plano de Otimização, Fluidez e Telas de Load — GT3 Time Attack (Godot 4)

Objetivo: eliminar os gargalos de carregamento e renderização para deixar o jogo fluido tanto no Desktop (Windows) quanto no Mobile (Android/iOS), antes de avançar para as próximas funcionalidades:
- Reduzir o tempo de abertura do jogo.
- Tornar a troca de carros na garagem rápida e responsiva.
- Acelerar a abertura da pista com o carro escolhido.
- Elevar o FPS (principalmente no preset **Mínimo**, que hoje não entrega o desempenho esperado de uma engine nativa).
- Adicionar páginas/telas de **Load** com progresso real nas transições pesadas.

---

## Diagnóstico dos Gargalos Atuais

### 1. Abertura lenta do jogo (`updater.gd` → `garagem.gd`)
- `scripts/ui/updater.gd` aguarda o `HTTPRequest` de versão (timeout de até `3.0s` se offline/instável) + espera fixa (`0.3s`), e depois chama `ResourceLoader.load_threaded_request` em `scenes/garagem.tscn` — porém `garagem.tscn` é apenas um `Node3D` vazio de 6 linhas.
- Todo o peso roda **sincronamente** na thread principal dentro de `garagem.gd._ready()`:
  - Cria `ReflectionProbe`, `DirectionalLight3D` (com `directional_shadow/size = 4096` no Desktop), 3 `OmniLight3D`s e `SSAO`/`SSR`/`Glow` (no Desktop).
  - Chama `CarView.new(c.id)` que executa `load(data.model.glb)` de forma síncrona (GLBs de `4,5 MB` a `36,8 MB`) e compila shaders na primeira renderização.

### 2. Troca lenta de carros na garagem (`garagem.gd` + `car_view.gd`)
- Cada `◀` / `▶` chama `_show(i)` → `CarView.new(c.id)` → `load(data.model.glb)` **síncrono na main thread** (ex.: `aston-vantage-gt3.glb` = `36,82 MB`, `ford-mustang-gt3.glb` = `29,74 MB`, `corvette-c8r-gt3.glb` = `27,45 MB`).
- Não há cache de `PackedScene`, nem pré-carregamento em background dos carros vizinhos (`idx - 1`, `idx + 1`), nem debounce/cancelamento ao trocar rápido, nem indicador visual de carregamento.
- `CarView._build_wheel()` instancia 24 `MeshInstance3D` de `ghosts` e duplica materiais de `blur_XX` mesmo na garagem, e `fix_materials()` ativa `clearcoat_enabled = true`, disparando novas compilações de pipeline por carro.

### 3. Abertura lenta do mapa com o carro escolhido (`garagem.gd._drive()` → `main.gd._ready()`)
- `scenes/main.tscn` também é um `Node3D` vazio; clicar em `PILOTAR` congela a tela porque `main.gd._ready()` executa tudo sincronamente em um único quadro:
  - Parse de `data/track/track.json` + carregamento/conversão na CPU de `assets/sky/ceu_2k.hdr` (`5,20 MB`) em `_load_sky_tex()` + bake do `Sky` (`RADIANCE_SIZE_256`).
  - `TrackView._ready()`: `load("res://assets/track/cenario.glb")` (`37,42 MB`) + carregamento de `>70 MB` de texturas 2K sem compressão VRAM + `_build_trees()` (`arvores_pos.json`).
  - `SurroundingsView._ready()`: `_build_towers()`, `_build_horizon()` (`horizonte.png`) e **`_split_crowd()`**, que fatia a malha da torcida triângulo por triângulo em GDScript puro na CPU toda vez que a pista abre.
  - `CarView.new(car_id)` recarrega o `.glb` do carro do zero (sem reaproveitar o modelo carregado na garagem).
  - `CarAudio.new(car, car_id)` carrega sincronamente todos os `.wav` de FX e do banco do motor.

### 4. FPS baixo mesmo no preset `Mínimo`
- **Texturas sem compressão VRAM e sem Mipmaps:** todos os PNGs em `assets/textures/`, `assets/trees/` e `assets/track/cenario_*.png` estão importados com `compress/mode=0` (Lossless) e `vram_texture=false`. Além disso, `asphalt_track_*`, `leafy_grass_*`, `sparse_grass_*`, `concrete_wall_*`, `arvores_cor.png` (`8,17 MB`) e `arvores_normal.png` (`11,07 MB`) estão com `mipmaps/generate=false`, gerando *cache thrashing* severo na GPU e consumo de VRAM/banda 4x–8x maior mesmo com `fast_mode = true`.
- **Cenário, árvores e materiais ainda pesados no `Mínimo`:**
  - `SurroundingsView.DETAIL[0]` mantém `"trees": 600.0` (de `>5.000` árvores) com `shaders/impostor.gdshader` usando `ALPHA_SCISSOR_THRESHOLD = 0.5` (quebra Early-Z/HSR) e sem `fast_mode` (fazendo 2 leituras de `normal_atlas` de `11,07 MB` + cálculo de normal por pixel).
  - Materiais do carro mantêm `clearcoat = 1.0` e normal maps, e não há ajuste de `viewport.mesh_lod_threshold` por preset.
  - Objetos secundários sem sombra em `TrackView._fix()` não recebem `visibility_range_end` curto no `Mínimo`.
- **Gargalo de CPU por quadro no HUD e Física:**
  - `Hud._draw()` (`scripts/ui/hud.gd`) redesenha ~100 strings via `SystemFont`, transforma os pontos do minimapa em GDScript todo quadro e **instancia novos `StyleBoxFlat.new()` dentro do `_draw()`** (`_draw_fps`, `_draw_tyres`, `_draw_dash`).
  - `Car.step()` (`scripts/physics/car.gd`) roda até 8 sub-passos no PC (`480 Hz`) / 4 no mobile (`240 Hz`), chamando `locate()`/`_nearest()` 5× por sub-passo e `magic()` 12× por sub-passo.
  - `CarAudio.update()` (`scripts/audio/car_audio.gd`) mantém todos os players de motor e FX rodando continuamente mesmo em `-80 dB`, recalculando `exp`/`pow`/`lerpf` a cada quadro.
- **Configuração de renderizador no `Mínimo`:** `project.godot` fixa `forward_plus`, `anisotropic_filtering_level=4` e `directional_shadow/size=4096` no Desktop; `main.gd._set_quality(0)` não reduz `mesh_lod_threshold`, não reduz `radiance_size` do céu e não desabilita `clearcoat`/normal maps/anisotrópico.

---

## Plano de Execução por Fases

### Fase 1 — Pipeline de Assets, Texturas e Pré-processamento
*Objetivo: reduzir drasticamente uso de VRAM, banda de GPU, tempo de carregamento e travamentos de disco.*

- [x] **1.1 Corrigir `.import` das texturas 3D (`assets/textures/`, `assets/trees/`, `assets/track/cenario_*.png`):**
  - Alterar `compress/mode=0` → `compress/mode=2` (VRAM Compressed: S3TC/BPTC no Desktop, ETC2/ASTC no Mobile).
  - Ativar `mipmaps/generate=true` em todas as texturas 3D (`asphalt_track_*`, `leafy_grass_*`, `sparse_grass_*`, `concrete_wall_*`, `arvores_*`, `cenario_*`).
  - Aplicar `process/size_limit` adequado (ex.: `1024` para materiais secundários de cenário/concreto, `2048` para asfalto/grama/atlas de árvores).
- [x] **1.2 Otimizar `.glb` dos carros e cenário em `tools/prep.ts`:**
  - Limitar resolução das texturas embutidas nos `.glb` dos carros (ex.: máximo `1024`–`2048 px`) e revisar geometria/materiais redundantes para diminuir os modelos maiores (`aston-vantage-gt3.glb`, `ford-mustang-gt3.glb`, `corvette-c8r-gt3.glb`) de 27–37 MB para uma faixa leve (~5–12 MB).
  - Garantir geração de LODs limpos na importação do Godot (`meshes/generate_lods=true`).
- [x] **1.3 Pré-processar a torcida fora do runtime:**
  - Mover o particionamento de `SurroundingsView._split_crowd()` (`scripts/track/surroundings_view.gd`) para etapa offline (`tools/cenario.mjs` ou script gerador de `.scn`/`.res`), eliminando a reconstrução de `ArrayMesh` triângulo a triângulo em GDScript ao abrir a pista.
- [x] **1.4 Carregamento nativo do céu (`ceu_2k.hdr`):**
  - Substituir `Image.load_from_file()` + `convert(FORMAT_RGBAH)` em `main.gd._load_sky_tex()` por carregamento direto via recurso importado do Godot (`load("res://assets/sky/ceu_2k.hdr")`) comprimido em VRAM.

---

### Fase 2 — Páginas de Load e Cache Compartilhado (`Game` + `LoadingScreen`)
*Objetivo: eliminar congelamentos em todas as transições com barra de progresso real e reaproveitamento de memória.*

- [x] **2.1 Criar cena reutilizável de Load (`scenes/loading.tscn` + `scripts/ui/loading_screen.gd`):**
  - Tela limpa com nome da pista/carro escolhido, barra de progresso (0–100%), label da etapa atual e dica/estado sem bloquear o loop de renderização.
  - Suporte a fila de carregamento assíncrono (`ResourceLoader.load_threaded_request`) + execução fatiada de etapas síncronas leves em múltiplos frames (`await get_tree().process_frame` entre etapas).
- [x] **2.2 Cache de `PackedScene` de carros em `scripts/game.gd`:**
  - Manter cache LRU pequeno (carro atual + vizinhos no Desktop; carro atual + 1 no Mobile) para evitar recarregar o `.glb` do disco ao ir da **Garagem → Pista** ou voltar ao mesmo carro.
- [x] **2.3 Otimizar abertura do jogo em `scripts/ui/updater.gd`:**
  - Reduzir timeout de rede para `1.5s`, remover o `await create_timer(0.3)` artificial quando atualizado e pré-carregar de forma assíncrona o `.glb` do `Game.car_id` inicial junto com a barra de progresso do updater, só abrindo a garagem quando o carro inicial já estiver pronto.
- [x] **2.4 Página de Load na transição Garagem → Pista (`garagem.gd._drive()`):**
  - Substituir `get_tree().change_scene_to_file("res://scenes/main.tscn")` direto pela transição via `loading.tscn`:
    1. `0–45%`: `load_threaded_request` de `cenario.glb` e leitura de JSONs (`track.json`, `arvores_pos.json`, `torres.json`).
    2. `45–65%`: pré-carga dos áudios do carro selecionado (`CarAudio`) e céu.
    3. `65–90%`: instanciação progressiva entre frames (`TrackView`, `SurroundingsView`, `CarView` aproveitando o cache).
    4. `90–100%`: warmup de 1–2 frames para compilação de shaders antes de liberar a câmera no grid.
- [x] **2.5 Página de Load na transição Pista → Garagem (`main.gd._to_garage()`):**
  - Usar a tela de load para descarregar a pista, limpar recursos e preparar o estúdio + carro selecionado sem congelar a UI.

---

### Fase 3 — Garagem Instantânea e Responsiva (`garagem.gd` + `car_view.gd`)
*Objetivo: passar de um carro para outro sem travamentos.*

- [x] **3.1 Pré-carregamento assíncrono dos carros vizinhos (`idx - 1`, `idx + 1`):**
  - Assim que um carro é exibido, disparar `ResourceLoader.load_threaded_request` em segundo plano para o próximo e o anterior da lista.
  - Se o usuário trocar rapidamente várias vezes (`◀` / `▶`), cancelar/ignorar cargas antigas e carregar apenas o índice final desejado.
- [x] **3.2 Indicador de carregamento não-bloqueante na Garagem:**
  - Se o carro escolhido ainda estiver carregando em thread separada, manter a câmera/UI responsivas e exibir um overlay/spinner discreto ("Carregando carro...") sobre a plataforma até concluir.
- [x] **3.3 Enxugar o setup do carro e estúdio na Garagem:**
  - Adicionar opção `enable_blur := false` em `CarView` para não instanciar as 24 malhas translúcidas de `ghosts` nem duplicar materiais `blur_XX` na garagem (nem nos presets `Mínimo`/`Leve`).
  - Respeitar o preset gráfico salvo (`user://jogo.cfg`) também dentro de `garagem.gd._build_studio()` (não forçar `SSAO`/`SSR`/`Glow` se o usuário escolheu `Mínimo` ou `Leve`).

---

### Fase 4 — Otimização de FPS no Preset `Mínimo` (GPU, Shaders, CPU e Física)
*Objetivo: atingir FPS alto e estável no `Mínimo` tanto no Windows quanto no Android.*

- [x] **4.1 GPU e Renderização no `Mínimo` (`main.gd._set_quality` + shaders):**
  - Ajustar `get_viewport().mesh_lod_threshold` por preset (ex.: `6.0` no `Mínimo`, `3.0` no `Leve`, `1.0` no `Médio`/`Extremo`).
  - Adicionar `uniform bool fast_mode = false` em `shaders/impostor.gdshader` para pular as 2 leituras de `normal_atlas` e cálculos de normal no `Mínimo`/`Leve`.
  - Reduzir o alcance das árvores em `SurroundingsView.DETAIL[0]` (`Mínimo`) de `600.0` m para `250.0`–`350.0` m.
  - No preset `Mínimo`, simplificar materiais do `CarView` e `TrackView` (desativar `clearcoat_enabled`, `normal_enabled` e filtragem anisotrópica pesada) e reduzir `sky.radiance_size` para `RADIANCE_SIZE_64`.
  - Estender `visibility_range_end` em `TrackView._fix()` também para malhas secundárias sem sombra (placas, cones, detalhes de arquibancada/pit) com alcance reduzido no `Mínimo` (`250–350 m`).
  - Limitar resolução 3D efetiva no `Mínimo` em telas HiDPI/4K no Desktop e avaliar opção de fallback/renderizador `gl_compatibility` para GPUs/drivers muito fracos.
- [x] **4.2 CPU — Otimização do HUD (`scripts/ui/hud.gd`):**
  - Remover todas as alocações de `StyleBoxFlat.new()` de dentro de `_draw()` (`_draw_fps`, `_draw_tyres`, `_draw_dash`), pré-alocando e reutilizando os `StyleBoxFlat`s no `_ready()`.
  - Pré-calcular os pontos transformados do minimapa em `_layout()` (em vez de alocar `PackedVector2Array` e recalcular todos os pontos da pista em `_draw_map()` a cada quadro).
  - Limitar a taxa de redesenho do HUD no `Mínimo` (ou globalmente para `30 Hz` nos painéis de texto) em vez de redesenhar ~100 strings via `SystemFont` a 60–144 FPS no Desktop.
- [x] **4.3 CPU — Física e Áudio (`car.gd`, `track.gd`, `car_audio.gd`):**
  - Permitir `max_sub = 4` (`240 Hz`) no preset `Mínimo` mesmo no Desktop (além do mobile), e reduzir buscas redundantes em `Track.locate()`/`_nearest()` aproveitando o `hint` já calculado no centro do carro.
  - Em `CarAudio.update()`, pausar/parar (`stream_paused = true`) loops cujo ganho seja efetivamente zero (`<= 0.001`: `grass_player`, `gravel_player`, `tyre_player` e loops de motor fora da janela ativa), evitando mixagem e cálculos contínuos de áudio em silêncio.

---

## Critérios de Validação (Antes vs. Depois)

Medir com `Time.get_ticks_msec()` e contador de FPS do HUD (`--shot` / `hud.fps` no Desktop Windows e APK Android):
1. **Tempo de abertura (boot → garagem visível com carro carregado).**
2. **Tempo de troca de carro na garagem (`◀` / `▶` entre carros pesados como Aston/Mustang/Corvette).**
3. **Tempo de transição Garagem → Pista (com barra de progresso contínua na página de load, sem congelamento).**
4. **FPS médio e mínimo no preset `Mínimo` e `Leve` durante volta completa em Interlagos.**
