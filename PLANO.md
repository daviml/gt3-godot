# Plano Definitivo: GT3 Time Attack em Godot 4 (Foco Android + Windows + iOS Ready)

Objetivo: ter na **Godot 4** a versão definitiva do **GT3 Time Attack**, trazendo **100% das evoluções do jogo web** (`REPOS/gt3-time-attack`), incluindo todas as melhorias recentes (Modo Arcade, 4 esquemas de controles mobile, física calibrada com dados do iRacing, correções de projeção de pista e ajustes para telas ultrawide), com uma **arquitetura de alto desempenho focada em rodar a 60 FPS cravados no APK Android**, mantendo gráficos no talo no Desktop (Windows) e pronto para exportar para iOS no futuro.

Princípio de trabalho: tudo via código, testável com prints (`--shot`), vídeos (`--write-movie`), baterias headless de paridade (`paridade.gd`, `controles.gd`), e testes reais com APK no celular do Davi. **Uma etapa por vez, com cada uma terminando 100% jogável.**

---

## O que falta subir do Web para o Godot (Inventário das Novidades Recentes)

Ao analisar os commits mais recentes do repositório web (`gt3-time-attack`), identificamos as seguintes funcionalidades cruciais que foram implementadas no web e agora entram no roteiro do Godot:

1. **Modo Arcade (`GameMode`):**
   - Aderência dos pneus multiplicada por **1,8x** (`grip_scale = 1.8` vs `1.0` no Simulador).
   - **Compensação Anti-Capotamento:** em curvas de alta com 1.8x de grip, a aceleração lateral ultrapassa 3,0 g. O braço vertical do CG até o Roll Center (~30 cm) gerava torque excessivo e capotava o carro na largura da bitola (~80 cm). A fórmula `_p += up * (dh * (1 - 1 / (grip_scale * grip_scale)))` neutraliza esse efeito no Arcade sem alterar a física do Simulador.
   - **Ajuste de esterço no Arcade:** limite de esterço dinâmico (`steer_limit`) escalado por `grip_scale`, permitindo curvas mais agressivas.
   - **Recordes e Rankings separados:** chaves locais distintas (`recordes-interlagos-v3` vs `recordes-interlagos-arcade`) e tabelas online separadas.

2. **Novos Esquemas de Controles de Toque para Celular (4 Modos):**
   - **Padrão:** analógico horizontal suave à esquerda (zona morta 8%, curva exponencial 1.6) + pedais proporcionais de ACEL. e FREIO à direita (a altura do dedo no botão determina a porcentagem de 0 a 100%).
   - **Fly-by-wire:** analógico horizontal à esquerda + barra vertical única multifunção à direita (do centro para cima acelera até 100%, do centro para baixo freia até 100%, zona morta de 6% no meio e vibração háptica no cruzamento).
   - **Inclinar (Giroscópio / Acelerômetro):** virar o celular como um volante físico usando o acelerômetro (`Input.get_accelerometer()`), com filtro de 0,08 s contra tremores da mão, 2° de zona morta, batente a ±30°, auto-centralização/recenter ao iniciar ou tocar no botão de recentralizar, e pedais na tela.
   - **Legacy:** botões digitais direcionais ◀ ▶ à esquerda e pedais digitais liga/desliga à direita com rampa progressiva.
   - **Melhorias de manuseio no toque:** Pointer capture aperfeiçoado (deslizar entre os pedais não solta o comando) e **Ré Automática no Toque (`brake_to_reverse`)**: parado (<0,5 m/s), segurar o freio por 0,4 s engata a ré; em ré, o freio acelera para trás e o acelerador freia; acelerar parado volta para a 1ª marcha.

