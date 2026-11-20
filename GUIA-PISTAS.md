# Guia: como fazer uma pista fiel (nível LMU / iRacing)

LMU e iRacing escaneiam as pistas a laser, com precisão de milímetros. A gente não tem o scan, mas dá pra chegar
perto juntando dados públicos e **conferindo tudo contra a telemetria do iRacing e o vídeo do LMU**. Este guia é o
processo que deu certo em Laguna Seca (13/11/2026), com o que ainda dá pra melhorar. Regra geral: **medir em vez de
desenhar, e validar cada etapa com um número antes de seguir**.

Exemplo completo: `tools/tracks/laguna-seca/` (scripts + `LEIA-ME.md`) e `PLANO-LAGUNA-SECA.md`.

---

## 0. Antes de começar: o que juntar

| Item | Para quê | Como |
|---|---|---|
| 2–4 voltas do Garage 61 (CSV), carros diferentes | traçado, linha de chegada, sentido, velocidades, g lateral/vertical | exportar do Garage 61 para `garage61/` |
| Vídeo do LMU com uma volta onboard **e** uma em 3ª pessoa | referência visual quadro a quadro | `python -m yt_dlp` → raiz do jogo (não versionar) |
| Relevo de alta resolução (LiDAR) | altitude, camber, morros em volta | ver tabela de fontes abaixo |
| OpenStreetMap | linha central, pit lane, muros, brita, prédios, arquibancadas, nomes das curvas | API 0.6 (`/api/0.6/map?bbox=`) |
| Foto de satélite ~0,25 m | largura real, zebras, brita, escapes, posições de objetos | Esri World Imagery (`export`) |
| Mapa oficial da pista | numeração das curvas, comprimento oficial, desnível | site da pista / FIA |

### Fontes de LiDAR por país

O relevo é o que mais pesa na física. Sem LiDAR, cair para SRTM/Copernicus 30 m (bem pior: perde camber e
compressões).

| País | Fonte | Resolução |
|---|---|---|
| EUA | USGS 3DEP (ImageServer `exportImage`) | 1 m |
| Brasil (São Paulo capital) | GeoSampa — levantamento a laser da Prefeitura (**confirmar cobertura de Interlagos**) | ~0,5–1 m |
| França | IGN LiDAR HD / RGE ALTI | 0,5–1 m |
| Espanha | PNOA LiDAR (CNIG) | ~0,5–2 m |
| Reino Unido | Environment Agency LiDAR Composite | 1 m |
| Holanda | AHN | 0,5 m |
| Bélgica (Spa) | Wallonie LiDAR (Géoportail) | 1 m |
| Alemanha | serviços de cada estado (ex.: Renânia-Palatinado para Nürburgring) | 1 m |
| Japão | GSI (Geospatial Information Authority) | 5 m |
| Austrália | ELVIS | 1–5 m |

---

## 1. Coleta (script `download.py` por pista)

- Pedir tudo em **blocos pequenos na projeção nativa do serviço (EPSG:3857)**, com bbox e tamanho exatos.
  - Pedido grande dá 502.
  - Pedido em graus (EPSG:4326) **desalinha os blocos** (~17 m de degrau entre faixas): conferir as emendas.
- Recorte do relevo: pista + **~1 km** em volta (os morros aparecem no horizonte).
- Satélite: só a área da pista, a 0,25 m.
- Brutos em `build/<pista>/` (não versionados); só os JSON processados vão para o git.

**Conferência:** emendas entre blocos com salto igual ao dos vizinhos; zero buracos no relevo.

---

## 2. Traçado (linha central, larguras)

1. **Linha central do OSM** (`highway=raceway`, sem pit lane), encadeada numa volta fechada.
   - Conferir o comprimento contra o oficial (Laguna: OSM 3.605 m × 3.602 m).
2. **Sentido e linha de chegada** pelas voltas do Garage 61 (primeira amostra da volta = s 0).
3. **Suavizar o polígono do OSM** (σ ≈ 5–6 m). Os vértices espaçados viram "cotovelos": a T6 de Laguna saía
   com raio de 31 m onde o iRacing passa a 176 km/h.
