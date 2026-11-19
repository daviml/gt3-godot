# Plano de Implementação — Autodromo Internazionale Enzo e Dino Ferrari (Imola) (`gt3-godot`)

Este documento define o roteiro completo e modular para adicionar **Imola (Grand Prix — 4.909 m, 19 curvas, sentido anti-horário)** ao `gt3-godot`, evoluindo a arquitetura do pipeline de pistas para **corrigir as dores de Interlagos e Laguna Seca** e estrear o uso integrado do **Blender MCP** e do **Godot MCP**.

> **Regra de ouro:** *medir em vez de desenhar no olho, validar cada fase com números/testes antes de avançar, e nunca comprometer os 60 FPS nos presets mobile (`Mínimo` e `Leve`).*

---

## 0. Entradas Já Disponíveis e Metas de Referência

### 0.1 Telemetria Real (Garage 61 — iRacing GT3)
Já presente em `garage61/`:
1. **BMW M4 GT3 EVO** (`01:40.124`) — `Garage 61 - Magnus Jørgensen - BMW M4 GT3 EVO - Autodromo Internazionale Enzo e Dino Ferrari (Grand Prix) - 01.40.124 - 01M78C8GN0QHMQVJP00HJM9YW7.csv` *(carro presente no jogo: `bmw-m4-gt3`)*
2. **Ford Mustang GT3** (`01:40.251`) — `Garage 61 - Steven Freiburghaus - Ford Mustang GT3 - Autodromo Internazionale Enzo e Dino Ferrari (Grand Prix) - 01.40.251 - 01M665V2J4K5A1AJM8N68BWGXD.csv`
3. **Mercedes-AMG GT3 2020** (`01:39.468`) — `Garage 61 - Villads Meinert - Mercedes-AMG GT3 2020 - Autodromo Internazionale Enzo e Dino Ferrari (Grand Prix) - 01.39.468 - 01M78589S3H6FZZ9WDKNMT0JAP.csv`

*Ter 3 carros diferentes (M4, Mustang e AMG) permite cruzar traçado, larguras, pontos de freada, `VertAccel`, `LatAccel` e `YawRate` sem viés de um único piloto/setup.*

### 0.2 Vídeo de Referência (Le Mans Ultimate — LMGT3)
- **URL:** `https://www.youtube.com/watch?v=AsMobXd_w_c`
- **Destino local (fora do git):** `IMOLA-LMU-LMGT3.mp4` na raiz + frames extraídos em `build/compare/lmu_imola/`.

### 0.3 Dados Geoespaciais Públicos (Itália / Emília-Romanha)
- **Coordenadas centrais:** `~44.3439° N, 11.7167° E` (Imola, BO, Itália — às margens do rio Santerno e *Parco delle Acque Minerali*).
- **Elevação / LiDAR 1 m (CC BY 4.0):**
  1. **Primário:** **Geoportale Regione Emilia-Romagna** (WCS / GeoTIFF LiDAR 0,5–1 m) e/ou **MASE Geoportale Nazionale (PST-A)** — fornecem **DTM** (terreno nu, para pista e camber) **e DSM** (superfície, para extrair altura real das copas de árvores do parque e telhados de prédios via `DSM − DTM`).
  2. **Fallback / terreno distante (horizonte ±2 km):** **TINITALY v1.1 (10 m)** via INGV / ArcoDataHub COG.
- **Traçado e entorno:** OpenStreetMap (`/api/0.6/map?bbox=`).
- **Ortofoto / Satélite (~0,25 m):** Esri World Imagery (e/ou ortofoto regional da Emília-Romanha em `EPSG:3857`) para medir bordas do asfalto, zebras, brita e sombras de pórticos.

---

## 1. O Que Vamos Fazer Melhor Desta Vez (Lições de Interlagos & Laguna Seca)

