# Plano de Reformulação das Árvores e Vegetação — `gt3-godot`

Este documento define o plano técnico para substituir as árvores atuais (impostores 2D repetitivos) por um **sistema híbrido de vegetação 3D + impostores de alta qualidade**, combinando **Blender (script headless / Blender MCP)** e **texturas/modelos CC0**, elevando o visual das pistas ao padrão **Le Mans Ultimate (LMU)** sem quebrar o orçamento de **60 FPS no mobile** nem inflar o APK/PCK.

---

## 1. Diagnóstico do Estado Atual

Uma auditoria no pipeline atual (`scripts/track/track_view.gd`, `shaders/impostor.gdshader`, `assets/trees/`, `data/track/arvores.json` e `tools/cenario/interlagos/`) identificou exatamente por que as árvores estão destoando do resto dos gráficos:

1. **Apenas 3 espécies quase idênticas:**
   - `data/track/arvores.json` usa somente `island_tree_01`, `island_tree_02` e `island_tree_03` (do mesmo pack tropical da Poly Haven). Todas são baixas e largas (proporção largura/altura entre `1,35` e `1,72`), esticadas de `2,0×` até `3,5×` em Interlagos (e até `4,8×` em Imola/Laguna).
2. **100% billboards 2D planos — até colados na pista:**
   - Todas as **7.052 árvores** de Interlagos (**3.333** em Laguna Seca, **8.975** em Imola) são quads 2D que giram no eixo Y em direção à câmera. Quando o carro passa a 200+ km/h a 10–50 m da árvore, o quad parece "papelão" e gira de forma artificial.
3. **Ghosting / dupla exposição no shader (`shaders/impostor.gdshader`):**
   - O shader faz `mix(texture(color_atlas, uv0), texture(color_atlas, uv1), blend)` entre duas fotos separadas por 30° (`VIEWS = 12`) com `ALPHA_SCISSOR_THRESHOLD = 0.5`. Isso cria bordas serrilhadas e efeito de imagem duplicada/borrada ao se mover.
4. **Cor homogênea e sem contato com o solo:**
   - Todas recebem o mesmo deslocamento de cor fixo (`vec3(0.86, 1.04, 0.8)`), variando apenas brilho (`0.80..1.15`).
   - Nenhuma árvore projeta sombra nem possui escurecimento (AO) na base/interior da copa, ficando com aspecto de "adesivo colado na grama".
5. **Excesso de densidade e empilhamento em Interlagos:**
   - `tools/cenario/interlagos/trackView.ts` (`MAX = 5200` em capões) somado a `osmScenery.ts` (1 árvore a cada `45 m²` + fileiras a `7 m`) planta **7.052** billboards gigantes (`~14–24 m` de copa) a partir de `10 m` do muro, criando uma parede repetitiva de arbustos esticados.
6. **Peso desproporcional no pacote:**
   - `assets/trees/arvores_cor.png` (`8,57 MB`, `6144×1536`) + `assets/trees/arvores_normal.png` (`11,61 MB`, `6144×1536`) consomem **20,18 MB** para apenas 3 modelos ruins.

---

## 2. Arquitetura Alvo: Sistema Híbrido em 2 Camadas (Padrão LMU / ACC)

Simuladores modernos de corrida não renderizam 7.000 árvores high-poly em 3D nem colocam billboard 2D ao lado da zebra. O padrão é **LOD híbrido em duas camadas** geradas a partir das **mesmas malhas-fonte** (garantindo transição invisível):

```
Distância da câmera:
  0 m ────────────────────── 150 m ─────────────────────────── 2400 m
  |====== Camada 1: 3D Low-Poly ======|
                         |========= Camada 2: Impostor Aprimorado =========|
                         ^ cross-fade / sobreposição suave (~130–160 m)
```