4. **Bordas do asfalto na foto de satélite**, perpendicular à pista a cada 1 m:
   - asfalto = cinza quase neutro (brilho ~105–160);
   - fora = mais claro ou mais amarelado (faixa branca, zebra, brita, terra);
   - mascarar a pit lane (distância à linha dela no OSM);
   - percentil baixo numa janela de ±20 m (escapes asfaltados e sombras só "alargam").
5. **Recentralizar** pelo meio das bordas medidas, algumas iterações.
6. Fechar a volta com **número de pontos múltiplo do passo de saída**: o último trecho curto vira degrau na emenda.

**Conferências:**
- as voltas do iRacing cabem entre as bordas (+ zebra) em ≥ 99% do tempo;
- o raio das curvas permite as velocidades do iRacing.

---

## 3. Relevo e camber

1. Altitude = LiDAR (terreno nu) sob o centro, com filtro de mediana (pontes) + suavização leve (σ ≈ 4 m).
   Não suavizar demais: perde a crista da T1 e a queda do Corkscrew.
2. **Camber** = diferença de altitude a ±3,5 m do centro (sempre sobre o asfalto; nas bordas o LiDAR pega
   muro/valeta). Suavizar ao longo da pista (σ ≈ 10 m): ruído de camber na reta torce o carro a 200 km/h.
3. Gravar `bank` no `track.json`. O Godot gira a lateral em torno da tangente (`track.gd`) e o cenário faz a
   mesma conta (`tools/tracks/bank.ts`). Pistas sem `bank` continuam como antes.

**Conferências com a telemetria** (as mais valiosas):
- **Aceleração vertical do iRacing (`VertAccel`) × v²·curvatura vertical da pista**: tem que bater em ±0,1–0,2 g
  na volta toda. Onde não bate, falta crista ou compressão.
- **Raio pelo GPS × v²/`LatAccel` × v/`YawRate`**: os três concordando mostram que a geometria está certa. Onde o
  carro faz mais g do que o raio explica, falta camber ou compressão (Laguna T6: 3,2 g).
- Sinal do camber: o lado de fora da curva é sempre o mais alto. Se não for, desconfiar da medida.

---

## 4. Telemetria de referência e física

1. Converter cada volta do Garage 61 (`tools/referencia.ts`): ajuste do GPS (rotação + escala + translação; em
   Laguna saiu quase nulo) e reamostragem a cada 2 m.
2. Registrar em `data/tracks.json` → `refs` (carro do jogo → referência).
3. Teste da pista (modelo: `scripts/tests/laguna_seca.gd`):
   - comprimento ≤ 0,5% do oficial, desnível, maior descida no lugar certo;
   - piloto automático (RefBot) dá voltas **válidas**, a ≤ 3% do tempo real;
   - **velocidade mínima por curva** a ≤ 10 km/h do iRacing;
   - carro não decola (≤ 2 rodas no ar por pouco tempo).
4. Diferenças que sobrarem e forem de física do carro (não de pista) ficam como "pendente" no teste, com a
   explicação. Não esconder.

---

## 5. Cenário

Hoje o cenário sai do código do jogo web, com cópias adaptadas por pista em `tools/cenario/<pista>/` e
`--track=<id>` nas ferramentas. **Para a próxima pista: trocar as posições escritas à mão por um arquivo de
configuração por pista** (pontes, placas, tendas, cores), sem copiar código.

O que fazer, do mais ao menos importante para "parecer a pista":