| Problema no passado | Solução nova a estrear em Imola |
|---|---|
| Cópia inteira de 5 arquivos `.ts` por pista (`tools/cenario/laguna/*.ts`) cheios de `if/else` de metragem | **Perfil visual declarativo (`visual_profile.json`)** por faixa `[s0, s1]` descrevendo lado esquerdo/direito (`zebra`, `faixas`, `brita`, `tipo e distância de barreira`, `alambrado`, `cores`) lido por um gerador reutilizável |
| `wallL`/`wallR` genéricos (~22 m) criando gramados falsos onde o muro é colado na pista | Medir `wallL`/`wallR` reais via OSM (`barrier=wall/fence`) + satélite + vídeo do LMU, trecho a trecho |
| Zebras geradas só pela curvatura (perdendo zebras planas, largas e salsichas reais) | **Detecção de zebras no satélite 0,25 m** + ajuste fino pelo vídeo do LMU (cores italianas vermelho/branco/verde e salsichas em Tamburello, Villeneuve e Variante Alta) |
| Árvores em fileiras genéricas tampando vistas abertas | Usar **LiDAR `DSM − DTM`** para posição e altura reais do *Parco delle Acque Minerali* + máscara de limpeza nas áreas abertas do vídeo |
| Ciclo lento de 1–2 min por ajuste visual (exportar GLB → `--import` no Godot → capturar) | Adicionar **`--preview` no `tools/cenario.mjs`** para fotografar os checkpoints `[s, d, yaw]` direto no Chromium/Three.js em ~2 s antes da passagem final no Godot |
| Marcos icônicos feitos de caixas/cilindros genéricos no código | Usar **Blender MCP** para modelar **Hero Props modulares leves** em `assets/props/imola/*.glb` (torre de controle, pórticos, tribuna histórica) instanciados pelo gerador |
| Câmera de comparação em `d = 0` distorcendo percepção de muros/zebras | Checkpoints do `capture_compare.gd` já criados no padrão `[nome, s, d_lateral, yaw_deg]` alinhados ao traçado do vídeo + opção `--mover` |
| Armadilhas GLB → Godot (`CLAMP_TO_EDGE`, `KHR_texture_transform`, fundações flutuando) | Checklist obrigatório no gerador: `wrapS = wrapT = RepeatWrapping`, repetição nos UVs/canvas (sem `tex.repeat`), fundações até `heightAt - 3 m`, prefixo `ess_` no `Mínimo` |

---

## 2. Roteiro por Fases (Execução Incremental)

Cada fase tem entregáveis claros e um **Portão de Saída** (só avançamos quando o portão passa).

---

### Fase 0 — Coleta de Dados, Download do Vídeo e Auditoria do LiDAR
**Objetivo:** reunir todos os dados brutos em `build/imola/` (não versionado) e confirmar qualidade do LiDAR 1 m antes de escrever código de geometria.

1. **Baixar o vídeo de referência do LMU:**
   - `python -m yt_dlp -f "bestvideo[height<=1080]+bestaudio/best[height<=1080]" --merge-output-format mp4 -o "IMOLA-LMU-LMGT3.mp4" "https://www.youtube.com/watch?v=AsMobXd_w_c"`
   - Inspecionar duração, câmeras disponíveis (onboard / 3ª pessoa) e horário/iluminação do vídeo.
2. **Inspecionar os 3 CSVs do Garage 61:**
   - Verificar colunas (`Lat`, `Lon`, `Alt`, `LapDist`, `Speed`, `Throttle`, `Brake`, `Gear`, `LatAccel`, `VertAccel`, `YawRate`), comprimento registrado da volta e pontos de velocidade mínima em cada curva.
3. **Criar `tools/tracks/imola/download.py`:**
   - Baixar **LiDAR DTM 1 m** e **DSM 1 m** (Emília-Romanha WCS / MASE) em blocos pequenos na projeção nativa (`EPSG:3857` / `EPSG:32632` reprojetado sem degraus) cobrindo a pista + `~1 km` de margem; baixar **TINITALY 10 m** para o anel externo de horizonte.
   - Baixar **OSM** (`bbox` da pista + parque + rio Santerno + arredores).
   - Baixar **satélite Esri 0,25 m** em blocos `EPSG:3857` cobrindo toda a pista e pit lane.

**Portão de Saída (Fase 0):**
- [ ] Vídeo `IMOLA-LMU-LMGT3.mp4` baixado e frames-chave mapeados por câmera.
- [ ] Emendas dos blocos de LiDAR e satélite conferidas (zero degraus e zero buracos no relevo).
- [ ] Confirmado se temos **DTM 1 m** (e se **DSM 1 m** cobre toda a pista + parque).

---

