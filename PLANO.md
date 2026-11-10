# Plano Definitivo: GT3 Time Attack em Godot 4 (Foco Android + Windows + iOS Ready)

Objetivo: ter na **Godot 4** a versão definitiva do **GT3 Time Attack**, trazendo **100% do que existe no jogo web** (`REPOS/gt3-time-attack` + todas as 6 etapas concluídas do `PLANO-visual.md`), mas com uma **arquitetura pensada para rodar liso (60 FPS) e muito bonito no Android**, mantendo gráficos no talo no Desktop (Windows) e pronto para exportar para iOS no futuro sem reescrever código.

Mesmo jeito de trabalhar: fazer tudo por código, testar com prints (`--shot`), vídeos (`--write-movie`) e testes headless, enquanto o Davi dirige e aprova. **Uma etapa por vez, e cada uma termina jogável.**

---

## Por que escolhemos Godot 4 como Engine Definitiva (e o que corrigir do protótipo)

1. **Multiplataforma Real (Android + PC + iOS no mesmo projeto):**
   - Diferente de Kotlin nativo (onde teríamos que programar motor 3D, shaders PBR e física do zero), a Godot 4 exporta APK/AAB para Android, `.exe` para Windows e projeto Xcode para iOS a partir do mesmo código.
2. **Diagnóstico do que deixava o protótipo lento e feio no celular:**
   - **Sombra 8K em 32-bits no `project.godot`:** `directional_shadow/size=8192` e `16_bits=false` estouram a largura de banda de GPUs mobile (Adreno/Mali). No Android, usaremos overrides `.mobile` (`2048`, `16-bits`).
   - **Física a 500 Hz rodando na Engine inteira:** `physics_ticks_per_second=500` com `max_physics_steps_per_frame=24` causa "espiral da morte" na CPU do celular se 1 frame atrasar. **Solução:** rodar o loop da Godot a **60 ou 120 Hz** e fazer **sub-stepping matemático interno** (`dt / N`) dentro do `car.gd` para manter exatos **500 Hz nos pneus/suspensão** com zero perda de paridade e fração do custo de CPU.
   - **Gargalo de ~30 ms na pista exportada (`cenario.glb`):** malhas específicas (índices 68–80 e 140–148, provavelmente transparência/overdraw de alambrado ou vidro) estão comendo ~30 ms de GPU sozinhas.
   - **Modo Celular "chapado" e borrado:** o `_set_quality(false)` atual não ativava sozinho no Android e, quando ativado, só desligava SSR/SSAO e baixava a escala 3D para `0.75` (deixando o carro sem reflexo, flutuando sem sombra de contato e a tela embaçada). **Solução:** pipeline **Mobile Bonito** com `ReflectionProbe`/Cubemap na pintura, sombra de contato escura embaixo do carro, luzes/cores quentes estilo LMU e `MSAA 2x` (muito barato em GPUs mobile Tile-Based) com resolução nítida.

---

## Ponto de partida (feito em 07–08/11/2026)
Protótipo em `REPOS/gt3-godot` (Godot 4.7.2, `Jogar.bat`):
- Interlagos exportada do jogo web (mesma classe `Track`: larguras, zebras, escapes e muros) com relevo SRTM em precisão de 0,1 mm.
- Os 13 carros GT3 com rodas girando/esterçando, pinças paradas, desfoque de roda e pintura com verniz; cena de Garagem funcionando.
- Física portada para GDScript (`scripts/physics/car.gd`, 500 Hz) com paridade ≤ 0,04% contra o web nos 13 carros.
- Céu HDRI, sol com sombra, SSAO/SSIL/SSR, neblina, árvores impostoras e zebras LMU.
- Câmera de perseguição estilo LMU com atraso e transferência de peso. HUD provisório e cronometragem por setores. Piloto automático `RefBot` seguindo a volta real do iRacing.