| Elemento | Fonte | Observação |
|---|---|---|
| Zebras (cor, largura, onde começam/terminam) | satélite (detectar vermelho/branco) + vídeo | hoje vêm da curvatura; medir no satélite é melhor |
| Brita × grama × escape asfaltado | satélite (classificação por cor) + OSM `natural=sand` | Laguna: `build_surfaces.py` |
| Muros, alambrado, pneus | OSM `barrier=wall` + vídeo | |
| Placas de freada | telemetria (onde o iRacing freia) + vídeo | aparecer no Mínimo |
| Pontes, pórticos, arcos | sombras no satélite + vídeo (s exato pelo velocímetro do vídeo × telemetria) | |
| Marcas de pneu e borracha | linha da referência + zonas de freada/aceleração da telemetria | muitas, sobrepostas, tons variados (o LMU é bem "sujo") |
| Asfalto (cor, remendos, emendas) | satélite + vídeo | cor por pista em `data/tracks.json` → `visual` |
| Boxes, paddock, tendas, torre, arquibancadas | OSM + vídeo | só do Leve para cima |
| Árvores | **LiDAR de superfície − terreno = altura da copa** (posição e tamanho reais) | evitar fileiras iguais |
| Horizonte | relevo LiDAR em volta + cor do bioma | |
| Sol | data/hora do vídeo do LMU | `sun_u`/`sun_elev` |

---

## 6. Validação visual com o LMU

1. Tirar quadros do vídeo (onboard e 3ª pessoa) a cada 2–3 s; anotar o **s de cada quadro** pela velocidade do
   velocímetro do vídeo × a referência.
2. `scripts/tests/capture_compare.gd -- --track=<id>` gera os mesmos pontos no Godot; montar lado a lado em
   `build/compare/<pista>/`.
3. Cuidados para a comparação ser justa:
   - carro **alinhado ao chão** (em rampa forte, carro nivelado parece enterrado);
   - de preferência **em movimento** (o LMU tem desfoque de velocidade);
   - mesma câmera (perseguição/capô) e FOV parecido.
4. Iterar nos pontos mais gritantes; repetir a folha no **Mínimo** e no **Leve**.

---

## 7. Desempenho e entrega

- Medir ms por quadro e draw calls no Mínimo/Leve/Extremo e comparar com Interlagos: não pode ser pior no Mínimo.
- Juntar malhas por região (250 m), detalhes só do Leve para cima, essenciais com `ess_` no nome.
- Rodar a suíte inteira: as outras pistas não podem mudar (comparar com a linha de base antes de começar).
- Texturas extraídas do GLB no `.gitignore`; brutos fora do git.

---

## 8. Indo além (para chegar mais perto do scan)

Ainda não feito, em ordem de ganho:

1. **Nuvem de pontos LiDAR** (não só a grade de 1 m): ondulações e lombadas de 10–20 cm no asfalto, perfil
   real das zebras, abaulamento.
2. **Altura da copa pelo LiDAR** (superfície − terreno) para posicionar cada árvore e prédio com a altura real.
3. **Zebras medidas no satélite** (posição, largura e tipo) em vez de deduzidas da curvatura; zebras "salsicha"
   na física.
4. **Camber medido em várias linhas** (não só ±3,5 m): pistas com inclinação que muda ao longo da largura.
5. **Ajuste fino de física por pista** com várias voltas e vários carros (ex.: T6 de Laguna).
6. **Marcas de pneu a partir de várias voltas** (onde cada carro freia/patina).
7. **Fotos de solo** (Street View, fotos de corrida) para placas, cores de muro e detalhes do paddock.
8. **Biblioteca de cenário** (fazer uma vez, usar em todas as pistas): hoje tudo é gerado por código (caixas,
   cilindros, texturas de canvas) e as árvores vêm de poucos modelos, então o cenário fica genérico e repetido.
   - Juntar ~30–50 modelos de licença livre (Poly Haven, Kenney, Quaternius, Sketchfab CC0/CC-BY com crédito):
     árvores por bioma (carvalho californiano, pinheiro, eucalipto, mata tropical...), tendas, caminhões,
     guindastes, cones, postes, banheiros químicos, motorhomes, cercas, pórticos.
   - Conferir a licença de cada um e registrar nos créditos; gerar impostores/LOD pelo mesmo processo das árvores
     de hoje (árvore vira imagem: 50 espécies custam quase o mesmo que 5 no celular).
   - Placas e banners com as **marcas reais que aparecem no vídeo de referência** (mesma marca, cor, formato e
     posição), o mais próximo possível. Decisão do Davi em 20/11/2026: o jogo não será comercializado.
