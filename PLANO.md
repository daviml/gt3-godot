# Plano: recriar o GT3 Time Attack em Godot 4 (Windows + Android)

Objetivo: ter no Godot tudo o que o jogo web (`REPOS/gt3-time-attack`) tem hoje, incluindo o plano visual
(`gt3-time-attack/PLANO-visual.md`), com gráfico melhor no PC e um APK que rode bem no celular.
Mesmo jeito de trabalhar: o Claude faz tudo por código e testa sozinho com prints e vídeo, o Davi dirige e dá a
opinião. **Uma etapa por vez, e cada uma termina jogável.**

## Ponto de partida (feito em 07/11/2026)
Protótipo em `REPOS/gt3-godot` (Godot 4.7.2, `Jogar.bat`):
- Interlagos exportada do jogo web (mesma classe `Track`: larguras, zebras, escapes e muros) com relevo SRTM.
- Porsche 992 GT3 R com rodas girando e esterçando, e pintura corrigida.
- Física portada para GDScript (`scripts/car.gd`, 500 Hz): pneu Pacejka, suspensão, aerodinâmica, câmbio
  automático, autoblocante, ABS e TC.
- Céu HDRI, sol com sombra, SSAO/SSIL/SSR, neblina, árvores impostoras e zebras LMU.
- Câmera de perseguição com atraso. HUD simples. Piloto automático simples (P). Modo de prints automático
  (`-- --shot=<pasta>`).

## Decisões de base
- **O jogo web continua sendo a fonte dos dados.** Pista, relevo, OSM, referências do iRacing e acerto dos carros
  continuam sendo gerados pelos scripts de `gt3-time-attack/scripts`. O `gt3-godot/tools/prep.ts` só exporta para
  o Godot. Assim a calibração da física não se duplica.
- **Linguagem:** GDScript. Se a física pesar no celular, só `car.gd` vai para C# (o resto continua em GDScript).
- **Renderizador:** Forward+ no PC e Mobile no Android, no mesmo projeto. Os presets **Leve / Médio / Extremo**
  ficam iguais aos do web.
- **Back-end:** o mesmo da Vercel (`/api/ranking` e `/api/volta` no repositório `daviml/gt3-tempos`). Web e
  Godot dividem o ranking.
- **Teste automático:** `--write-movie` do Godot substitui o `film-lap.mjs`, gerando vídeo com o HUD real
  quadro a quadro. Os prints do `--shot` servem para comparar com o jogo web e com o vídeo do LMU.
- **Repositório:** criar `daviml/gt3-godot` privado (perguntar antes) e registrar como submodule em `REPOS/`.
  Texturas e modelos convertidos entram no git, todos < 95 MB por arquivo. A pasta `.godot/` fica fora.

## Etapas

### 1. Fundação e dados
- [x] Organizar o projeto: `scenes/`, `scripts/{physics,track,render,ui,net,audio,tests}`, `assets/{cars,sky,
      textures,trees,sounds}`, `data/{track,cars,reference}`. (07/11)
- [x] `prep.ts` exportando **tudo** (07/11; `npx vite-node prep.ts -- dados` refaz só os JSON):
  - os 13 carros (GLB sem meshopt/webp em `assets/cars/<id>/`);
  - o acerto final de cada carro em `data/cars/<id>.json` (gerado pelo próprio `carParams()` do web, junto com
    nome, cor, som e rodas do modelo) e a lista do menu em `data/cars.json`;
  - nomes das curvas (14 seções do OSM, em `track.json`), OSM, árvores, 3 referências do iRacing e sons
    (`data/sounds.json` com o giro de cada gravação).
  - Conferência: `godot --headless --script res://scripts/tests/check_cars.gd` (13 carros com 4 rodas, sons).
  - Para a etapa 6: alguns GLB usam UV diferente para normal/metal e cor, que o Godot ignora (aviso no import).
- [x] Criar o repositório `daviml/gt3-godot` (privado) e o submodule. (07/11)