3. **Física Refinada e Dados Atualizados do iRacing:**
   - **Mercedes-AMG GT3 2020:** nova calibração com 4 voltas reais de telemetria do iRacing (Garage 61, 1:29.775 etc.) com curva de torque de 8 pontos, relações de marcha, diferencial e aero balanceados (`data/cars/mercedes-amg-gt3.json`, `data/reference/interlagos-amg.json`).
   - **Calibração refinada dos demais GT3:** Porsche 992 GT3 R, Audi R8 LMS EVO II e Ford Mustang GT3 sincronizados com telemetrias atualizadas.
   - **Correção na Projeção 2D da Pista (`track.gd`):** remoção do termo `4 * dy²` na busca global do `nearest()` (evitando distorções em subidas/descidas como o S do Senna e Junção) e cálculo do produto escalar puramente horizontal 2D no `locate()`.
   - **RefBot com malha fechada de giro (Yaw Rate):** controle com ganhos `yaw_p`, `yaw_i`, `line_gain` e `hold_line` sincronizados com o web.

4. **Estratégia de Otimização Extrema do APK Android para Alto FPS (60+ FPS Estáveis):**
   - **Novo Preset Gráfico "Mínimo (Celular Fraco)":** além de Leve, Médio e Extremo, adicionar o preset Mínimo (sem sombras direcionais, sem reflexos/pós-processamento, cenário simplificado, 70-75% de resolução interna com upscaling nítido).
   - **FSR 1.0 (AMD FidelityFX Super Resolution) no Mobile:** ativar `scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR` na Godot 4 com escala 0.70x–0.80x no Android, aliviando o fillrate das GPUs mobile em telas FHD+/QHD+ enquanto o HUD e botões 2D continuam nítidos em resolução nativa.
   - **Otimização de Sombras Mobile:** sombras direcionais limitadas a 1 ou 2 splits a 60–80 m no preset Leve, e apenas sombra de contato (blob shadow) no preset Mínimo.
   - **Culling de Geometria e Draw Calls:** distância de visão dos blocos de edifícios procedurais e torcida reduzidos em dispositivos móveis, e `cam.far` reduzido de 6000 m para 2000 m no celular.
   - **Avaliação de Renderer (Vulkan Mobile vs OpenGL Compatibility):** suporte e testes com fallback para `gl_compatibility` (OpenGL ES 3.0), que evita bugs de drivers Vulkan e reduz aquecimento térmico em SoCs com GPU Mali (Exynos/MediaTek).
   - **Redução do Tamanho do APK:** exclusão de assets e pastas de teste (`scripts/tests/*`, `data/tests/*`), compactação de texturas ASTC e otimização de GLBs.

---

## Ponto de Partida e Status Atual (Base Consolidada em 10/11/2026)

- [x] Interlagos exportada com relevo SRTM em precisão de 0,1 mm e materiais de asfalto/zebras estilo LMU.
- [x] 13 carros GT3 com pintura com verniz, suspensão visual, rotação/esterço e pinças paradas.
- [x] Garagem 3D interativa funcionando com giratório e reflexos de estúdio.
- [x] Física 500 Hz portada para GDScript com sub-stepping matemático integrado ao loop de 60 Hz da engine.
- [x] Câmera de perseguição estilo LMU com atraso de rumo e transferência de peso nos eixos.
- [x] Sistema de som nativo Godot com bancos de motor `engine-sim`, turbo, pneus e superfícies.
- [x] Arredores LMU: anel de 1400 edifícios procedurais via `MultiMeshInstance3D`, horizonte cilíndrico de 4 km e torcida de 40.000 pessoas particionada em 18 blocos com culling dinâmico.
- [x] HUD redondo estilo LMU com luzes de troca, mostrador de pneus por slip e painéis de tempos.
- [x] Presets gráficos reais no menu de pausa: **Leve**, **Médio** e **Extremo**.
- [x] Pipeline de build automatizado: `Build-Android.bat` gerando APK assinado para ARM64.

---

## Etapas Detalhadas de Implementação

### 1. Fundação e Dados Atualizados (Sincronização com o Web)
- [x] Organizar o projeto em pastas e módulos de cena/scripts. (07/11)
- [x] Exportador `tools/prep.ts` gerando geometria, árvores e dados de pista. (07/11)
- [ ] **Sincronização das Novas Referências e Calibrações:**
  - Rodar `npx vite-node prep.ts -- dados` para importar:
    - `data/cars/mercedes-amg-gt3.json` e a referência `data/reference/interlagos-amg.json` (calibrada com 4 voltas do iRacing).
    - Parâmetros atualizados de `porsche-992-gt3r.json`, `audi-r8-lms-gt3.json` e `ford-mustang-gt3.json`.
  - Atualizar `data/cars.json` com os 13 carros devidamente balanceados.
  - Teste de validação: `godot --headless --script res://scripts/tests/check_cars.gd`.