## Decisões de base
- **O jogo web continua sendo a fonte dos dados de física e traçado.** Pista, relevo, OSM, referências do iRacing e acerto dos carros continuam vindo de `gt3-time-attack/scripts` via `gt3-godot/tools/prep.ts`.
- **Linguagem:** GDScript com sub-stepping otimizado na física (e se ainda precisar de mais folga em celulares antigos, apenas `car.gd` pode ir para C# ou GDExtension, mantendo todo o resto em GDScript).
- **Renderizador Híbrido:** `forward_plus` no PC e `mobile` (Vulkan/OpenGL) no Android/iOS, configurados no mesmo `project.godot` com presets **Leve / Médio / Extremo** pensados para cada plataforma.
- **Back-end:** o mesmo da Vercel (`/api/ranking` e `/api/volta` no repositório `daviml/gt3-tempos`). Web, PC e Android dividem o mesmo ranking.
- **Teste automático:** `--write-movie` do Godot substitui o `film-lap.mjs`, gerando vídeo com o HUD real quadro a quadro. Os prints do `--shot` servem para comparar com o jogo web e com o vídeo de referência do LMU (quadros 26 s, 30 s, 45 s, 52 s e 70 s).

---

## Etapas

### 1. Fundação e dados
- [x] Organizar o projeto: `scenes/`, `scripts/{physics,track,render,ui,net,audio,tests}`, `assets/{cars,sky,textures,trees,sounds}`, `data/{track,cars,reference}`. (07/11)
- [x] `prep.ts` exportando **tudo** (07/11; `npx vite-node prep.ts -- dados` refaz só os JSON):
  - os 13 carros (GLB sem meshopt/webp em `assets/cars/<id>/`);
  - o acerto final de cada carro em `data/cars/<id>.json` (gerado pelo próprio `carParams()` do web, junto com nome, cor, som e rodas do modelo) e a lista do menu em `data/cars.json`;
  - nomes das curvas (14 seções do OSM, em `track.json`), OSM, árvores, 3 referências do iRacing e sons (`data/sounds.json` com o giro de cada gravação).
  - Conferência: `godot --headless --script res://scripts/tests/check_cars.gd` (13 carros com 4 rodas, sons).
- [x] Criar o repositório `daviml/gt3-godot` (privado) e o submodule. (07/11)

### 2. Física com paridade
- [x] `car.gd` lendo o acerto do JSON (`Car.load_car(ground, id)`; `--car=<id>` escolhe o carro no jogo). (07/11)
- [x] Câmbio manual (E/Shift e Q/Ctrl, RB/A e LB/X no controle) e auxílios ligáveis (1 = ABS, 2 = TC, G = câmbio automático), como no web. Teste: `scripts/tests/cambio_superficies.gd`. (07/11)
- [x] Superfícies: asfalto, zebra, escape e grama (iguais ao web), com zebra "pulando" só no Godot (ondulação de 3 mm por listra) e superfície sob cada roda no HUD. (07/11)
- [x] Teste de paridade web × Godot (`tools/paridade.ts` + `scripts/tests/paridade.gd`) nos 13 carros + GT3 base: física no plano idêntica e voltas a ≤ 0,04% com pista exportada em precisão de 0,1 mm. (07/11)
- [x] `RefBot` e `Bot` portados (`scripts/track/`); o piloto automático (P) segue a volta real do iRacing nos carros com referência. Bot de referência do Porsche: 1:36,36 nos dois jogos. (07/11)

### 3. Controles
- [x] Teclado e controle com a mesma curva e suavização da direção do web: `scripts/input/input_reader.gd` (limite 14/v, rampa progressiva no teclado, zona morta 0,08 + curva 1,6 e ~0,2 s até o batente no controle, direção antiga no toque). Back do controle = R. (07/11)
- [x] Vibração do controle (`scripts/input/rumble.gd`): zebra, grama, ABS e batida no motor forte; pneu escorregando e limitador no fraco. (07/11)
- [x] Toque igual ao web (`scripts/input/touch_controls.gd`): ◀ ▶ à esquerda, freio e acelerador à direita, multitoque, área de toque maior que o desenho, câmbio automático, sem inclinar o celular. No PC: `-- --touch`. ☰ e voltar do Android pausam. Teste: `scripts/tests/controles.gd`. (07/11)

### 4. Cronometragem e regras
- [x] Volta lançada, 3 setores e delta ao vivo contra a melhor volta (`scripts/track/lap_timer.gd`, porte do `timing.ts`). Painel provisório no canto superior direito com setores roxo/verde/amarelo e delta. (07/11)
- [x] Volta inválida com as 4 rodas além da zebra por 0,2 s (os escapes contam como fora), como no `timing.ts`. (07/11)
- [x] Recordes locais por nick e carro (`scripts/ui/records.gd`, `user://recordes-interlagos-v3.json`, mesmo formato do web; N = nick, `--nick=`), nome da curva atual no painel. R volta para o grid e zera a volta. Voltas do piloto automático não viram recorde. Teste: `scripts/tests/cronometragem.gd`. (07/11)
  - `RefBot` com malha fechada pela taxa de giro (`yaw_p`): Porsche 1:35,88 e Mustang 1:33,60 válidas seguindo o traçado real.
  - Pendente (Davi decide): a volta do R8 passa 2,3 m além da zebra na Descida do Lago e a linha do jogo tem dobras locais (entrada da Ferradura, S do Senna, Junção).

### 5. Câmera (PLANO-visual etapas 1 e 2)
- [x] Perseguição LMU (`scripts/render/chase_camera.gd`, teste `scripts/tests/camera.gd`): FOV 50°, 6,8 m atrás e 1,85 m de altura, altura e alvo filtrados (0,2 s). (07/11)
- [x] Atraso de ~0,15 s no rumo, no máximo 6° (mostrando levemente a lateral do carro nas curvas). (07/11)
- [x] Avanço de −0,16 m/g na freada (~35 cm a 2,2 g) e afastamento de +0,24 m/g na aceleração (~15–20 cm), com G filtrada (0,25 s) e mola suave (0,45 s, sem tranco na troca de marcha). (07/11)
- [x] FOV abrindo até +3,5° com a velocidade (+0,045°/m/s) e tremida bem leve: 12 mm na zebra e até 6 mm de 250 a 300 km/h. A câmera dá ~1/3 do solavanco vertical do carro. (07/11)
- [x] Sem câmera de cockpit. C (Y no controle) alterna perseguição, capô e longe (11 m, 3,4 m); R reposiciona atrás do carro. (07/11)

### 6. Carros e garagem
- [x] Os 13 GT3 com as correções do `carView.ts` (`scripts/render/car_view.gd` + `tools/car_fix.ts`): metalness por regex de material, Mustang fosco, normais desviradas (M6, Mustang, Ferrari 296 e pinças direitas de Audi e Nissan). (07/11)
- [x] Rodas com suspensão visual, esterço e rotação; pinças paradas (`caliper_XX`); desfoque de roda girando (`blur_XX` com 6 cópias translúcidas no arco de 1/60 s). (07/11)
- [x] Garagem (`scenes/garagem.tscn` como cena inicial): carro no giratório com anel na cor dele, piso reflexivo, softboxes no reflexo da pintura; troca com ◀ ▶ / A D / LB RB, Enter / A / PILOTAR vai para a pista, Esc na pista volta para a garagem. Escolha salva em `user://jogo.cfg`. (07/11)
- [x] Pintura com verniz (`clearcoat = 1`, `roughness = 0.04`, `specular = 0.6`). (07/11)

### 7. Pista base e Desempenho de Geometria (PLANO-visual etapa 3)
- [x] Exportador `tools/cenario.mjs` gerando `assets/track/cenario.glb` e `data/track/arvores_pos.json`, carregados por `scripts/track/track_view.gd` com shaders próprios (`asfalto.gdshader`, `grama.gdshader`, `fachada.gdshader`). (07/11)
- [x] Asfalto estilo LMU: tom marrom-acinzentado escuro (~RGB 120/105/90), textura lida em duas escalas (sem repetição), manchas grandes de 18 e 45 m + variação fina de 7 m, faixa de borracha no traçado **real** (referência do Porsche, rugosidade 1 para não brilhar cinza no sol), decalques de marcas de pneu nas freadas fortes e saídas de curva lenta, linhas brancas de 35 cm mais vivas. (07/11)
- [x] Zebras, escapes por trecho, grid pintado, remendos, muros com placas, barreira azul, alambrado, guard-rail duplo, pneus, pórtico de largada, passarela, placas de frenagem/curvas, arquibancadas, prédios do OSM, lago, pit lane, kartódromo e paddock. (07/11)
- [x] **Correção crítica de FPS da Pista (Prioridade #1 para Android e PC):**
  - Culling de distância (`visibility_range_end = 650.0`) nos detalhes de pista e postes, evitando overdraw massivo a 6000 m.
  - Eliminação de conflitos de profundidade e otimização de render priority com `DEPTH_DRAW_DISABLED` nas faixas e marcas transparentes sobre o asfalto. (10/11)

### 8. Arquitetura de Desempenho Mobile + Luz, Cor e Velocidade (PLANO-visual etapas 1 e 6)
- [x] **Física 500 Hz com Sub-stepping (CPU amigável para Android):**
  - Loop principal da engine ajustado para 60 Hz no [project.godot](file:///D:/Git/Davi/REPOS/gt3-godot/project.godot).
  - Sub-stepping matemático embutido em `car.gd` garantindo 500 Hz cravados na física de pneus e suspensão sem sobrecarregar a CPU. (10/11)
- [x] **Overrides de Projeto `.mobile` no `project.godot`:**
  - `directional_shadow/size.mobile=2048` e `16_bits.mobile=true` (acabando com estouro de VRAM de 8192 no celular).
  - Presets de MSAA e filtragem anisotrópica balanceados por plataforma. (10/11)
- [x] **Luz e Cor estilo LMU (PC e Mobile):**
  - Sol quente e potente (energia 2.8, cor `0xffe6c2`) com splits de sombra otimizados perto do carro.
  - Shader de céu HDRI (`sky.gdshader`) com gradiente azulado no horizonte até ~35° sem tingir o sol. (10/11)
- [x] **Pintura e Sombra Bonitas no Modo Mobile:**
  - Verniz da pintura do carro recalibrado com rugosidade nítida e especular alto para refletir o céu mesmo sem SSR.
  - Sombra de contato escura (blob shadow) sob o chassi para o carro nunca parecer flutuando no Android.
  - Detecção automática de modo Mobile ao iniciar o jogo e escala de resolução nativa (sem embaçar). (10/11)
- [x] **Desfoque de Velocidade e Presets Reais (PLANO-visual etapa 1):**
  - Desfoque radial pós-processado na direção do ponto de fuga (`shaders/speed_blur.gdshader` e `scripts/render/speed_blur.gd`) de 90 a 260 km/h, mascarando a caixa projetada do carro na tela e deixando o centro e o HUD nítidos.
  - Três presets reais configurados em `main.gd`: **Leve** (Mobile 60 FPS, sem SSAO/SSIL/SSR, sombras 2 splits 80 m, MSAA 2x, blur desligado, arredores 220 m), **Médio** (Mobile Top / PC Médio, SSAO suave, sombras 4 splits 130 m, MSAA 2x, blur 0.8, arredores 500 m) e **Extremo** (PC com GPU, SSAO forte, SSIL, SSR 48 passos, sombras 180 m, MSAA 4x, blur 1.0, arredores 900 m). Teste: `scripts/tests/qualidade_blur.gd`. (10/11)

### 9. Arredores no nível LMU (PLANO-visual etapa 5 completa)
Todas as melhorias de cenário da etapa 5 do web portadas e integradas na Godot com orçamento de renderização para PC e Android (`scripts/track/surroundings_view.gd` + `tools/arredores.mjs`). Teste: `scripts/tests/arredores.gd`. (10/11)
- [x] **Prédios e Condomínios:** anel de 1.400 torres residenciais procedurais em condomínios (2–6 iguais) entre ~350 m e ~2,8 km da pista, mais denso a norte/leste (Interlagos/Cidade Dutra/Socorro), desenhados em **uma única chamada de desenho via `MultiMeshInstance3D`** com shader de fachada (`shaders/torre.gdshader`) em coordenadas de mundo (andares de 2,9 m, janelas iluminadas/apagadas, varandas com guarda-corpo escuro, caixas de escada e térreo escuro). (10/11)
- [x] **Horizonte Cilíndrico:** faixa cilíndrica de 3,9 km de raio e 420 m de altura (`shaders/horizonte.gdshader`) com morros da Cantareira/Serra do Mar e camadas de cidade desenhadas em 4096 px com névoa azulada embutida e recorte de céu (`assets/track/horizonte.png`). (10/11)
- [x] **Mata densa em capões:** 7.082 árvores impostoras (`data/track/arvores_pos.json`) agrupadas em 28 blocos de 250 m com culling de frustum e suporte a `visibility_range_end` para os presets. (10/11)
- [x] **Arquibancadas e Torcida LMU:** torcida com mais de 40.000 pessoas em cartões orientados do atlas particionada em tempo de carregamento em 18 blocos de até 120 m (`_split_crowd`), permitindo frustum culling real e limite de distância de visão dinâmico no preset Leve (220 m). (10/11)
- [x] **Faixas de propaganda e detalhes de curva:** faixas no topo dos muros, alambrado detalhado com cabos, placas de frenagem e detalhes de pista herdados do pipeline do web via `cenario.glb` e com LOD de distância (`visibility_range_end = 650 m`). (10/11)

### 10. HUD LMU e Menu Completo (PLANO-visual etapa 4)
Tudo desenhado por código em `scripts/ui/hud.gd` (um Control com `_draw`, escalado pela altura da tela como o web) e
`scripts/ui/pause_menu.gd`. Teste: `scripts/tests/hud.gd`. Prints: `-- --shot=<pasta> --cam=1` (capô) e `--touch`. (10/11)
- [x] **Mostrador redondo estilo LMU (canto inferior direito):** (10/11)
  - Fundo azul-marinho sólido, arco branco grosso de giro (240°, sem números, faixa vermelha fina perto do corte; arco fica vermelho nos últimos 700 rpm e pisca azul na hora de trocar), marcha grande no centro, velocidade e `KM/H`.
  - Arcos internos de 70° para acelerador (verde, à direita) e freio (vermelho, à esquerda).
  - Bloco dos **4 pneus** ao lado, coloridos pelo slip combinado em relação ao pico ($\kappa/\kappa_{\text{pico}}$, $\alpha/\alpha_{\text{pico}}$, filtrado): azul (frio/solto) → verde → amarelo → vermelho (passou do pico), com indicadores `ABS / TC / AUT` abaixo.
- [x] **Painel do Porsche 992:** aparece **apenas na câmera de capô** (nas câmeras de fora fica só o mostrador LMU para a traseira do carro aparecer inteira, igual ao web). 16 luzes de troca, chaves ABS/TC/AUT, tabela, marcha, barra de giro, tempos, setores e pedais. (10/11)
- [x] **Painéis de Tempo e Mapa:** melhores tempos à esquerda (gap para o 1º, linha do seu nick destacada); `Best / Current` + 3 setores coloridos + barra de delta ao vivo + nome da curva + última volta à direita; minimapa da pista com o carro na cor dele; FPS no topo. No celular: painéis menores, mapa ao lado dos tempos e mostrador em cima no centro, longe dos botões de toque. T = telemetria. (10/11)
- [x] **Menu de Pausa e Configurações (`Esc` / Start no controle, `☰` / Voltar no Android):** (10/11)
  - Trocar nick, voltar para a garagem (trocar carro), escolher qualidade gráfica (**Leve / Médio / Extremo**) mostrando o FPS ao vivo, ajustar volume (bus Master), alternar assistências (ABS, TC, Câmbio), instruções e sair. Tudo guardado em `user://jogo.cfg` (`Game.get_setting / set_setting`); F1 alterna o preset sem abrir o menu.
  - Três presets reais integrados com `main.gd` e `SurroundingsView.set_detail()`. (10/11)

### 11. Som
- [ ] Bancos do `engine-sim` por carro (CC-BY-4.0, os mesmos de `public/sounds`): dois loops vizinhos com crossfade pelo giro e `pitch_scale` corrigido; filtro low-pass abafando ao soltar o acelerador; som de turbo e válvula (blow-off).
- [ ] Sons de pneu cantando (proporcional ao slip), grama, escape, vento em alta velocidade e batida na zebra, usando os buses de áudio nativos da Godot.

### 12. Online (Ranking e Fantasmas)
- [ ] **Ranking compartilhado com o web por HTTP (`HTTPRequest`):** consumir `/api/ranking` e enviar voltas válidas para `/api/volta` (mesmo back-end da Vercel, dividindo tabela entre Web, PC e Android).
- [ ] **Fantasmas online em tempo real:**
  - Opção A: compatível com o Trystero do web (sinalização WebSocket nos relays Nostr + WebRTC).
  - Opção B: sala rápida via WebSocket/WebRTC dedicada, se preferirmos simplicidade no mobile.
- [ ] Carros fantasmas translúcidos com etiqueta de nick acima, interpolação de 120 ms, lista "Na pista agora" e aviso quando alguém baixa o tempo na sessão.

### 13. Exportação e Polimento Android (e Preparação iOS)
- [ ] Configurar JDK 17 + Android SDK + templates de exportação da Godot 4.7, keystore de debug/release e preset `Android` no `export_presets.cfg` (orientação paisagem travada, tela cheia imersiva, ícone).
- [ ] Testar o APK diretamente no celular do Davi: validar os 60 FPS no preset **Leve/Médio**, nitidez da imagem, reflexo do carro, resposta dos botões de toque e temperatura do aparelho.
- [ ] Deixar o preset de **iOS** pré-configurado no `export_presets.cfg` caso queira compilar num Mac futuramente.

### 14. Distribuição e Atualização
- [x] **PC (`.exe` em zip):** `export_presets.cfg` (preset "Windows") gerando executável com `godot --headless --path . --export-release "Windows" "build/windows/GT3 Time Attack.exe"`. (08/11)
- [ ] **Android (`.apk` / `.aab`):** script de build de 1 comando gerando o `.apk` pronto para instalar no celular ou enviar para amigos (e `.aab` caso decida colocar na Play Store depois).
- [ ] Aviso no menu inicial quando houver versão nova disponível para download (consulta leve a um JSON online).

---

## Nova Ordem de Execução (Priorizando Desempenho e Visual Mobile + PC)

1. **Etapa 7 (finalizar) + Etapa 8:** Consertar o gargalo de 30 ms da pista (`cenario.glb`), ativar o sub-stepping da física, configurar os presets **Leve (Mobile Bonito)** / **Médio** / **Extremo** e aplicar a luz quente + pintura viva + desfoque de velocidade. *(Aqui o jogo já fica rápido e bonito!)*
2. **Etapa 13 (Build Android Cedo):** Gerar o primeiro APK logo após a Etapa 8 para já testar no celular de verdade e garantir que o desempenho e o visual mobile estão excelentes.
3. **Etapa 9:** Completar os arredores LMU (prédios, horizonte, capões de mata, arquibancada vazada com 45k pessoas, faixas de muro) já respeitando o orçamento de FPS do Android.
4. **Etapa 10:** HUD redondo estilo LMU + Menu completo (necessário para trocar qualidade/carro no celular sem teclado).
5. **Etapa 11 e 12:** Som completo dos motores/pneus e Ranking/Fantasmas online.
6. **Etapa 14:** Pacote final de distribuição (PC + Android).

---

## Verificação em cada etapa
- Prints automáticos (`--shot`) e vídeo (`--write-movie`) nos mesmos pontos da pista que o vídeo do LMU (26, 30, 45, 52 e 70 s), comparando PC (`Extremo`) e Mobile (`Leve`) lado a lado com o web e com o LMU.
- Teste headless de física (`paridade.gd`) garantindo que nenhuma otimização alterou os tempos de volta.
- Medição de tempo de quadro (ms de CPU e GPU) no PC e FPS no celular.
- O Davi dirige e aprova antes de passar para a próxima etapa.

## Regras
- Perguntar antes de commit, push e de criar repositório.
- Não versionar builds (`.exe`, `.apk`), vídeos nem `.godot/`.
- Câmera calma, sem cockpit, uma etapa por vez.