### Camada 1 — Árvores 3D Game-Ready (Perto da pista: `0–160 m`)
- **Geometria (`MultiMeshInstance3D` por espécie + chunk de `250 m`):**
  - Tronco e galhos principais 3D low-poly + **clusters de cartões de folhagem cruzados** (`350–800 triângulos` por árvore).
  - **Normais esféricas/hemisféricas transferidas no Blender** na malha da folhagem: elimina a aparência de "planos cruzados" e dá sombreamento volumoso de copa real.
  - **Vertex Color AO assado no Blender**: interior da copa e base do tronco mais escuros, pontas mais claras.
- **Shader (`shaders/foliage_3d.gdshader`):**
  - **Variação por instância** (matiz, saturação e brilho derivados de `INSTANCE_CUSTOM` / posição) para eliminar sensação de clones.
  - **Translucidez falsa (backlighting / SSS barato):** folhas iluminadas contra o sol ganham brilho verde-dourado quente (assinatura visual do LMU).
  - **Vento sutil no vertex shader** (balanço suave de copa proporcional à altura; desativado em `fast_mode`).
  - **Alpha scissor nítido com mipmap ajustado** (sem halo escuro e sem translucidez cara).
  - **Sombra:** árvores 3D próximas (`0–110 m`) projetam sombra no preset `Extremo` (e opcionalmente no `Médio` após benchmark).

### Camada 2 — Impostores Aprimorados (Média e Longa Distância: `130–2400 m`)
- **Gerados automaticamente no Blender a partir das mesmas 6–8 árvores 3D da Camada 1**, garantindo silhueta, proporção e paleta idênticas na transição.
- **Fim do ghosting no `shaders/impostor.gdshader`:**
  - Substituir o `mix` linear entre vistas distantes (que cria folha dupla) por seleção limpa com transição por **dither/snap suave** (ou card cruzado leve para média distância) + **variação de matiz por instância** igual ao `foliage_3d.gdshader`.
  - Adicionar **gradiente de AO na base** do impostor para "ancorar" a árvore no chão.
- **Economia de espaço:**
  - Novo atlas compacto (`4096×2048` ou `4096×1024` otimizado em WebP/PNG comprimido na importação VRAM), reduzindo `assets/trees/` de **20,18 MB** para **~5–8 MB** no total (incluindo os `.glb` 3D e o atlas de folhas!).

---

## 3. Estratégia de Assets: Blender + Texturas/Modelos CC0

Combinar **Blender** com **recursos CC0 online** entrega o melhor equilíbrio entre realismo, controle de triângulos, peso no APK e segurança de licença:

### 3.1 O que buscar online (CC0 / Domínio Público)
- **Texturas reais de ramos/folhas com Alpha + Normal + Roughness (CC0):**
  - Fontes: **AmbientCG**, **Poly Haven** e **OpenGameArt (CC0)**.
  - Montar **1 único atlas de folhas (`1024×1024`)** contendo 4 a 6 tipos de ramos reais fotografados (folha larga tropical, folha miúda/eucalipto, agulha de pinheiro/cipreste, carvalho, arbusto) + **1 atlas simples de cascas (`512×512`)**.
  - **Vantagem enorme:** todas as 6–8 espécies 3D compartilham o **mesmo material/textura**, minimizando draw calls e uso de VRAM no celular.
- **Modelos 3D CC0 de referência/base (opcional):**
  - Da **Poly Haven** (todos CC0): modelos como `jacaranda_tree` (ótimo para Interlagos), `pine_tree_01`, `shrub_01`, `dry_branches` podem ser importados no Blender, decimados/retopologizados com cartões de folha (`< 800 tris`) e padronizados na mesma escala.