### 2. Física com paridade
- [x] `car.gd` lendo o acerto do JSON (`Car.load_car(ground, id)`; `--car=<id>` escolhe o carro no jogo). (07/11)
- [x] Câmbio manual (E/Shift e Q/Ctrl, RB/A e LB/X no controle) e auxílios ligáveis (1 = ABS, 2 = TC,
      G = câmbio automático), como no web. Teste: `scripts/tests/cambio_superficies.gd`. (07/11)
- [x] Superfícies: asfalto, zebra, escape e grama (iguais ao web; brita fica para quando o web tiver), com zebra
      "pulando" só no Godot (ondulação de 3 mm por listra) e superfície sob cada roda no HUD. (07/11)
- [x] Teste de paridade web × Godot: `tools/paridade.ts` roda a física do web e grava
      `data/tests/paridade-web.json`; `scripts/tests/paridade.gd` roda os mesmos ensaios no Godot e compara
      (0–100, máxima, 200–0, g lateral a 72 e 216 km/h, envelope por velocidade, volta do Bot e do RefBot) nos 13
      carros + GT3 base. Tudo bate: física no plano idêntica e voltas a ≤ 0,04%. (07/11)
  - Achado: o `prep.ts` arredondava a pista em cm, o que deixava degraus de até 5 mm a cada 2 m e fazia o carro
    quicar (Audi 0,7% mais lento). Agora exporta em 0,1 mm.
- [x] `RefBot` e `Bot` portados (`scripts/track/`); o piloto automático (P) segue a volta real do iRacing nos
      carros com referência. Bot de referência do Porsche: 1:36,36 nos dois jogos. (07/11)

### 3. Controles
- [x] Teclado e controle com a mesma curva e suavização da direção do web (commits 1177412 e 2fd40d5):
      `scripts/input/input_reader.gd` (limite 14/v, rampa progressiva no teclado, zona morta 0,08 + curva 1,6 e
      ~0,2 s até o batente no controle, direção antiga no toque). Back do controle = R. (07/11)
- [x] Vibração do controle (`scripts/input/rumble.gd`): zebra, grama, ABS e batida no motor forte; pneu
      escorregando e limitador no fraco. (07/11)
- [x] Toque igual ao web (`scripts/input/touch_controls.gd`): ◀ ▶ à esquerda, freio e acelerador à direita,
      multitoque, área de toque maior que o desenho, câmbio automático, sem inclinar o celular. No PC:
      `-- --touch` (o mouse vira dedo). ☰ e o voltar do Android **pausam** até o menu da etapa 9 existir. (07/11)
  - Teste: `scripts/tests/controles.gd` (36 verificações contra os números do web).
  - Falta conferir no celular de verdade (etapa 13) e no controle do Davi.

### 4. Cronometragem e regras
- [x] Volta lançada, 3 setores e delta ao vivo contra a melhor volta (`scripts/track/lap_timer.gd`, porte do
      `timing.ts`). Painel provisório no canto superior direito com setores roxo/verde/amarelo e delta. (07/11)
- [x] Volta inválida com as 4 rodas além da zebra por 0,2 s (os escapes contam como fora), como no `timing.ts`.
      (07/11)
- [x] Recordes locais por nick e carro (`scripts/ui/records.gd`, `user://recordes-interlagos-v3.json`, mesmo
      formato do web; N = nick, `--nick=`), nome da curva atual no painel. R volta para o grid e zera a volta,
      como no web. Voltas do piloto automático não viram recorde. Teste: `scripts/tests/cronometragem.gd`. (07/11)
  - Achado: o RefBot abria 2–4 m do traçado real em quase toda curva (o pure pursuit ignora o escorregamento
    do pneu) e saía da pista na Descida do Lago, embora a volta real do iRacing seja válida ali. Agora ele tem
    malha fechada pela taxa de giro (`yaw_p`/`yawP`, opcional, igual no `refBot.ts` do web): Porsche 1:35,88 e
    Mustang 1:33,60 **válidas** seguindo o traçado real, iguais nos dois jogos. É o piloto automático (P) do Godot.
  - Pendente (Davi decide): a volta do R8 passa 2,3 m além da zebra na Descida do Lago (GPS desalinhado ou pista
    real mais larga ali) e a linha do jogo tem dobras locais (entrada da Ferradura, S do Senna, Junção) que pedem
    até ~25% mais g lateral que o real nesses 20–40 m.

