# AGENTS.md — Guia de Arquitetura, Regras e Fluxo de Trabalho (`gt3-godot`)

Este arquivo é a referência principal para agentes de IA que trabalham no `gt3-godot`. Leia antes de editar código, shaders, cenas, ferramentas ou assets.

---

## 1. Visão Geral e Princípios Inegociáveis

1. **Referência de Fidelidade (LMU + iRacing / Garage 61):**
   - **Física e pistas:** medidas reais (LiDAR 1 m, OSM, satélite 0,25 m) validadas contra telemetria real de GT3 do **Garage 61 (iRacing)**. Regra de ouro: *medir em vez de desenhar no olho, e validar cada etapa com números e testes*.
   - **Visual e UI:** inspirados no **Le Mans Ultimate (LMU)**, validados quadro a quadro contra os vídeos de referência (`INTERLAGOS-IN-LE-MANS-ULTIMATE-LMGT3-Track.mp4` e `LAGUNA-SECA-LMU-LMGT3.mp4`) usando `scripts/tests/capture_compare.gd`.
2. **Celular Primeiro (Mobile-First Performance):**
   - O jogo roda em **Android**, **Web** e **Windows (PC)**.
   - Os presets **0 — Mínimo** e **1 — Leve** têm orçamento estrito de GPU/CPU para rodar fluido no celular e em renderizador `gl_compatibility`.
   - **Nunca** adicione luzes dinâmicas (`OmniLight3D` / `SpotLight3D`), sombras extras, `SSR`, `SSIL` ou pós-processamento pesado nos presets `Mínimo` e `Leve`.
   - **Referências de pilotagem são sagradas em todos os presets (inclusive no `Mínimo`):** placas de frenagem (`ess_`), zebras, caixas de brita (com cor/textura bem distinta do asfalto), faixas pintadas e muros/barreiras **nunca** podem ser ocultados no `Mínimo`.
3. **Não Editar `.glb` Gerados nem Cenas Procedurais no Escuro:**
   - As pistas (`assets/track/cenario.glb` e `assets/tracks/<id>/cenario.glb`) são **geradas por código** via `tools/cenario.mjs` (`tools/cenario/`). Qualquer ajuste em pista/cenário deve ser feito nos geradores TypeScript e/ou em `scripts/track/track_view.gd` + `shaders/*.gdshader`, seguido de reexportação.

---

## 2. Mapa da Arquitetura

### 2.1 Estado Global e Fluxo de Cenas
- `scripts/game.gd` (`class_name Game`): estado persistido em `user://jogo.cfg` (`car_id`, `track_id`, `mode` `"sim"`/`"arcade"`, preset gráfico `"Mínimo"`/`"Leve"`/`"Médio"`/`"Extremo"`), cache LRU de cenas de carros e helpers de caminhos por pista (`Game.track_data_path()`, `Game.track_asset_path()`).
- `scenes/updater.tscn` + `scripts/ui/updater.gd`: tela inicial de auto-update via pacotes incrementais `.pck` do GitHub Releases (**Nota:** `updater.gd` é isolado e **não** pode depender de `Game` ou outros scripts para permitir que qualquer script do jogo seja atualizado via patch sem exigir novo APK).
- `scenes/garagem.tscn` + `scripts/ui/garagem.gd` + `scripts/ui/lmu_menu.gd`: menu estilo LMU compartilhado entre Garagem e Menu de Pausa (`scripts/ui/pause_menu.gd`).
- `scenes/loading.tscn`: carregamento assíncrono de pista, texturas de céu, carro e streams de áudio antes de ativar a física.
- `scenes/main.tscn` + `scripts/main.gd`: cena principal de corrida.

