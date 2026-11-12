# Plano de Entrega: GT3 Time Attack — Versão Web & PWA (Vercel)

Este documento estabelece o plano completo para empacotar e publicar o **GT3 Time Attack** como uma **Progressive Web App (PWA)** acessível diretamente pelo navegador (PC, Android e iOS / Safari), hospedado na **Vercel**, mantendo **100% de isolamento e zero regressão** nas builds existentes (Windows Desktop, Android APK e Packs).

---

## 1. Princípios e Regras Fundamentais

1. **Zero impacto na build atual:**
   - Nenhuma alteração pode quebrar ou modificar o comportamento dos presets `Windows`, `Android`, `iOS`, `DataPack` ou `Patch`.
   - A configuração de renderizador padrão do projeto continua `forward_plus` no Desktop e `mobile` no Android. O renderizador `gl_compatibility` (WebGL 2.0) será ativado **exclusivamente** via override de feature tag:
     ```ini
     renderer/rendering_method.web="gl_compatibility"
     ```
2. **Compatibilidade Universal (PC + Android + iOS):**
   - **iOS Safari:** Suporte a PWA com `apple-mobile-web-app-capable`, bloqueio de pull-to-refresh/scroll elástico, tratamento de destravamento de `AudioContext` via gesto de toque e limite seguro de consumo de memória.
   - **Android Chrome:** Instalação nativa via Web App Manifest (`beforeinstallprompt`) e suporte a controles touch.
   - **PC Desktop:** Teclado, mouse e controles USB/Bluetooth via Web Gamepad API nativa.
3. **Plataforma de Hospedagem: Vercel:**
   - Configuração de cabeçalhos HTTP rigorosos (`vercel.json`), incluindo `Cross-Origin-Opener-Policy` (COOP), `Cross-Origin-Embedder-Policy` (COEP), suporte aos MIME types corretos (`.wasm`, `.pck`) e regras de cache imutável para assets pesados.
4. **Isolamento de Código via Feature Flags:**
   - Todo comportamento exclusivo de navegador será condicionado por `OS.has_feature("web")`.
   - Na Web, o `updater.gd` deve desviar do download externo de `.pck` via HTTP (evitando problemas de CORS e estouro de cota do IndexedDB/IDBFS) e carregar diretamente a experiência com o `.pck` embutido.

---

## 2. Arquitetura da Solução PWA

```
gt3-godot/
├── export_presets.cfg         # [MODIFY] Adiciona Preset 5: "Web"
├── project.godot              # [MODIFY] Adiciona renderer/rendering_method.web="gl_compatibility"
├── scripts/ui/updater.gd      # [MODIFY] Desvio if OS.has_feature("web") -> vai direto para garagem
├── Build-Web.bat              # [NEW] Script de compilação da build Web
└── deploy/
    └── vercel/                # [NEW] Pasta de publicação para Vercel
        ├── vercel.json        # Configuração de headers, rotas e MIME types
        ├── manifest.json      # Manifesto PWA (nome, cores, landscape, ícones)
        ├── sw.js              # Service Worker para cache e PWA instalável
        ├── index.html         # Shell HTML customizado (splash, áudio unlock, viewport iOS)
        ├── icon-192.png       # Ícone PWA 192x192
        ├── icon-512.png       # Ícone PWA 512x512
        ├── index.js           # (Gerado pelo Godot)
        ├── index.wasm         # (Gerado pelo Godot)
        └── index.pck          # (Gerado pelo Godot)
```

---

## 3. Fases de Execução

### Fase 1: Configuração do Projeto e Preset Web no Godot
- [ ] **Configurar Override no `project.godot`:**
  - Inserir `renderer/rendering_method.web="gl_compatibility"` sem alterar os métodos Desktop (`forward_plus`) e Mobile (`mobile`).
- [ ] **Criar Preset "Web" em `export_presets.cfg`:**
  - Tipo: `Web` (HTML5 / WebAssembly).
  - Suporte a Threads: `Single-Thread` (ou `Thread Support: false` dependendo da versão 4.x), garantindo compatibilidade imediata com Safari iOS sem risco de tela preta por restrições de `SharedArrayBuffer`.
  - VRAM Texture Compression: Ativar compressão adequada (`s3tc_bptc` para navegadores desktop e `etc2_astc` para navegadores mobile).
  - Destino de exportação: `deploy/vercel/index.html`.

### Fase 2: Adaptações de Código (`OS.has_feature("web")`)
- [ ] **Ajuste no `updater.gd`:**
  - Adicionar guarda no início do script:
    ```gdscript
    if OS.has_feature("web"):
        # No navegador, o jogo roda com o pacote completo embarcado
        get_tree().change_scene_to_file("res://scenes/garagem.tscn")
        return
    ```
  - Evita falhas de rede por CORS ou inconsistências com o IndexedDB virtual do Safari.