### 5. Câmera (PLANO-visual etapas 1 e 2)
Porte do `camera.ts` do web em `scripts/render/chase_camera.gd` (mesma mola SmoothDamp e mesmos números).
Teste: `scripts/tests/camera.gd` (reta + volta do RefBot do Porsche com a câmera a 60 Hz). (07/11)
- [x] Perseguição LMU: FOV 50°, 6,8 m atrás e 1,85 m de altura, altura e alvo filtrados (0,2 s).
- [x] Atraso de ~0,15 s no rumo, no máximo 6° (na volta chega a 6° nos S e no Laranjinha).
- [x] Avanço de −0,16 m/g na freada e afastamento de +0,24 m/g na aceleração, com G filtrada (0,25 s) e mola
      (0,45 s). Na volta a distância fica entre 6,55 e 6,96 m.
- [x] FOV abrindo até +3,5° com a velocidade (+0,045°/m/s) e tremida bem leve: 12 mm na zebra e até 6 mm de 250
      a 300 km/h. A câmera dá ~1/3 do solavanco vertical do carro.
- [x] Sem câmera de cockpit. Como no web, C (Y no controle) alterna perseguição, capô e longe (11 m, 3,4 m);
      R reposiciona a câmera atrás do carro.

### 6. Carros e garagem
- [x] Os 13 GT3 com as correções do `carView.ts` (07/11): visual do carro em `scripts/render/car_view.gd`
      (`CarView`), metalness por nome de material (mesmas regex do web), Mustang fosco. As correções pesadas
      ficam na exportação (`tools/car_fix.ts`, rodado pelo `prep.ts`; `-- carros` refaz só os modelos):
      normais invertidas (M6, Mustang, Ferrari 296 e as pinças do lado direito de Audi e Nissan).
- [x] Rodas com suspensão visual, esterço e rotação; pinças paradas; desfoque de roda girando (07/11).
      O `car_fix.ts` separa da roda, por peça conectada, o que não dá a volta no eixo (pinça, suporte) em
      `caliper_XX`, que esterça mas não gira, e copia o miolo (aro e disco) em `blur_XX`: 6 cópias
      translúcidas espalhadas no arco de 1/60 s fazem o desfoque.
- [x] Garagem (`scenes/garagem.tscn`, agora a cena inicial; 07/11): carro no giratório com anel na cor dele,
      piso que reflete, faixas de softbox que só aparecem no reflexo da pintura; ◀ ▶ / A D / LB RB trocam,
      Enter / A / PILOTAR vai para a pista, Esc na pista volta para a garagem. O carro escolhido fica em
      `user://jogo.cfg` (`Game.car_id`). `--car`, `--shot` e `--auto` pulam a garagem.
      Conferência: `-- --vitrine=<pasta>` tira de cada carro um print 3/4 e três da roda (parada, girada,
      girando rápido). Diagnóstico de materiais: `scripts/tests/inspect_cars.gd`.
- [x] Pintura com verniz (clearcoat 1, rugosidade 0,04, especular 0,6) (07/11). Falta o Davi aprovar o
      reflexo na pista; se ficar fraco, dá para subir com uma sonda de reflexo seguindo o carro.