### 2. Física com Paridade e Modo Arcade
- [x] `car.gd` lendo o acerto do JSON (`Car.load_car(ground, id)`). (07/11)
- [x] Câmbio manual/automático, ABS e TC ligáveis. (07/11)
- [x] Sub-stepping matemático a 500 Hz mantendo paridade com loop da engine a 60 Hz. (10/11)
- [ ] **Implementar Modo Arcade no `car.gd`:**
  - Adicionar propriedade `grip_scale: float = 1.0` (Simulador = 1.0, Arcade = 1.8).
  - Aplicar `grip_scale` no cálculo de aderência dos pneus dianteiros e traseiros.
  - **Mecanismo Anti-Capotamento:** quando `grip_scale > 1.0`, reduzir o braço vertical do momento de tombamento pela fórmula:
    $$\Delta h = (\text{body.pos} - \text{point}) \cdot \text{up}$$
    $$\text{point} += \text{up} \cdot \left(\Delta h \cdot \left(1 - \frac{1}{\text{grip\_scale}^2}\right)\right)$$
    Evita capotamentos acima de 3 g nas curvas velozes (Curva do Sol, Junção, Subida dos Boxes).
- [ ] **Ré Automática no Toque (`brake_to_reverse`):**
  - Quando a velocidade longitudinal for $< 0,5\text{ m/s}$ e o freio for segurado $> 30\%$ sem acelerar por $0,4\text{ s}$, engatar marcha ré (`gear = -1`).
  - Em ré, os pedais invertem (freio acelera para trás, acelerador freia o carro).
  - Parado em ré com acelerador $> 10\%$, engatar 1ª marcha automaticamente.
- [ ] **Correção da Projeção 2D da Pista (`scripts/track/track.gd`):**
  - No `nearest()`, quando `hint < 0`, remover a penalidade vertical `+ 4.0 * (q.y - p.y)^2`, usando apenas a distância euclidiana horizontal no plano XZ `(q.x - p.x)^2 + (q.z - p.z)^2`.
  - No `locate()`, calcular o produto escalar horizontal 2D `(p.x - P[i].x) * T[i].x + (p.z - P[i].z) * T[i].z < 0.0` em vez de projeção 3D com inclinação vertical.
- [ ] **Atualização do `RefBot` (`scripts/track/ref_bot.gd`):**
  - Suporte aos parâmetros `yaw_p`, `yaw_i`, `line_gain` e `hold_line` para acompanhar o traçado da Mercedes-AMG GT3 e novas referências.
- [ ] Teste automatizado: `scripts/tests/paridade.gd` validando o modo Arcade (1.8x) e Simulador (1.0x).

### 3. Controles Mobile e Desktop Completos
- [x] Teclado e controle com limites de esterço por velocidade, zona morta e curvas exponenciais. (07/11)
- [x] Vibração háptica de controle (rumble para zebras, ABS, rotação e limitador). (07/11)
- [x] Controle de toque Legacy funcional com botões digitais. (07/11)
- [ ] **Implementar os 4 Modos de Toque no `touch_controls.gd` e `input_reader.gd`:**
  - **1. Modo Padrão (Recomendado):**
    - Analógico virtual horizontal à esquerda com retorno automático, deadzone de 8% e resposta exponencial 1.6.
    - Pedais de FREIO e ACEL. proporcionais à direita: leitura da coordenada Y do toque com curva (0 a 15% de toque = 0 a 10% do pedal; 15 a 85% = proporcional; >85% = 100%).
  - **2. Modo Fly-by-wire:**
    - Analógico horizontal à esquerda para direção.
    - Barra vertical única à direita: centro neutro ($\pm 6\%$), deslizar para cima acelera gradualmente até 100%, deslizar para baixo freia gradualmente até 100%. Vibração do aparelho (`Input.vibrate_handheld(8)`) ao cruzar a zona neutra.
  - **3. Modo Inclinar (Giroscópio / Acelerômetro):**
    - Direção calculada a partir de `Input.get_accelerometer()`.
    - Ângulo no plano da tela: $\theta = \text{atan2}(g.y, g.x) \cdot \frac{180}{\pi}$.
    - Filtro de suavização contra tremor da mão ($1 - e^{-dt / 0.08}$), zona morta de $2^\circ$ e batente a $\pm 30^\circ$.
    - Botão na tela de auto-centralização/recenter para calibrar a inclinação neutra conforme a pegada do jogador.
    - Pedais na tela (digitais ou proporcionais).
  - **4. Modo Legacy:**
    - Botões digitais ◀ ▶ e pedais liga/desliga com as rampas clássicas de aceleração e retorno.