### Fase 1 — Geometria, Elevação, Camber e Validação Física (`track.json`)
**Objetivo:** construir o traçado mais fiel possível de Imola e validá-lo matematicamente contra as 3 voltas do Garage 61 **antes** de tocar no cenário 3D.

1. **Criar `tools/tracks/imola/build_track.py`:**
   - Extrair centerline do OSM (`highway=raceway`, excluindo pit lane e variantes antigas), encadear volta fechada em sentido **anti-horário**.
   - Alinhar `s = 0` (linha de chegada) e sentido usando as 3 voltas do Garage 61.
   - Suavizar polígono OSM (`σ ≈ 5–6 m`) preservando o raio real das chicanes (Tamburello, Villeneuve, Variante Alta).
   - Medir bordas do asfalto (`wl`, `wr`) perpendicularmente a cada 1 m no satélite 0,25 m (mascarando pit lane e escapes asfaltados) e recentralizar iterativamente.
   - Extrair altitude do **LiDAR DTM 1 m** (filtro de mediana para pontes + suavização leve `σ ≈ 4 m`).
   - Extrair **camber (`bank`)** medindo LiDAR a `±3,5 m` (e conferindo em múltiplas linhas nas curvas largas como Tosa, Piratella e Rivazza), suavizado (`σ ≈ 10 m`).
   - Mapear as **seções oficiais de Imola** (`sections`):
     1. Reta Principal (*Start/Finish*)
     2. Variante del Tamburello (T2–T4)
     3. Variante Villeneuve (T5–T6)
     4. Curva della Tosa (T7)
     5. Curva della Piratella (T9)
     6. Acque Minerali (T11–T13 — descida forte + compressão)
     7. Variante Alta (T14–T15 — chicane em subida com salsichas)
     8. Discesa verso Rivazza
     9. Rivazza 1 & 2 (T17–T18 — dupla esquerda em descida)
     10. Traguardo / Reta Final
2. **Criar `tools/tracks/imola/build_osm.py` e `tools/tracks/imola/build_surfaces.py`:**
   - Classificar **brita × grama × escape asfaltado × rio Santerno** no satélite + OSM (`natural=sand`, `waterway=river`).
   - Detectar **zebras** diretamente no satélite (cores vermelho/branco/verde) + arquivo de override manual para zebras elevadas / salsichas (Variante Alta, Tamburello, Villeneuve).
   - Extrair `wallL`/`wallR` reais a partir de `barrier=wall` + satélite (acabando com o muro fixo em 22 m).
3. **Exportar dados para o Godot e converter referências:**
   - `npx vite-node pista.ts -- imola` → gera `data/tracks/imola/{track,terrain,osm}.json`.
   - `npx vite-node referencia.ts -- imola ...` → gera `data/reference/imola-m4.json`, `imola-mustang.json` e `imola-amg.json`.
   - Registrar `"imola"` em `data/tracks.json` (com `refs` apontando `bmw-m4-gt3` → `imola-m4` e fallback para os demais GT3).
4. **Criar teste automatizado `scripts/tests/imola.gd`:**
   - Comprimento ≤ `0,5%` dos **4.909 m** oficiais.
   - Desnível total (~34–35 m) e compressões críticas (descida para Acque Minerali, subida para Variante Alta, descida para Rivazza 1).
   - `VertAccel` do Garage 61 vs. `v² · curvatura vertical` dentro de `±0,15–0,20 g`.
   - As 3 voltas do Garage 61 cabem entre `wl`/`wr` (+ zebra) em `≥ 99%` da volta.
   - `RefBot` completa voltas **válidas** a `≤ 3%` do tempo real (`~1:40`) e velocidades mínimas por curva a `≤ 10 km/h` do iRacing, sem decolar.

**Portão de Saída (Fase 1):**
- [ ] `scripts/tests/imola.gd` passando em 100% das métricas de geometria, relevo, camber e `RefBot`.
- [ ] `paridade.gd` e `laguna_seca.gd` sem regressão.

---

### Fase 2 — Arquitetura Melhorada do Gerador de Cenário (`visual_profile.json` + `--preview`)
**Objetivo:** eliminar a duplicação de código de cenário e acelerar a iteração visual antes de construir o visual fino de Imola.

