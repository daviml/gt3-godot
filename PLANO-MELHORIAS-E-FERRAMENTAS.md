# Plano de Evolução do `gt3-godot` — Ferramentas de IA & Melhorias de Jogo

Este plano integra **4 ferramentas/práticas gratuitas de engenharia assistida por IA** diretamente às próximas fases de evolução do `gt3-godot`, aproveitando o que já está instalado na máquina (`Godot 4.7.2`, `FFmpeg 9.0.1`, `Python 3.13`, `Node.js`) e respeitando a arquitetura do projeto.

---

## Parte 1 — Ferramentas e MCPs para Preencher Lacunas da IA

### 1. `AGENTS.md` na Raiz do Repositório — ✅ CRIADO
- **Qual lacuna preenche:** Evita que a IA edite `.glb` gerados por script, adicione luzes dinâmicas caras nos presets mobile (`Mínimo`/`Leve`), esqueça tipagem estrita em GDScript ou quebre o `updater.gd`.
- **Arquivo:** `AGENTS.md` na raiz do repositório, documentando a arquitetura (`Car`, `Track`, `CarView`, `TrackView`, `CarAudio`), o pipeline em `tools/`, a matriz dos 4 presets gráficos e os comandos exatos de teste e captura comparativa.

---

### 2. Godot MCP (`Coding-Solo/godot-mcp` ou `hi-godot/godot-ai`)
- **Qual lacuna preenche:** Hoje a validação visual e estrutural depende de rodar scripts batch como `capture_compare.gd`, `check_cars.gd` ou `inspect_cars.gd`. Com o Godot MCP conectado, a IA consegue abrir cenas, inspecionar a árvore de nós instanciada em tempo real (muito útil para ver nós gerados por `TrackView._fix()` e `CarView._build_wheel()`), ler erros/warnings do debugger e validar layouts de UI (`LmuMenu`, `Hud`).
- **Como implantar no ambiente atual:**
  1. Clonar `https://github.com/Coding-Solo/godot-mcp` em `C:\Users\davim\Tools\godot-mcp` e rodar `npm install && npm run build`.
  2. Configurar no MCP do Antigravity apontando `GODOT_PATH` para `C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64.exe`.
  3. **Uso combinado:** usar o **Godot MCP** durante o desenvolvimento interativo (inspeção de árvore, materiais, shaders e UI) e manter o **`capture_compare.gd`** como portão final de regressão visual e benchmark de FPS nos checkpoints de Interlagos e Laguna Seca.

---

### 3. Pipeline de Áudio Automatizado (`tools/audio_prep.py` + `FFmpeg` + Freesound CC0)
- **Qual lacuna preenche:** A IA não "ouve" diretamente o jogo, mas com `FFmpeg 9.0.1` + `Python 3.13` (já instalados no PC) ela consegue analisar espectro/volume, remover silêncio inicial, normalizar loudness, aplicar filtros e criar loops perfeitos sem estalos (*zero-crossing* + *crossfade*).
- **O que construir (`tools/audio_prep.py`):**
  - **Modo `oneshot`:** corta silêncio inicial/final (`silenceremove`), normaliza pico a `-1.5 dBFS`, converte para `44100 Hz, 16-bit PCM, mono` (latência zero para troca de marcha, cliques de UI e batida de zebra).
  - **Modo `loop`:** recorta o trecho mais estável do sample CC0, aplica crossfade de `150 ms` entre fim e início buscando cruzamento por zero (*zero-crossing*), equaliza (high-pass/low-pass) e grava os metadados de loop no `.wav`.
  - **Modo `inspect`:** gera relatório JSON de duração, RMS, pico dBFS e frequência dominante de todos os arquivos em `assets/sounds/` para garantir que nenhum som estoure ou fique inaudível frente ao motor.

---