- [ ] **Gerenciamento de Áudio no iOS:**
  - Garantir que a inicialização do áudio seja deferida até que o jogador clique na tela ("Tocar para Iniciar"), respeitando as políticas do WebKit/Safari.
- [ ] **Controles Touch no Navegador:**
  - Assegurar que `touch_controls.gd` seja inicializado automaticamente quando `DisplayServer.is_touchscreen_available()` for verdadeiro no ambiente Web.

### Fase 3: Camada PWA e Shell Web para Vercel
- [ ] **`manifest.json` (Progressive Web App):**
  - Configurar orientação fixa: `"orientation": "landscape"`.
  - Modo de exibição: `"display": "standalone"` (remove a barra de navegação no Safari e Chrome).
  - Tema: `"theme_color": "#0b0d10"` e `"background_color": "#0b0d10"`.
- [ ] **`index.html` Responsivo e Otimizado:**
  - Meta tags essenciais para iOS:
    - `<meta name="apple-mobile-web-app-capable" content="yes">`
    - `<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">`
    - `<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">`
  - Tela de splash profissional com barra de progresso do download do WASM/PCK.
  - Tela de bloqueio quando o celular estiver na vertical (Portrait) pedindo para girar para a horizontal (Landscape).
- [ ] **`sw.js` (Service Worker):**
  - Registro de Service Worker para habilitar o status de PWA instalável no Android e iOS.
- [ ] **`vercel.json`:**
  - Cabeçalhos de isolamento e segurança:
    ```json
    {
      "headers": [
        {
          "source": "/(.*)",
          "headers": [
            { "key": "Cross-Origin-Opener-Policy", "value": "same-origin" },
            { "key": "Cross-Origin-Embedder-Policy", "value": "require-corp" },
            { "key": "Cache-Control", "value": "public, max-age=3600" }
          ]
        },
        {
          "source": "/(.*)\\.(wasm|pck)",
          "headers": [
            { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
          ]
        }
      ]
    }
    ```

### Fase 4: Automação da Build (`Build-Web.bat`)
- [ ] Criar script `Build-Web.bat` na raiz:
  - Invoca o binário do Godot em modo `--headless`.
  - Exporta para o diretório `deploy/vercel/`.
  - Copia os arquivos da camada PWA (`manifest.json`, `sw.js`, `vercel.json`, ícones) para a pasta final de deploy.

### Fase 5: Publicação na Vercel e Validação
- [ ] **Deploy na Vercel:**
  - Deploy da pasta `deploy/vercel/` via Vercel CLI (`vercel --prod`) ou vinculação direta do repositório GitHub configurando o *Root Directory* para a pasta web.
- [ ] **Matriz de Validação:**
  1. **iOS (Safari / iPadOS):**
     - Acessar via Safari ➔ Testar áudio ➔ Testar botão "Adicionar à Tela de Início" ➔ Executar em modo Standalone (tela cheia).
     - Testar resposta com toque e controle Bluetooth (Xbox / PlayStation).
  2. **Android (Chrome):**
     - Acessar ➔ Verificar aviso de instalação ("Instalar App") ➔ Testar controles de toque e performance em 60 FPS.
  3. **PC (Chrome / Edge / Firefox):**
     - Carregamento rápido via cache ➔ Controles de teclado e Gamepad USB.
  4. **Builds Nativas (Regressão Zero):**
     - Rodar `Build-Android.bat` e testar Windows Desktop para certificar que nada foi afetado.

---

## 4. Limitações Conhecidas e Mitigações

| Desafio | Causa | Mitigação no Plano |
| :--- | :--- | :--- |
| **Limite de Memória no Safari** | iOS WebKit fecha abas com alto consumo de RAM (>1 GB). | Assets já limitados a 1024 nas texturas; build web focada em assets otimizados. |
| **Áudio Inicial Silencioso no iOS** | Autoplay bloqueado pelo navegador até o primeiro toque. | Botão interativo de splash "Tocar para Iniciar" que destrava o `AudioContext`. |
| **CORS no Auto-Updater** | Navegadores bloqueiam requisições a URLs externas sem headers permissivos. | `OS.has_feature("web")` faz o jogo ignorar o updater e ir direto para o menu. |
| **Tamanho do Arquivo na Vercel** | Vercel tem limite de 100 MB por arquivo estático no plano gratuito. | Manter o `.pck` web otimizado ou particionado caso necessário. |

---

## 5. Próximos Passos Imediatos

1. Aprovação do plano.
2. Inclusão da diretiva `renderer/rendering_method.web="gl_compatibility"` no `project.godot`.
3. Adição do preset `Web` no `export_presets.cfg` e teste da primeira compilação headless via `Build-Web.bat`.
4. Montagem dos arquivos da camada PWA e teste de deploy na Vercel.