1. **Criar esquema declarativo `tools/tracks/imola/visual_profile.json`:**
   - Define por faixa `[s0, s1]` e lado (`L` / `R`):
     - `kerb`: tipo (`flat`, `raised`, `italian_rwg`, `sausage`), largura e cor.
     - `strips`: sequência da linha branca para fora (ex.: `["kerb", "green_paint:2.0", "gravel", "wall"]` ou `["kerb", "asphalt:4.0", "tecpro"]`).
     - `barrier`: distância real, tipo (`wall`, `rail`, `tecpro`, `tecpro2`, `tyre`), `fence: true/false`, cor/banner fictício.
   - Define também listas declarativas para:
     - `bridges` (pontes/pórticos com `s`, tipo, altura, texto fictício/Imola).
     - `braking_boards` (placas `150 / 100 / 50` derivadas da telemetria + vídeo, sempre com prefixo `ess_`).
     - `pit_lane` (entrada após Rivazza 2 com atenuador, mureta dos boxes, saída antes do Tamburello).
     - `hero_props` (lista de `.glb` modulares vindos do Blender MCP com `[s, d, yaw, scale, min_quality]`).
2. **Criar módulo limpo `tools/cenario/imola/`** que consome `visual_profile.json` (em vez de dezenas de `if/else` fixos), garantindo desde o dia 1:
   - `wrapS = wrapT = THREE.RepeatWrapping` em todas as texturas repetíveis.
   - Repetição aplicada nos UVs ou direto no canvas (nunca `tex.repeat.set()` / `KHR_texture_transform`).
   - Normais verificadas em todas as faixas verticais.
   - Fundações de prédios e arquibancadas descendo até `heightAt(x, z) - 3 m`.
   - Agrupamento de malhas por região (~250 m) e prefixo `ess_` em placas de frenagem, zebras, brita e muros.
3. **Adicionar modo `--preview` no `tools/cenario.mjs`:**
   - Permite fotografar a lista de checkpoints `[s, d, yaw]` direto na cena Three.js no Chromium em ~2–3 s, salvando em `build/compare/imola/preview/` sem precisar exportar GLB nem reimportar no Godot durante ajustes de posição.

**Portão de Saída (Fase 2):**
- [ ] `node cenario.mjs --track=imola --preview` gerando capturas rápidas em segundos.
- [ ] `node cenario.mjs --track=imola` exportando `assets/tracks/imola/cenario.glb` limpo, sem warnings de textura ou UV.
- [ ] Interlagos e Laguna Seca inalteradas.

---

### Fase 3 — Entorno Real (LiDAR `DSM − DTM`, Rio Santerno, Bioma Italiano e Horizonte)
**Objetivo:** capturar a identidade visual única de Imola — um autódromo encaixado num parque arborizado e colinas da Emília-Romanha, bem diferente do vale árido de Laguna Seca e da zona urbana de Interlagos.

1. **Árvores e prédios com altura real (`DSM − DTM`):**
   - Criar script `tools/tracks/imola/build_canopy.py` que subtrai `DSM - DTM`:
     - Dentro do *Parco delle Acque Minerali* e colinas de Tosa/Piratella/Rivazza: detectar copas reais, posição e altura → alimentar `arvores_pos.json` com espécies mediterrâneas/europeias (pinheiros-mansos, ciprestes, carvalhos/plátanos) e **limpeza seletiva** onde o vídeo do LMU mostra morros de grama abertos (como a arquibancada natural da Tosa e Rivazza).
     - Sobre pegadas de prédios do OSM: usar altura real medida pelo DSM (evitando galpões virarem torres).
2. **Elementos marcantes do terreno:**
   - **Rio Santerno** correndo fora da reta principal/Tamburello/Villeneuve (malha de água barata ou textura no terreno).
   - **Arquibancadas naturais (gramados em talude)** da Tosa, Acque Minerali e Rivazza — muito visíveis no LMU, com torcida (`MultiMesh`) do `Leve` para cima.
   - **Horizonte (`arredores.mjs --track=imola`):** colinas da Emília-Romanha (Apeninos ao sul, cidade baixa de Imola ao norte), `torres.json` vazio ou mínimo (sem arranha-céus).