### 7. Pista (PLANO-visual etapa 3 + tudo o que o web já tem)
Feito em 07/11 **exportando o cenário do próprio web**, sem reescrever: `tools/cenario.mjs` abre
`tools/cenario/` no Chromium (Vite + Playwright), roda o `buildTrack()` do web e grava `assets/track/cenario.glb`
(39 MB: malhas e texturas de canvas) e `data/track/arvores_pos.json` (7.082 árvores). Mudou a pista no web →
`node cenario.mjs` (de `tools/`) e reimportar. No Godot, `scripts/track/track_view.gd` carrega o GLB e troca o que o
web faz com shader próprio: `shaders/asfalto.gdshader`, `grama.gdshader` (com a terra vermelha) e
`fachada.gdshader` (janelas dos prédios); concreto com as texturas da Poly Haven; torcida com a figura do atlas
assada no UV. Peças soltas juntadas por material a cada 250 m; árvores em blocos de 250 m e sem sombra (como no web).
- [x] Asfalto estilo LMU: tom marrom, manchas de 18 e 45 m, segunda escala, borracha e marcas de pneu do traçado
      real (referência do Porsche), linhas brancas de 35 cm. (07/11)
- [x] Zebras, escapes por trecho (verde, verde-água, vermelho com listras), grid pintado, remendos e terra
      vermelha. (07/11)
- [x] Muros com placas por trecho, barreira azul, alambrado com ponta inclinada e cabos, guard-rail duplo, pneus,
      pórtico de largada, passarela antes do S do Senna. (07/11)
- [x] Placas de frenagem e com os nomes das curvas. (07/11)
- [x] Arquibancadas com 40 mil pessoas, pórticos vermelhos, postos de fiscal, câmeras de TV e cones. (07/11)
- [x] Arredores do OSM: 4.659 prédios, lago, mata, caixa d'água, pit lane com garagens, kartódromo e paddock. (07/11)
- [ ] **Desempenho:** a pista leva a GPU de 13 para ~43 ms por quadro (GTX 1650 dividida com outros programas,
      1280×720: ~22 fps). Não é draw call nem sombra; a bisseção apontou um punhado de malhas (índices 140–148 e
      68–80 do GLB) que custam ~30 ms sozinhas — achar quais são (provavelmente transparência em tela cheia, ex.
      alambrado ou vidro) antes da etapa 13.
- [ ] Anel de prédios altos e horizonte (`surroundings.ts`) ficam para a etapa 12 (o exportador os descarta).

### 8. Luz, cor e velocidade (PLANO-visual etapas 1 e 6)
- [ ] Desfoque de velocidade (90–260 km/h, carro mascarado) como `CompositorEffect`. O Godot não tem motion
      blur pronto.
- [ ] Sol mais forte e quente, sombra do carro escura e recortada, neblina azulada na distância, grama mais
      seca e alaranjada com manchas, contraste maior.
- [ ] Opcional no Extremo: iluminação global (SDFGI ou VoxelGI) e neblina volumétrica.

### 9. HUD e menu (PLANO-visual etapa 4)
- [ ] Painel LMU: melhores tempos à esquerda; Best/Current + setores + delta à direita; mapa.
- [ ] Conta-giros circular com luzes de troca e painel do Porsche 992 (só no Porsche), escalados no PC e no
      celular como hoje.
- [ ] Mostrador redondo azul-marinho do LMU (arcos de acelerador e freio, 4 pneus coloridos pelo slip), como no
      `hud.ts` do web. Resolvido no web: o painel do Porsche só aparece na câmera de capô; na perseguição vale o
      mostrador LMU.
- [ ] Menu (Esc ou ☰): nick, carro, gráficos com fps e sugestão de preset, volume, instruções.

### 10. Som
- [ ] Bancos do engine-sim por carro (CC-BY-4.0, os mesmos de `public/sounds`): dois loops vizinhos com crossfade
      pelo giro e tom corrigido; filtro abafando ao soltar o acelerador; turbo e válvula.
- [ ] Pneu cantando, grama, brita, vento e zebra, usando os buses e efeitos de áudio do Godot.