- [ ] **Pointer Capture e Transição Suave entre Pedais:**
  - Rastrear toques por ID (`event.index`); ao deslizar o polegar da área de acelerador para freio (ou vice-versa), trocar o comando sem necessidade de levantar o dedo e sem cancelamento acidental.
- [ ] **Escala do Limite de Esterço no Arcade:**
  - Ajustar `steer_limit` no `input_reader.gd`: `limit = min(1.0, steer_limit(speed) * grip_scale)`.
- [ ] Teste de controles: atualizar `scripts/tests/controles.gd` para cobrir os 4 modos mobile e o sensor de inclinação.

### 4. Cronometragem, Regras e Recordes Separados
- [x] Volta lançada, 3 setores, delta ao vivo e detecção de corte de pista. (07/11)
- [ ] **Separação de Recordes por Modo de Jogo:**
  - Salvar recordes do Simulador em `user://recordes-interlagos-v3.json`.
  - Salvar recordes do Arcade em `user://recordes-interlagos-arcade.json`.
  - Alternar a tabela de recordes em tempo de execução ao mudar de modo no menu.
  - No HUD e na tabela de melhores voltas, indicar o modo atual (ex.: `[SIM]` ou `[ARCADE]`).
- [ ] Teste: `scripts/tests/cronometragem.gd` validando separação de recordes.

### 5. Câmera Estilo LMU
- [x] Perseguição com FOV dinâmico, atraso suave de rumo e reação longitudinal a g de frenagem/aceleração. (07/11)
- [x] Alternância entre perseguição, capô e externa longa. (07/11)

### 6. Carros e Garagem
- [x] Modelos dos 13 GT3 corrigidos com rodas independentes e pinças paradas. (07/11)
- [x] Cena de garagem com iluminação de estúdio e plataforma giratória. (07/11)
- [ ] Garantir que o modelo e pinturas da Mercedes-AMG GT3 2020 estejam 100% integrados à garagem e pista.

### 7. Pista e Geometria Base
- [x] Asfalto LMU com faixas de borracha, manchas e marcas de pneu. (07/11)
- [x] Zebras, guard-rails, placas e muros exportados. (07/11)
- [x] Culling de distância em objetos pequenos para eliminar gargalos de GPU. (10/11)

### 8. Otimização Extrema de Performance Mobile (Foco APK 60 FPS)
- [x] Sub-stepping de física a 500 Hz integrado ao loop de 60 Hz. (10/11)
- [x] Overrides `.mobile` no `project.godot` para limites de VRAM de sombras. (10/11)
- [x] Sombra de contato chassi (blob shadow) sob o carro para evitar efeito de flutuação no celular. (10/11)
- [ ] **Novo Preset Gráfico "Mínimo (Celular Fraco)" (Total de 4 Presets):**
  - **Mínimo:** pensado para celulares básicos (Mali-G52, Adreno 610/619). Sem sombras direcionais (apenas blob shadow), resolução 3D a 70% com FSR, sem MSAA, sem desfoque de velocidade, sem SSAO/SSIL/SSR, sem torcida, prédios e árvores visíveis apenas até 150 m.
  - **Leve (Mobile Bonito):** celulares intermediários (Snapdragon 778G, Dimensity 8100, Mali-G77). Sombras 1 split até 60 m (1024/2048), resolução 3D a 80% com FSR, MSAA 2x, torcida visível até 120 m, árvores até 220 m.
  - **Médio (Mobile Top / PC Médio):** celulares topo de linha (Snapdragon 8 Gen 1/2/3, iPhone Pro) e PCs intermediários. Sombras 4 splits até 130 m, resolução 100% nativa, SSAO suave, desfoque radial suave, arredores até 500 m.
  - **Extremo (PC com GPU Dedicada):** PCs gamer. SSAO forte, SSIL, SSR 48 passos, sombras 180 m, MSAA 4x, arredores 900 m.