3. **Calibração de shaders e cores em `data/tracks.json → visual`:**
   - **Asfalto:** cinza médio-escuro europeu com remendos, emendas e trilho de borracha forte derivado das 3 voltas do Garage 61.
   - **Grama:** verde-oliva/gramado italiano vivo (mais verde que Laguna Seca, mais sóbrio que o verde tropical de Interlagos).
   - **Brita:** cascalho claro cinza-bege de alto contraste contra o asfalto (visível inclusive no `Mínimo`), especialmente em Tamburello, Tosa, Piratella, Acque Minerali e Rivazza.
   - **Sol (`sun_u`, `sun_elev`):** calibrado pela direção das sombras no vídeo `IMOLA-LMU-LMGT3.mp4`.

**Portão de Saída (Fase 3):**
- [ ] `arredores.mjs --track=imola` gerando `horizonte.png` e `arvores_pos.json` coerentes com o parque e colinas.
- [ ] Cena carregando no Godot 4 (`--import` + execução) sem erros nem prédios flutuando.

---

### Fase 4 — Hero Props Modulares via Blender MCP (`assets/props/imola/`)
**Objetivo:** elevar o acabamento visual dos marcos icônicos de Imola usando o **Blender MCP** sem nunca editar `cenario.glb` na mão.

**Regra de orçamento mobile:** cada hero prop deve ser low-poly limpo (meta `300–2.500` triângulos por prop), texturas compactas (`512×512` ou `1024×512` em atlas) e **ocultado automaticamente no preset `Mínimo`** (exibido do `Leve` para cima com `visibility_range_end`).

Props prioritários a modelar via **Blender MCP** (guiados pelos frames do vídeo do LMU):
1. **Torre de Controle / Pódio de Imola** (icônica na reta dos boxes, com janelas escuras que acendem no modo noturno via shader/emissivo).
2. **Prédio dos Boxes & Terraço de Imola** (fachada modular repetível com garagens, mureta e costas texturizadas para quem vem do miolo).
3. **Pórticos / Passarelas características** (passarela da reta principal, pórtico de Acque Minerali / Variante Alta) com placas fictícias no estilo visual do vídeo (sem copiar logos reais de patrocinadores).
4. **Props compartilháveis de paddock/pista** (reutilizáveis depois em Interlagos e Laguna Seca):
   - Posto de fiscal de pista (*marshal post*)
   - Guindaste / ambulância / carro de resgate low-poly
   - Tendas e caminhões de paddock

**Portão de Saída (Fase 4):**
- [ ] Todos os `.glb` em `assets/props/imola/` auditados (triângulos, normais, UVs, tamanho em KB).
- [ ] Instanciados via `visual_profile.json` → `cenario.mjs --track=imola` e visíveis corretamente no Godot nos presets `Leve`, `Médio` e `Extremo` (e ocultos no `Mínimo`).

---

### Fase 5 — Inspeção ao Vivo (Godot MCP) e Comparação Quadro a Quadro com o LMU
**Objetivo:** fechar a fidelidade visual no detalhe, curva por curva, usando o protocolo que funcionou na revisão de Interlagos.

1. **Inspeção estrutural via Godot MCP:**
   - Abrir e inspecionar a cena carregada com Imola no Godot: validar árvore de nós gerada por `TrackView` e `SurroundingsView`, checar materiais/shaders aplicados (`asfalto`, `grama`, `brita`, `impostor`, `fachada`), conferir `visibility_range_end`, seleção da pista na Garagem (`lmu_menu.gd`) e ausência de erros/warnings no debugger.
2. **Montar lista de ~16–20 checkpoints em `scripts/tests/capture_compare.gd` (`CHECKPOINTS_IMOLA`):**
   - Cada checkpoint com `[nome, s, d_lateral, yaw_deg, frame_chase, frame_onboard]` cobrindo:
     1. Reta Principal / Pórtico / Torre dos Boxes
     2. Entrada do Tamburello (freada + placas)
     3. Saída do Tamburello (zebras + brita)
     4. Variante Villeneuve (chicane rápida)
     5. Freada e grampo da Tosa (arquibancada natural + brita)
     6. Subida pós-Tosa → Piratella (entrada cega + brita esquerda)
     7. Descida de Acque Minerali (compressão + parque ao fundo)
     8. Saída de Acque Minerali (subida)
     9. Freada e chicane da Variante Alta (salsichas + muros próximos)
     10. Descida para Rivazza
     11. Rivazza 1 (freada em descida + brita larga)
     12. Rivazza 2 + entrada dos boxes (atenuador + mureta)
     13. Variante final / reta até linha de chegada