### 3.2 O que fazer no Blender (Script Headless + Blender MCP)
Seguindo o padrão já validado em `tools/gen_hero_props.py`, criar dois scripts reproduzíveis em Python/Blender:
1. **`tools/gen_trees.py`** — gera ou otimiza a biblioteca de **6 a 8 espécies** em `assets/trees/models/*.glb`:
   - Pode usar o add-on nativo do Blender (**Sapling Tree Gen**) ou gerador procedural em `bmesh` + dispersão de clusters de galhos com o atlas de folhas CC0.
   - Aplica automaticamente:
     - Pivô exato na base do tronco (`y = 0`);
     - Escala real em metros (`altura real` já embutida no modelo, eliminando o scale `3.5×`);
     - **Data Transfer de normais esféricas** na copa;
     - **Vertex Color AO** (escuro no miolo/base, claro nas pontas);
     - Contagem estrita de triângulos (`350–800 tris` por espécie).
2. **`tools/bake_tree_impostors.py`** — renderiza automaticamente no Blender (Cycles/EEVEE ortográfico) todas as espécies de `assets/trees/models/*.glb` em 8–12 ângulos (Cor RGBA + Normal Map) e grava:
   - `assets/trees/arvores_cor.png`
   - `assets/trees/arvores_normal.png`
   - `data/track/arvores.json` (metadados: `views`, `species`, `width`, `height`, `biome_weights`).

> **Regra de ouro (AGENTS.md):** O Blender MCP / scripts Python atuam apenas em `assets/trees/` (assets modulares). Nenhum `.glb` de pista (`cenario.glb`) é editado manualmente.

---

## 4. Catálogo de Espécies por Bioma (Fim da Repetição)

Em vez de 3 arbustos tropicais iguais em todas as pistas, a biblioteca terá **7 espécies bem distintas** (altura, silhueta e cor), com pesos configuráveis por pista em `data/tracks.json`:

| ID | Espécie / Silhueta | Altura base | Uso principal |
| :-: | :--- | :---: | :--- |
| `0` | **Copa Larga Frondosa** (Tipuana / Sibipiruna) | 11 m | Interlagos (dominante), Imola |
| `1` | **Árvore Alta Esguia** (Eucalipto) | 16 m | Interlagos (quebra o topo da mata!) |
| `2` | **Conífera / Araucária ou Pinheiro Alto** | 14 m | Interlagos (miolo/Pinheirinho), Laguna Seca |
| `3` | **Árvore Média Irregular** (Ipê / Folha Miúda) | 8,5 m | Interlagos (variação de tom/altura), Imola |
| `4` | **Carvalho Baixo e Largo** (Coast Live Oak) | 7,5 m | Laguna Seca (dominante), Imola |
| `5` | **Cipreste Italiano** (Colunar fino) | 13 m | Imola (marca registrada!), Laguna Seca |
| `6` | **Arbusto / Sub-bosque Denso** | 3,5 m | Todas as pistas (borda de mata e preenchimento de base) |

---

## 5. Auditoria de Densidade e Posicionamento (Especialmente Interlagos)

Trocar o modelo ajuda muito, mas em Interlagos a **distribuição atual** também causa poluição visual:

1. **Reduzir empilhamento de árvores em Interlagos (`tools/cenario/interlagos/trackView.ts` e `osmScenery.ts`):**
   - Aplicar filtro de **distância mínima entre troncos (Poisson-disk / grade espacial)** de `6–9 m` para árvores grandes (e `3–4 m` para arbustos), evitando 5 copas gigantes no mesmo ponto.
   - Rebalancear o teto de árvores procedurais (`MAX` de `5.200` → `~2.800–3.500`, somando ~`4.200–5.000` árvores no total com o OSM — muito mais limpo, natural e leve, mantendo `tv.trees` saudável e a mata fechada onde realmente existe no vídeo do LMU).
2. **Escala realista (`0.80..1.25`):**
   - Como cada espécie já nasce em tamanho real (`3,5 m` a `16 m`), o fator de escala em `arvores_pos.json` passa a ser apenas uma variação natural (`0.80..1.25`), sem distorcer troncos nem criar "arbustos de 20 metros".
