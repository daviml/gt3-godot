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
- [ ] `car.gd` lendo o acerto do JSON (hoje está fixo no código, só o Porsche).
- [ ] Câmbio manual (borboletas) e auxílios ligáveis (ABS, TC, câmbio automático), como no web.
- [ ] Superfícies: asfalto, zebra, escape, grama e brita, com zebra "pulando" (altura e vibração).
- [ ] Teste de paridade web × Godot com os mesmos números do `vitest`: 0–100 em 3,0 s, máxima de 282 km/h,
      200–0 em 80 m, g lateral de 1,7–2,1 a 72 km/h e o envelope por velocidade (`scripts/envelope.ts`).
      Script headless no Godot que imprime os mesmos valores.
- [ ] `RefBot` (segue a volta real do iRacing) e `Bot` portados. Meta: o bot de referência do Porsche perto de
      1:36,0 nos dois jogos.

### 3. Controles
- [ ] Teclado e controle com a mesma curva e suavização da direção do web (commits 1177412 e 2fd40d5).
- [ ] Vibração do controle (`rumble.ts`): zebra, ABS, batida.
- [ ] Toque no Android igual ao web: ◀ ▶ à esquerda, freio e acelerador à direita, câmbio automático, ☰ para o
      menu, sem inclinar o celular.

### 4. Cronometragem e regras
- [ ] Volta lançada, 3 setores e delta ao vivo contra a melhor volta.
- [ ] Volta inválida ao sair da pista (os escapes contam como fora), como no `timing.ts`.
- [ ] Recordes locais por nick e carro (`user://`) e nome da curva atual no HUD.

### 5. Câmera (PLANO-visual etapas 1 e 2)
- [ ] Perseguição LMU: FOV 50°, 6,8 m atrás e 1,85 m de altura (já no protótipo).
- [ ] Atraso de ~0,15 s no rumo, no máximo 6° (já no protótipo).
- [ ] Avanço de −0,16 m/g na freada e afastamento de +0,24 m/g na aceleração, com G filtrada (0,25 s) e mola
      (0,45 s).
- [ ] FOV abrindo +3,5° com a velocidade e tremida bem leve em zebra e acima de 250 km/h (câmera calma, como o
      Davi pediu).
- [ ] Sem câmera de cockpit (o Davi não quer).

### 6. Carros e garagem
- [ ] Os 13 GT3 com as correções do `carView.ts`: normais invertidas (Mustang, M6), metalness por nome de
      material, Mustang fosco.
- [ ] Rodas com suspensão visual, esterço e rotação; pinças paradas; desfoque de roda girando.
- [ ] Seletor de carro no menu e garagem (o `galeria.html` vira uma cena com o carro girando e luz de estúdio).
- [ ] Pintura com mais reflexo do céu (PLANO-visual 6), usando o clearcoat do Godot.

### 7. Pista (PLANO-visual etapa 3 + tudo o que o web já tem)
- [ ] Asfalto estilo LMU: tom marrom (~RGB 120/105/90), manchas de 18 e 45 m, segunda escala anti-repetição,
      borracha nas trilhas do **traçado real** (referência do Porsche), marcas de pneu nas freadas e saídas,
      linhas brancas de 35 cm.
- [ ] Zebras, escapes por trecho (verde, verde-água, vermelho com listras), grid pintado, remendos e terra
      vermelha (`trackDetails.ts`).
- [ ] Muros com placas por trecho, barreira azul acolchoada, alambrado com ponta inclinada, guard-rail duplo,
      pneus, pórtico de largada, passarela antes do S do Senna.
- [ ] Placas de frenagem na lista fixa do `scenery.ts`, placas com os nomes das curvas.
- [ ] Arquibancadas com torcida, pórticos vermelhos e postos de fiscal (`trackside.ts`).
- [ ] Arredores do OSM: 4.675 prédios, lago, mata, caixa d'água, pit lane com garagens, kartódromo e paddock com
      cobertura em pétalas.

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