- [ ] **FSR 1.0 (AMD FidelityFX Super Resolution) no Mobile:**
  - Configurar no viewport:
    - `get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR`
    - `get_viewport().fsr_sharpness = 0.2`
    - `get_viewport().scaling_3d_scale = 0.70` (Mínimo), `0.80` (Leve) e `1.0` (Médio/Extremo).
  - Garante alívio massivo de processamento de fragmentos da GPU mantendo nitidez das linhas e texturas, enquanto o HUD e botões 2D continuam renderizados na resolução nativa 1080p da tela.
- [ ] **Ajuste de Far Plane da Câmera no Mobile:**
  - Reduzir `cam.far` de 6000 m para 2000 m no Android nos presets Mínimo e Leve, economizando precisão de Z-buffer e descartando vértices fora do campo visível.
- [ ] **Avaliação e Testes de Driver (Vulkan Mobile vs OpenGL Compatibility):**
  - O renderizador padrão mobile da Godot 4 é o Vulkan Mobile (`renderer/rendering_method.mobile="mobile"`).
  - Configurar chave de fallback ou preset de teste com `gl_compatibility` (OpenGL ES 3.0), verificando estabilidade térmica e FPS em aparelhos Android com drivers Vulkan instáveis.

### 9. Arredores e Cenário LMU
- [x] Anel de edifícios procedurais via `MultiMeshInstance3D` com shader de fachada em coordenadas de mundo. (10/11)
- [x] Faixa cilíndrica de horizonte com névoa e relevo da Cantareira/Serra do Mar. (10/11)
- [x] Capões de mata com árvores impostoras agrupadas em blocos com frustum culling. (10/11)
- [x] Torcida LMU de 40.000 pessoas particionada em 18 blocos com controle dinâmico por preset de qualidade. (10/11)

### 10. HUD LMU e Menu de Configurações Completo
- [x] Mostrador redondo LMU, velocímetro, conta-giros, pedais e slip de pneus. (10/11)
- [x] Painel de instrumentos específico do Porsche 992 GT3 R na câmera de capô. (10/11)
- [x] Painéis de tempos, mapa de pista e minimapa com posições. (10/11)
- [ ] **Atualização do Menu de Pausa e Configurações (`scripts/ui/pause_menu.gd`):**
  - Adicionar seletor de **Modo de Jogo:** `Simulador` (física realista) / `Arcade` (1.8x de aderência e anti-tombamento) com nota explicativa.
  - Adicionar seletor de **Controles Mobile:** `Padrão` / `Fly-by-wire` / `Inclinar` / `Legacy` (visível no celular ou em modo `--touch`).
  - Adicionar botão de **Calibrar Volante (Recentralizar)** quando o modo Inclinar estiver ativo.
  - Adicionar os 4 presets gráficos (`Mínimo`, `Leve`, `Médio`, `Extremo`).
  - Persistir todas as escolhas em `user://jogo.cfg`.
- [ ] **Responsividade para Telas Ultrawide Mobile (19.5:9, 20:9 e Notch):**
  - Ajustar posicionamento do HUD e botões de toque com `DisplayServer.get_display_safe_area()`, garantindo que entalhes de câmera frontal ou cantos arredondados de celulares como o Galaxy S22/S23 não cubram botões nem textos.