9. **Detalhes iguais ao vídeo de referência do Davi**: tudo o que aparece no vídeo do LMU que ele fornecer vira
   item a reproduzir, não só a pista em si:
   - marcos de cada pista modelados sob medida a partir dos quadros do vídeo (arcos, passarelas, torre de
     controle, prédios dos boxes, bandeiras, letreiros com o formato e as cores certos);
   - mesmo tipo e posição de placas, barreiras, alambrados, cores de muro e de zebra, tendas e estruturas do paddock;
   - lista de checagem por pista: cada quadro do vídeo × print do Godot no mesmo ponto, item por item, até não
     sobrar diferença gritante.
10. **Refazer Interlagos com este processo** (LiDAR do GeoSampa se cobrir; larguras pelo satélite; camber;
   validação × iRacing). Muda a pista principal: nova versão dos recordes e testes antes de trocar.

---

## 9. Lições práticas de Interlagos (detalhes quadro a quadro, armadilhas GLB/Godot e melhorias sugeridas)

Na revisão visual de Interlagos (`v1`–`v11`) surgiram erros recorrentes que não apareciam nas métricas numéricas e que precisam guiar qualquer pista nova ou refeita daqui para frente.

### 9.1. Protocolo de inspeção quadro a quadro (nunca "arrumar no atacado")

1. **Alinhar primeiro a câmera ao traçado real do vídeo**: em `scripts/tests/capture_compare.gd`, cada ponto deve ter `[nome, s, d_lateral, yaw_deg]` (em metros laterais e ângulo na pista), não `d = 0` reto no centro. Sem estar na mesma tangência/borda e ângulo de curva do vídeo de referência, a distância aparente das barreiras, zebras e prédios engana.
2. **Inspecionar os números crus do `track.json` antes de editar**: imprimir `wl`, `wr`, `kerbL`, `kerbR`, `runL`, `runR`, `wallL` e `wallR` a cada 10–20 m no trecho analisado. Em Interlagos, `wallL`/`wallR` estavam fixos em `~22,5 m` na maior parte da volta, criando gramados irreais de `15 m` e afastando muros/alambrados que na pista real ficam colados ao escape.
3. **Analisar uma foto por vez, da linha branca para fora, nos dois lados**:
   - **Lado esquerdo** e **lado direito**: listar exatamente a sequência visível no vídeo: `zebra` → `faixas de grama / escape pintado (e sua ordem: ex. grama + vermelho + verde na Reta Oposta)` → `distância e tipo da barreira` → `alambrado` → `tendas, torres, prédios e árvores de fundo`.

### 9.2. Checklist de detalhes visuais que não podem passar batido

- **Barreiras por trecho (nunca genéricas)**: distinguir muro de concreto (`wall`), guard-rail duplo/triplo (`rail`), barreira acolchoada simples (`tecpro` / `rolex_pad`), e **barreira acolchoada dupla empilhada colada na zebra** (como na esquerda da Descida do Lago). Conferir trecho a trecho onde há alambrado alto (`fence: true`) e onde o muro é baixo.
- **Entrada e saída dos boxes completas**: modelar o asfalto do pit-lane até a junção/divergência real com a pista, o guard-rail ou mureta divisória (ex.: saída dos boxes contornando a Curva do Sol) e o atenuador laranja/preto na ponta da mureta (ex.: entrada dos boxes na Subida dos Boxes).
- **Costas e fundações de prédios e arquibancadas**: tudo o que fica na reta principal é visto **por trás** a partir do miolo da pista (Ferradura, Laranjinha, Pinheirinho).
  - Nunca deixar parede traseira ou ponta de prédio com cor sólida clara (`#e1e2e3` sob `sun.light_energy` vira um paredão branco chapado). Usar textura arquitetônica escura (concreto cinza-escuro, faixas de vidro fumê, brises e pilares).
  - Descer todas as bases de arquibancadas, pilares e prédios até `-10 m` (ou ao `heightAt(x, z) - 3`), garantindo que nenhuma estrutura flutue sobre barrancos.