### 11. Online
- [ ] Ranking compartilhado com o web por HTTP (`/api/ranking`, `/api/volta`). Fácil: dá para fazer cedo.
- [ ] Fantasmas: o web usa Trystero (WebRTC em malha, sinalização pelos relays do Nostr), que não existe no
      Godot. Opções (o Davi decide):
  - **(a)** implementar no Godot o mesmo protocolo de sinalização do Trystero (WebSocket nos relays Nostr +
        extensão webrtc-native), para que web e Godot se vejam na mesma sala. Mais trabalho, mas ninguém fica
        de fora;
  - **(b)** sala só entre jogadores do Godot, com sinalização simples. Mais rápido, mas separa quem joga no
        navegador.
- [ ] Fantasmas translúcidos com nick, 120 ms de atraso interpolado, lista "Na pista agora" e aviso de volta dos
      amigos.

### 12. Arredores no nível LMU (PLANO-visual etapa 5, portado do web e melhorado no Godot)
- [ ] Prédios residenciais altos (15–25 andares) com fachada texturizada (janelas, varandas, reboco) e anel de
      prédios no horizonte.
- [ ] Horizonte com cidade e morros distantes e neblina azulada.
- [ ] Mata densa e alta, principalmente no miolo da pista e atrás do Laranjinha/Pinheirinho. No PC, árvores 3D de
      verdade com LOD (o Godot aguenta mais que os impostores do web).
- [ ] Terreno com grama seca variada e terra só em trilhas.
- [ ] Arquibancada da reta com estrutura aparente e público em cartões (sprites) variados.
- [ ] Faixas de propaganda contínuas e saturadas no topo dos muros (marcas fictícias), cones, câmeras de TV,
      postes e cabos do alambrado.

### 13. Android
- [ ] Instalar JDK 17 + Android SDK, criar keystore de debug e preset de exportação (paisagem, tela cheia).
- [ ] Preset Leve: renderizador Mobile, luz da pista pré-calculada (`LightmapGI` com o sol fixo), texturas
      ASTC, sombra só do carro, resolução dinâmica, 60 fps travado.
- [ ] Testar no celular do Davi e comparar com o webapp (fps, visual, direção).

### 14. Distribuição
- [ ] PC: `.exe` em zip (GitHub Releases do repositório privado, ou link direto para os amigos).
- [ ] Android: APK fora da loja. A Play Store custa US$ 25 uma vez, se valer a pena depois.
- [ ] Aviso no jogo quando houver versão nova (consulta simples a um JSON).

## Ordem sugerida
1 → 2 → 3 → 4 dão um jogo completo de dirigir.
5 → 6 → 7 → 8 deixam ele no visual do web ou melhor.
9 → 10 → 11 trazem o HUD, o som e o online.
13 (Android) logo depois do 8, para descobrir cedo se o celular aguenta.
12 e 14 por último.

## Coordenação com o jogo web
- O `PLANO-visual.md` do web está **todo feito** (etapas 1 a 6, a última no commit `6cbf6ac` de 07/11): desfoque
  de velocidade, câmera, asfalto LMU, mostrador LMU, prédios/horizonte/mata/arquibancadas/placas e luz e cor.
  **Decidido (07/11):** tudo isso é portado do web para o Godot (`speedBlur.ts`, `camera.ts`, `trackView.ts`,
  `hud.ts`, `surroundings.ts`, `trackside.ts`, `osmScenery.ts`, `scene.ts`), não refeito do zero. O Godot pode
  ir além do web onde ele aguenta mais (árvores 3D com LOD, GI, sombras melhores).
- Mudanças de pista ou de física continuam no web (scripts e dados) e chegam ao Godot rodando `prep.ts` de
  novo.

## Verificação em cada etapa
- Prints automáticos (`--shot`) e vídeo (`--write-movie`) nos mesmos pontos da pista que o vídeo do LMU
  (26, 45, 52 e 70 s), lado a lado com o web.
- Teste headless de física (paridade com o web) e fps no PC (RTX 4060) e no celular.
- O Davi dirige e aprova antes de passar para a próxima etapa.

## Regras
- Perguntar antes de commit, push e de criar repositório.
- Não versionar builds (`.exe`, `.apk`), vídeos nem `.godot/`.
- Câmera calma, sem cockpit, uma etapa por vez.