### 2.2 Física, Pista e Piloto Automático
- `scripts/physics/car.gd` (`class_name Car`): física customizada GT3 rodando em passo fixo (`Car.HZ = 240.0`, sem `VehicleBody3D` da Godot). Simula pneus (Pacejka / slip combinado), aerodinâmica (downforce/drag), suspensão nos 4 cantos, diferencial, freios, ABS, TC e câmbio.
- `scripts/track/track.gd` (`class_name Track`): carrega `track.json` (`stride = 16` + `bank` opcional para camber real de LiDAR). Fornece projeção espacial rápida (`locate(pos, hint)`), normais com camber, limites de pista, zebras (`kerbL`/`kerbR`), brita/escape (`runL`/`runR`) e muros (`wallL`/`wallR`).
- `scripts/physics/bot.gd` (`Bot`) e `scripts/physics/ref_bot.gd` (`RefBot`): piloto automático. Quando a pista possui telemetria de referência para o carro em `data/tracks.json -> refs` (`data/reference/<pista>-<carro>.json`), usa o `RefBot` para seguir o traçado e velocidades reais do iRacing.

### 2.3 Renderização e Shaders
- `scripts/render/car_view.gd` (`class_name CarView`): instancia o `.glb` do carro, alinha o modelo ao CG da física com interpolação sub-frame (`visual_pos`, `visual_rot`), corrige materiais PBR do Sketchfab por regex (`fix_materials`), anima esterço/suspensão/giro das 4 rodas (`wheel_XX`, `caliper_XX`) e gera o motion blur radial das rodas (`blur_XX` com 6 ghosts nos presets `Médio`/`Extremo`) + sombra de contato (`blob_shadow`).
- `scripts/track/track_view.gd` (`class_name TrackView`): carrega `cenario.glb`, substitui materiais pelo pipeline de shaders (`shaders/asfalto.gdshader`, `shaders/grama.gdshader`, `shaders/fachada.gdshader`, `shaders/torre.gdshader`, `shaders/impostor.gdshader`), configura `visibility_range_end` (culling por distância) e alterna `fast_mode` conforme o preset gráfico (`set_detail(0..3)`).
- `scripts/track/surroundings_view.gd` (`class_name SurroundingsView`): renderiza `MultiMesh` de árvores (`Arvores`), torcida (`Torcida`), anel de torres residenciais (`Torres`) e cilindro de horizonte (`Horizonte`).

### 2.4 Áudio (`CarAudio`)
- `scripts/audio/car_audio.gd` + `data/sounds.json`: síntese por bancos de gravações reais (`engine-sim` / Stunt Rally 3) com crossfade de mesma potência (`cos`/`sin`) entre faixas de RPM vizinhas, filtro low-pass dinâmico por carga do acelerador na bus `Engine`, pneus cantando (`Tires`), grama/brita/zebra contínua (`Surface`), vento (`Wind`) e trocas de marcha/raspagem/pipocos (`FX`).
- **Regra de ouro de áudio:** **nunca** sintetizar loops tonais contínuos agudos com senoides (`turbo`, `brake_squeal`, `gearbox_whine` — tendem a virar sirene/apito irritante). Camadas desse tipo só entram com **gravações reais CC0** processadas via `tools/audio_prep.py` e validadas no ouvido.

### 2.5 Ferramentas e Pipeline Offline (`tools/`)
- `tools/prep.ts` e `tools/car_fix.ts`: processam os carros em `assets/cars/<id>/` (separam rodas, pinças de freio e malha de blur, corrigem normais e exportam metadados para `data/cars/<id>.json`).
- `tools/cenario.mjs` (`tools/cenario/cenario.ts`, `interlagos/`, `laguna/`): constrói e exporta `cenario.glb` das pistas usando Vite + Three.js headless. Malhas com prefixo `ess_` (ex.: placas de frenagem) são preservadas no preset `Mínimo`.
- `tools/arredores.mjs`: gera `arvores.json`, `arvores_pos.json`, `torres.json` e `horizonte.png`.
- `tools/tracks/laguna-seca/`: pipeline completo de ingestão de LiDAR USGS 1 m, OSM, satélite Esri e telemetria do Garage 61 (documentado em `GUIA-PISTAS.md`).