3. **Composição natural de borda de mata:**
   - Na faixa mais próxima à pista (`10–30 m` do muro), priorizar **árvores bem espaçadas + arbustos baixos (`ID 6`)** e evitar troncos bloqueando placas de frenagem (`ess_`) ou linhas de visão das curvas (S do Senna, Ferradura, Laranjinha, Pinheirinho, Junção).
4. **Classificação de camada no carregamento (`TrackView.build_trees()`):**
   - Separar automaticamente (ou por flag em `arvores_pos.json`) as árvores próximas à pista (`<= 160 m` da linha central da pista) para receberem **LOD0 3D + LOD1 Impostor**, enquanto árvores de fundo (`> 160 m`, fora do alcance visual próximo) ficam **somente em Impostor** — economizando memória e instâncias 3D onde o jogador nunca chega perto!

---

## 6. Orçamento de Performance por Preset (Mobile-First)

Respeitando rigorosamente a regra de `AGENTS.md` (celular primeiro, 60 FPS no `Leve`, zero peso no `Mínimo`):

| Preset | Camada 1 (3D Low-Poly) | Camada 2 (Impostores) | Sombras nas Árvores | Vento / Translucidez |
| :---: | :--- | :--- | :---: | :---: |
| **`0` — Mínimo** | Desligada (`visible = false`) | Desligada (`visible = false`) | Não | Não (`fast_mode = true`) |
| **`1` — Leve** | Desligada *(ou opcional até `70 m` sem sombra se `--bench` aprovar ≥ 60 FPS)* | Ativa (`0–1200 m`), novo atlas sem ghosting + variação de cor | Não | Não (`fast_mode = true`) |
| **`2` — Médio** | Ativa (`0–150 m`, `visibility_range_end = 150`) | Ativa (`130–2400 m`, `visibility_range_begin = 130`) | Não *(ou apenas faixa `0–80 m` se custo < 0.8 ms)* | Sim (`fast_mode = false`) |
| **`3` — Extremo** | Ativa (`0–220 m`) | Ativa (`200–2400 m`) | **Sim** (árvores 3D até `120 m`) | Sim (`fast_mode = false`) |

### Orçamento de Tamanho em Disco (`assets/trees/`)
| Item | Atual | Meta |
| :--- | :---: | :---: |
| Atlas de Impostores (Cor + Normal) | `20,18 MB` | `~4,5–6,0 MB` |
| Atlas de Folhas + Cascas 3D (CC0) | `0 MB` | `~1,0–1,5 MB` |
| 7 Modelos `.glb` Low-Poly (`assets/trees/models/`) | `0 MB` | `~0,4–0,7 MB` |
| **Total `assets/trees/`** | **`20,18 MB`** | **`~6,0–8,2 MB` (~60% menor!)** |

---

## 7. Roteiro de Execução em Etapas

### Etapa 1 — Curadoria de Texturas CC0 e Definição Visual
- [ ] Baixar/organizar texturas CC0 de ramos/folhas com alpha + casca (AmbientCG / Poly Haven) em `build/trees_src/` (fora do APK) e montar o atlas compartilhado `assets/trees/foliage_atlas.png` (`1024×1024`) + `foliage_normal.png` + `bark_atlas.png` (`512×512`).
- [ ] Definir a paleta de cada pista em `data/tracks.json` (`visual.trees`: pesos das espécies `0..6` e `foliage_tint`).

### Etapa 2 — Pipeline Blender (Modelos 3D + Bake de Impostores)
- [ ] Criar `tools/gen_trees.py` para gerar/otimizar as 7 espécies (`assets/trees/models/tree_0.glb` .. `tree_6.glb`) com `< 800 tris`, normais esféricas e Vertex Color AO.
- [ ] Inspecionar cada `.glb` no Blender (render de conferência em `build/trees_preview/`) para validar silhueta, proporção e densidade de copa antes de levar para a Godot.
- [ ] Criar `tools/bake_tree_impostors.py` para renderizar o novo atlas de impostores (7 linhas × 8 ou 12 vistas) a partir dos mesmos `.glb`, salvando `assets/trees/arvores_cor.png`, `assets/trees/arvores_normal.png` e `data/track/arvores.json`.