- **Eixos locais de objetos (`makeBasis(s.r, up, -s.t)`)**: `+X` segue `+s.r` (atravessando para a direita/dentro da pista) e `+Z` segue `-s.t` (ao longo da pista). Sempre conferir qual dimensão da `BoxGeometry` está paralela à pista e garantir que objetos laterais (telões, casinhas de apoio, tendas) fiquem com folga externa ao muro (`-(wl + offset)`), sem jamais invadir o asfalto.
- **Limpeza seletiva de árvores e placas**: remover árvores do OSM e do `buildScenery` próximas à borda nos trechos abertos do vídeo (para não esconder morros de grama, tendas, caixa d'água e marcos reais) e não gerar placas azuis genéricas (`buildSectionSigns` / placas de setor) onde a pista de referência não possui placa.

### 9.3. Armadilhas técnicas do pipeline Three.js → GLB → Godot 4

1. **Sempre definir `wrapS = wrapT = THREE.RepeatWrapping`**: o `StandardMaterial3D` do Godot 4 não tem modo de repetição independente por eixo; o importador glTF só liga `texture_repeat = true` quando **ambos** `wrapS` e `wrapT` são `RepeatWrapping`. Se `wrapT` ficar no padrão `ClampToEdgeWrapping`, qualquer malha com `uv.x > 1.0` (muros, barreiras `ROLEX`/`GOODYEAR`/`MOTUL`/`DHL`/`AVIS`, pilares dos boxes) é grampeada na última coluna de pixels (`CLAMP_TO_EDGE`), virando faixas lisas sem texto nem divisórias.
2. **Não depender de `tex.repeat.set()` (`KHR_texture_transform`)**: a otimização do GLB (`gltf-transform`) descarta `KHR_texture_transform`, esticando um único logo na malha inteira (como aconteceu na passarela `ROLEX`). Em vez disso:
   - escalar a repetição diretamente nos `UV`s da geometria (`strip` / `wallBand`), **ou**
   - desenhar todas as repetições direto no canvas (ex.: os 6 logos `ROLEX` da passarela num `2048×192`).
3. **Shaders `onBeforeCompile` não vão para o GLB**: só funcionam no Godot se forem substituídos por um `.gdshader` equivalente mapeado por nome em `cenario.ts` e `track_view.gd` (como `asfalto`, `grama`, `fachada`). Para prédios do OSM, boxes e barreiras, exportar malhas com `CanvasTexture` + `vertexColors` padrão do glTF.
4. **Orientação das normais em faixas verticais**: mesmo com `DoubleSide`, conferir a ordem dos índices da `BufferGeometry` para que a normal aponte para a pista e para o sol — face com normal invertida fica escura na sombra própria.
5. **Reimport obrigatório no Godot**: sempre executar `godot --headless --path . --import` depois de `node cenario.mjs` antes de rodar `capture_compare.gd`; caso contrário o Godot renderiza o `.glb` antigo do cache `.godot/imported/`.

### 9.4. Sugestões de formas melhores para fazer e refazer pistas

1. **Perfil visual declarativo por fatia (`visual_profile.json`)**: separar a física (`track.json`) de um arquivo declarativo de fatias `[s0, s1]` descrevendo para cada lado a sequência de faixas (`kerb`, `grass`, `green`, `red`, `asphalt`, `gravel`), a distância e o tipo de barreira (`wall`, `rail`, `tecpro`, `rolex_pad`, `tecpro2`), o esquema de banner/cor e `fence`, eliminando dezenas de `if/else` imperativos no `trackView.ts`.
2. **Preview rápido em ~2 s direto no Chromium (`cenario.mjs --preview`)**: antes de rodar o ciclo pesado de exportar ~25 MB de `.glb` + reimportar no Godot + capturar (~1–2 min por tentativa), fotografar os mesmos `CHECKPOINTS` `[s, d, yaw]` direto na cena Three.js aberta pelo Vite no `cenario.mjs` e montar o lado a lado com o LMU em poucos segundos para iterar posições e texturas; deixar o ciclo completo no Godot para a validação final de shader/iluminação.
3. **Gabarito métrico projetado nos quadros**: gerar um overlay opcional no `capture_compare.gd` com linhas guia de metragem (`s` a cada `10 m` e `d` a cada `2 m`) para medir exatamente onde começa/termina cada zebra, escape e muro sem tentativa e erro.