### 11. Sistema de Som Nativo Godot
- [x] Motores do `engine-sim` com crossfade por potência sonora e rotação. (10/11)
- [x] Efeitos de pneu cantando, zebras, vento, freio e superfícies nos buses de áudio nativos. (10/11)

### 12. Modo Online (Ranking e Fantasmas)
- [ ] **Consumo da API de Ranking com Suporte ao Modo:**
  - Chamar `/api/ranking?modo=sim` ou `/api/ranking?modo=arcade` via `HTTPRequest`.
  - Exibir a tabela correspondente no menu de melhores tempos.
- [ ] **Envio de Voltas Válidas:**
  - Postar volta válida para `/api/volta` com nome do piloto, carro, tempo, setores e tag do modo (`sim` ou `arcade`).
- [ ] **Fantasmas em Tempo Real:**
  - Transmissão leve via WebSocket/WebRTC exibindo fantasmas translúcidos na pista.

### 13. Otimização e Empacotamento do APK Android (e Preparação iOS)
- [x] Preset Android configurado em `export_presets.cfg` com assinatura de release e modo paisagem travado. (10/11)
- [x] Script `Build-Android.bat` para exportação de release em 1 clique. (10/11)
- [ ] **Redução de Tamanho do APK:**
  - Configurar filtros de exclusão no `export_presets.cfg` para ignorar `scripts/tests/*`, `data/tests/*`, scripts de pré-processamento (`tools/*`), vídeos temporários e assets não utilizados no runtime.
  - Validar compressão ASTC para todas as texturas 3D.
- [ ] **Bateria de Testes de Desempenho no Celular do Davi:**
  - Instalar o APK compilado via ADB (`adb install -r build/android/GT3 Time Attack.apk`).
  - Medição de FPS em tempo real com o contador do HUD nos 4 presets.
  - Validar estabilidade de 60 FPS cravados no preset Leve ou Mínimo.
  - Testar sensibilidade e ergonomia dos 4 esquemas de toque.
  - Monitorar consumo de bateria e dissipação térmica após 10 minutos contínuos de pilotagem.

### 14. Distribuição e Atualização
- [x] Pacote Windows `.exe` pronto para exportação. (08/11)
- [x] APK Android assinado gerado em `build/android/`. (10/11)
- [ ] Verificador leve de atualizações online (checagem de versão via JSON para avisar se há APK novo disponível).

---

## Ordem Imediata de Execução

1. **Fase A (Dados):** Sincronizar dados do web para o Godot (`tools/prep.ts`), trazendo a Mercedes-AMG GT3, a nova referência do iRacing (`interlagos-amg.json`) e acertos refinados dos carros.
2. **Fase B (Física & Modo Arcade):** Implementar no `car.gd` o multiplicador `grip_scale` (1.8x), a fórmula de anti-capotamento, a ré automática no celular (`brake_to_reverse`), a correção 2D da pista no `track.gd` e o `RefBot` atualizado.
3. **Fase C (Controles Mobile):** Expandir `touch_controls.gd` e `input_reader.gd` para suportar os 4 esquemas de toque (Padrão com pedais por altura, Fly-by-wire com háptica, Inclinar com acelerômetro/recenter e Legacy).
4. **Fase D (Otimização Mobile Extrema):** Implementar o preset **Mínimo**, ativar upscaling **FSR 1.0** para resolução dinâmica no mobile e ajustar distâncias de culling de sombras e cenário.
5. **Fase E (Menu & HUD):** Integrar seletores de Modo (Simulador/Arcade) e de Controles no menu de pausa, suporte à safe area de telas 20:9 e divisão de recordes locais.
6. **Fase F (Validação no Aparelho):** Gerar novo APK otimizado e testar no celular do Davi para comprovar 60 FPS lisos e ergonomia perfeita.

---

## Regras de Trabalho

- Perguntar antes de commit, push e de criar repositório.
- Não versionar builds (`.exe`, `.apk`), vídeos nem `.godot/`.
- Câmera calma, sem cockpit, uma etapa por vez.
- Sempre manter paridade matemática com os dados e telemetrias de referência.