### 4. Blender + Blender MCP (`ahujasid/mcp-for-blender`) — ✅ CONFIGURADO
- **Qual lacuna preenche:** A Godot não modela nem corrige topologia/UV/materiais mal separados dentro de `.glb`.
- **Regra de convivência com o pipeline `tools/`:**
  - **Nunca** editar `assets/track/cenario.glb` ou `assets/tracks/laguna-seca/cenario.glb` manualmente no Blender (eles são regerados por `node tools/cenario.mjs`).
  - **Onde usar o Blender MCP:**
    1. **Os 13 carros GT3 (`assets/cars/<id>/`):** separar faces de faróis dianteiros (`HEADLIGHT_LENS`, `HEADLIGHT_EMISSIVE`) e lanternas/luzes de freio (`TAILLIGHT`, `BRAKELIGHT`) nos modelos do Sketchfab onde tudo veio num único material genérico; corrigir normais invertidas e reduzir contagem de triângulos (Decimate limpo) para melhorar o FPS no celular.
    2. **Props modulares de destaque (`assets/props/*.glb`):** modelar objetos icônicos leves (ex.: torre de controle de Laguna Seca, pórticos detalhados, postos de fiscal, guindaste/ambulância low-poly) para o `scenery.ts` instanciar ao longo da pista.
- **Como implantar:**
  1. Instalar o Blender LTS via terminal: `winget install BlenderFoundation.Blender`.
  2. Instalar o addon `ahujasid/mcp-for-blender` no Blender e registrar o servidor `blender-mcp` via `uvx blender-mcp` no Antigravity.

---

## Parte 2 — Roteiro de Melhorias do Jogo (Fases de Execução)

### Fase 1 — Fundação: `AGENTS.md`, Godot MCP e Auditoria dos 13 Carros
1. [x] Criar `AGENTS.md` na raiz com arquitetura, orçamento por preset e comandos de teste.
2. [x] Configurar o **Godot MCP** apontando para o Godot 4.7.2 local.
3. [x] Rodar script de inspeção (`scripts/tests/inspect_cars.gd` + `scripts/tests/audit_cars.gd`) nos 13 carros GT3 para mapear materiais de farol/freio e contagem de triângulos:
   - **Prontos via regex em `CarView` (3):** `corvette-c6r-gt3`, `bmw-m6-gt3`, `corvette-c7-gr3`.
   - **Parciais (`red_glass`/`light_emissive` atrás, mas material principal compartilhado frente+trás) (3):** `audi-r8-lms-gt3`, `nissan-gtr-gt3`, `lamborghini-gallardo-gt3`.
   - **Material único frente+trás (precisam separar `HEADLIGHT`/`BRAKELIGHT` via Blender MCP ou por Z) (6):** `bmw-m4-gt3`, `ferrari-488-gt3`, `lamborghini-huracan-gt3`, `mclaren-720s-gt3`, `bentley-continental-gt3-2020`, `aston-v12-vantage-gt3`.
   - **Materiais genéricos `Material.001..005` (precisa Blender MCP) (1):** `acura-nsx-gt3`.
   - **Alerta de triângulos (>100k base, candidatos a Decimate na Fase 4):** `mclaren-720s-gt3` (154.884), `corvette-c6r-gt3` (151.006), `lamborghini-huracan-gt3` (150.583), `audi-r8-lms-gt3` (149.889), `corvette-c7-gr3` (133.795), `nissan-gtr-gt3` (133.175), `bmw-m4-gt3` (107.980).

---

### Fase 2 — Horário nas Pistas, Iluminação Noturna (0 ms) e Faróis (`PLANO-HORARIO-FAROIS.md`)
Implementar o plano já desenhado em `PLANO-HORARIO-FAROIS.md`:
1. **Seleção de Horário (`scripts/game.gd`, `lmu_menu.gd`, `pause_menu.gd`):**
   - `Automático (Relógio do Sistema)` como padrão + escolha manual (`Manhã`, `Tarde`, `Pôr do sol`, `Noite`) com troca ao vivo na pista e flag `--time=<preset>` na CLI.
2. **Atmosfera e Céu (`scripts/main.gd`, `shaders/sky.gdshader`, `shaders/horizonte.gdshader`):**
   - Parametrizar `sky.gdshader` e `horizonte.gdshader` sem carregar HDRIs extras na RAM.
3. **Noite Leve via Shaders (~0 ms de custo):**
   - Acender janelas proceduralmente em `shaders/torre.gdshader` e `shaders/fachada.gdshader` via uniform `night_amount` (sem luzes dinâmicas na pista).
   - Calibrar legibilidade noturna em `shaders/asfalto.gdshader`.