### Etapa 3 — Shaders (`foliage_3d.gdshader` e `impostor.gdshader`)
- [ ] Criar `shaders/foliage_3d.gdshader` (normais esféricas, variação de matiz/brilho por instância, translucidez contra o sol, vento suave no vertex, `fast_mode`).
- [ ] Atualizar `shaders/impostor.gdshader`:
  - Ler quantidade de espécies dinamicamente (7 linhas no atlas em vez de 3 hardcoded);
  - Eliminar o ghosting do `mix(uv0, uv1, blend)`;
  - Aplicar a mesma variação de matiz/saturação/brilho da Camada 1 + AO na base;
  - Suportar `foliage_tint` por pista e `fast_mode`.

### Etapa 4 — Integração na Godot (`TrackView` + `SurroundingsView`)
- [ ] Atualizar `scripts/track/track_view.gd` (`build_trees`) para:
  - Carregar as 7 malhas `.glb` de `assets/trees/models/`;
  - Separar instâncias por proximidade da pista (`<= 160 m` → cria blocos `MultiMeshInstance3D` de **Árvores 3D** por espécie/chunk + impostor com `visibility_range_begin`; `> 160 m` → apenas impostor);
  - Manter compatibilidade com `SurroundingsView._is_tree()` e `set_detail(0..3)` para os 4 presets gráficos.
- [ ] Atualizar `scripts/track/surroundings_view.gd` para controlar `visibility_range_begin`/`end` e `cast_shadow` das duas camadas por preset.

### Etapa 5 — Rebalanceamento das Pistas (Interlagos, Laguna Seca, Imola)
- [ ] Atualizar `tools/cenario/interlagos/trackView.ts` e `osmScenery.ts` (espaçamento mínimo Poisson-disk, escala `0.80..1.25`, distribuição das espécies `0..6` de Mata Atlântica/SP).
- [ ] Atualizar distribuição de espécies em Laguna Seca (`tools/cenario/laguna/`) e Imola (`tools/cenario/imola/`).
- [ ] Reexportar `arvores_pos.json` das 3 pistas via `node cenario.mjs`.

### Etapa 6 — Validação Visual, Benchmark e Portão de Regressão
- [ ] Rodar `capture_compare.gd --bench` em **Interlagos**, **Laguna Seca** e **Imola** nos presets `Leve (1)`, `Médio (2)` e `Extremo (3)` comparando:
  - Visual lado a lado contra `INTERLAGOS-IN-LE-MANS-ULTIMATE-LMGT3-Track.mp4`;
  - FPS médio, tempo de quadro e draw calls (garantir regressão zero no `Leve` e impacto mínimo no `Médio`/`Extremo`).
- [ ] Atualizar e rodar todos os testes automatizados em modo headless:
  - `scripts/tests/arredores.gd`
  - `scripts/tests/otimizacao_fase4.gd`
  - `scripts/tests/paridade.gd`
  - `scripts/tests/laguna_seca.gd`
  - `scripts/tests/imola.gd`
- [ ] Conferir tamanho final de `assets/trees/` e garantir que arquivos temporários fiquem em `build/` (ignorado pelo export).

---

## 8. Critérios de Pronto (Definition of Done)

- Interlagos sem aparência de "parede de arbustos 2D clonados": árvores próximas à pista têm volume 3D real, troncos visíveis, variação de espécie/altura/cor e transição suave para a mata distante.
- Zero ghosting/borrão duplo nos impostores em movimento.
- Preset `Mínimo` continua com 0 árvores; preset `Leve` mantém ≥ 60 FPS estáveis; presets `Médio` e `Extremo` rodam fluidos com ganho visual nítido no `capture_compare.gd`.
- Peso de `assets/trees/` menor ou igual ao atual (meta: redução de ~20 MB para < 8,5 MB).
- Todos os testes automatizados passando sem erros nem warnings.