---

## 3. Presets Gráficos e Regras de Orçamento

| Nível | Nome | Público-Alvo | Regras de Renderização |
| :---: | :--- | :--- | :--- |
| `0` | **Mínimo** | Celular fraco / Básico | Escala 3D reduzida (`0.65`), `fast_mode = true` nos shaders de asfalto/grama, sem normal maps, sem sombras do sol (`blob_shadow` ativa), sem árvores/torcida/prédios/banners. **Sempre visíveis:** pista, zebras, brita, faixas pintadas, muros, pneus e placas de frenagem (`ess_`). |
| `1` | **Leve** | Celular padrão (60 FPS) | Escala 3D `0.75` no mobile, `fast_mode = true`, exibe prédios, boxes, arquibancadas, árvores (`1200 m`), torcida (`260 m`) e props externos com culling agressivo. Sem `SpotLight3D` dinâmico ou pós-processamento pesado. |
| `2` | **Médio** | Celular forte / PC | Shaders completos (`fast_mode = false`), normal maps e filtragem anisotrópica ativos, desfoque de roda (`blur_enabled = true`), árvores (`2400 m`) e torcida (`400 m`). |
| `3` | **Extremo** | PC Dedicado | Mesma geometria/detalhes de pista do `Médio`, com sombras direcionais de 4 splits, SSAO, SSIL, SSR e glow ativos (quando fora de `gl_compatibility`). |

---

## 4. Como Rodar Testes e Validação Visual

O executável do Godot na máquina local fica em:
- GUI / Renderização (necessário para `capture_compare.gd` salvar texturas da viewport):
  `C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64.exe`
- Console / Headless:
  `C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe`

### 4.1 Rodar Testes Automatizados (`scripts/tests/*.gd`)
Sempre rode os testes relevantes após alterar física, controles, UI, áudio ou pistas:
```powershell
& "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/paridade.gd
& "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/laguna_seca.gd
& "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/audio.gd
& "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/lmu_menu_test.gd
```

### 4.2 Captura e Comparação Visual com o LMU (`capture_compare.gd`)
Para validar mudanças visuais em pista, shaders, iluminação ou carros (não use `--headless` aqui, pois precisa renderizar a viewport):
```powershell
# Interlagos (preset Mínimo=0, Leve=1, Médio=2, Extremo=3) com benchmark de FPS/draw calls:
& "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/capture_compare.gd -- --out=build/compare/teste_interlagos --quality=2 --bench

# Laguna Seca (câmera 0 = perseguição, 1 = capô; --only filtra checkpoints específicos):
& "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/capture_compare.gd -- --track=laguna-seca --out=build/compare/teste_laguna --quality=2 --cam=0 --only=01_freada_andretti,09_corkscrew
```

---

## 5. Cuidados com Build, Export e Auto-Update

- **Proteção de Tamanho do APK/PCK:** Tudo o que for gerado para comparação, cache ou dados brutos de satélite/LiDAR deve ficar dentro de `build/` (que contém `build/.gdignore` e está no `exclude_filter` do `export_presets.cfg`).
- **Tipagem GDScript:** Use tipagem explícita (`var x: float = ...`) ao ler de `Dictionary`/`Array`/JSON para não disparar erros de inferência `Variant` em execução.
- **Idioma e Estilo:** Comentários, mensagens de UI e documentação do projeto são escritos em **português claro e direto**.
- **Planos e Roteiros de Referência:**
  - `docs/planos/PLANO-MELHORIA-GERAL.md`: plano ativo de evolução do jogo (Etapas 1–5: auditoria pós-Blender/mixer de áudio, HUD com Delta + Ghost Car, acabamento visual LMU, áudio CC0 real e IA/novas pistas).
  - `docs/planos/PLANO-MELHORIAS-E-FERRAMENTAS.md`: histórico das Fases 1–4 concluídas (setup de MCPs, horário/faróis, áudio Fase 3 e polish dos 13 carros).