4. **Faróis e Lanternas nos 13 Carros (`scripts/render/car_view.gd`):**
   - Emissivo nas lentes de farol e lanterna traseira em todos os presets (0 ms).
   - Feixe de luz no asfalto: malha plana leve com shader aditivo nos presets `Mínimo` e `Leve` (~0 ms) e `SpotLight3D` duplo sem sombra nos presets `Médio` e `Extremo`.
   - **Bonus Game Feel:** ativar emissão forte nas **luzes de freio (`BRAKELIGHT`)** sempre que `car.brake > 0.05` (muito visível na câmera de perseguição, especialmente no pôr do sol e à noite).
5. **Validação:** criar `scripts/tests/horario_e_farois.gd` e rodar `capture_compare.gd --bench` comparando Tarde vs. Noite.

---

### Fase 3 — Evolução do Áudio e "Game Feel" GT3 (`tools/audio_prep.py` + `CarAudio`)
Usar o pipeline `FFmpeg + Python` com samples CC0 para elevar a imersão sonora em `scripts/audio/car_audio.gd` e na UI:
1. **Criar `tools/audio_prep.py`:** automatizar corte, normalização, filtros e criação de loops perfeitos em `assets/sounds/fx/`.
2. **Novos efeitos físicos na pista (`CarAudio`):**
   - **Zebra Contínua (`kerb_loop.wav`):** loop de vibração grave modulado em pitch e ganho pela velocidade sobre a zebra (`on_kerb`), complementando o ataque do `bump_front1`.
   - **Freio de Carbono Cantando (`brake_squeal.wav`):** assobio agudo sutil quando `brake > 0.5` e a velocidade está entre `60 km/h` e `220 km/h`.
   - **Fundo Raspando no Asfalto (`bottom_scrape.wav`):** one-shot metálico/fibra quando a compressão da suspensão atinge o batente em alta carga vertical (ex.: saída do Corkscrew, Curva 6 de Laguna Seca, Mergulho/Senna em Interlagos).
   - **Pipocos de Escape na Redução (`backfire_1..3.wav`):** estalos curtos na bus `Engine`/`FX` ao reduzir marcha em RPM alto ou soltar o acelerador abruptamente acima de 7.000 RPM.
3. **Áudio de Interface (`LmuMenu` e `Hud`):**
   - Sons curtos e secos estilo simulador moderno para clique de botão, troca de aba, início de sessão e cruzamento da linha de chegada (volta válida vs. recorde pessoal/roxo).
4. **Validação:** atualizar `scripts/tests/audio.gd` para testar todos os novos gatilhos e buses.

---

### Fase 4 — Acabamento Visual de Pistas & Carros (Blender + Comparativo LMU) — ✅ CONCLUÍDA
1. [x] **Refinamento de Modelos 3D com Blender (`tools/car_polish.py`):**
   - Materiais de luzes frente/trás separados em `HEADLIGHT_*` e `BRAKELIGHT_*` nos 10 carros pendentes (incluindo `acura-nsx-gt3`), e correção de `car.brake` → `car.brake_out` em `scripts/render/car_view.gd` para acender luzes de freio.
   - Decimate limpo (`COLLAPSE`, alvo ~78k tris) nos 7 carros acima de 100k triângulos base (`mclaren-720s-gt3`, `corvette-c6r-gt3`, `lamborghini-huracan-gt3`, `audi-r8-lms-gt3`, `corvette-c7-gr3`, `nissan-gtr-gt3`, `bmw-m4-gt3`).
   - *Hero props* ajustados em `tools/cenario/`: correção de orientação da "salsicha" amarela do Corkscrew em `laguna/scenery.ts` e torre de controle detalhada com placa `INTERLAGOS`, dois níveis envidraçados e antena em `interlagos/scenery.ts`, com reexportação de ambos os `cenario.glb`.
2. [x] **Passada Fina Lado a Lado (`capture_compare.gd`):**
   - Comparação visual nas câmeras `--cam=0` e `--cam=1` em Interlagos e Laguna Seca contra os frames de referência do LMU.
   - Benchmark `--bench` dentro do orçamento: Interlagos `Mínimo` (`q=0`) a `16.67–16.70 ms/frame` (`~60 FPS`, 179 draw calls) e Laguna Seca `Leve` (`q=1`) a `16.66–16.77 ms/frame` (`~60 FPS`, 242–293 draw calls).