3. **Ciclo de refinamento quadro a quadro:**
   - Extrair frames do `IMOLA-LMU-LMGT3.mp4` para `build/compare/lmu_imola/`.
   - Rodar `capture_compare.gd -- --track=imola --out=build/compare/imola/godot_v1 --quality=2 --cam=0` (e `--cam=1` para onboard, além de `--mover` para validar desfoque/alinhamento dinâmico).
   - Analisar cada par lado a lado **da linha branca para fora, nos dois lados**, ajustando `visual_profile.json` (primeiro via `--preview`, depois exportando GLB final).
   - Repetir folha comparativa nos presets **Mínimo (`--quality=0`)** e **Leve (`--quality=1`)** e no **modo noturno (`--time=noite`)**.

**Portão de Saída (Fase 5):**
- [ ] Todos os checkpoints críticos aprovados lado a lado contra o vídeo do LMU (sem erros gritantes de zebra, brita, muro, placa ou proporção).
- [ ] Legibilidade garantida no `Mínimo` (placas de frenagem, zebras, brita e muros bem nítidos) e no `Noite` (faróis, janelas dos boxes/torre).

---

### Fase 6 — Otimização Mobile, Portão de Regressão e Entrega
**Objetivo:** garantir que Imola rode suave no celular/Web/PC, não infle o APK/PCK e não quebre nada existente.

1. **Benchmark de performance (`capture_compare.gd -- --track=imola --bench`):**
   - Medir `ms/frame` e `draw calls` nos presets `0 (Mínimo)`, `1 (Leve)`, `2 (Médio)` e `3 (Extremo)`.
   - Meta: **não ser pior que Interlagos** no `Mínimo` (~16,7 ms / ≤ 200 draw calls) e manter 60 FPS estáveis no `Leve`.
2. **Auditoria de peso (APK / Web PCK):**
   - Conferir tamanho de `assets/tracks/imola/cenario.glb`, `assets/props/imola/` e `data/tracks/imola/`.
   - Garantir que todos os brutos (LiDAR, satélite, vídeo, frames de comparação) estejam em `build/imola/` e `build/compare/imola/` (ignorados pelo git e pelo `export_presets.cfg`).
3. **Suíte completa de testes automatizados:**
   ```powershell
   & "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/imola.gd
   & "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/paridade.gd
   & "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/laguna_seca.gd
   & "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/audio.gd
   & "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/horario_e_farois.gd
   & "C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\Git\Davi\REPOS\gt3-godot" --script res://scripts/tests/lmu_menu_test.gd
   ```
4. **Documentação final:**
   - Criar `tools/tracks/imola/LEIA-ME.md` com comandos de regeneração e tabela de conferências (comprimento, desnível, camber medido, `RefBot` × Garage 61 e FPS por preset).

---

## 3. Resumo Rápido de Acompanhamento

- [ ] **Fase 0:** Vídeo LMU baixado + auditoria dos 3 CSVs do Garage 61 + download LiDAR 1 m (DTM/DSM) + OSM + Satélite 0,25 m.
- [ ] **Fase 1:** `build_track.py`, `build_osm.py`, `build_surfaces.py` + validação física (`scripts/tests/imola.gd`) contra os 3 logs do Garage 61.
- [ ] **Fase 2:** `visual_profile.json` declarativo + `cenario.mjs --preview` (iteração rápida em 2 s) + primeira exportação `cenario.glb`.
- [ ] **Fase 3:** `DSM − DTM` (*Parco delle Acque Minerali* + alturas de prédios) + Rio Santerno + horizonte + calibração de shaders/sol.
- [ ] **Fase 4:** Hero Props modulares no **Blender MCP** (torre de controle, boxes, pórticos, props de paddock).
- [ ] **Fase 5:** Inspeção ao vivo no **Godot MCP** + comparação quadro a quadro (`capture_compare.gd`) contra o vídeo do LMU nos presets `0..3` e modo `Noite`.
- [ ] **Fase 6:** Benchmark mobile, auditoria de tamanho APK/PCK, suíte completa de testes e `LEIA-ME.md`.
