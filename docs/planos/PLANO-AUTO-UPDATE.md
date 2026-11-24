# Plano: Sistema de Auto-Update Incremental (Patches em Cadeia)

## Objetivo
Substituir o fluxo antigo (APK "magro" + `base_data.pck` de ~250 MB) por um **APK base completo (~180 MB)** com todos os assets embarcados, seguido de **atualizações automáticas leves em cadeia** (`vN -> vN+1`) publicadas no GitHub Releases contendo **apenas os arquivos alterados** entre uma versão e outra.

---

## Diagnóstico do Sistema Atual (Por que falhou antes)
1. **Versão do Godot divergente no CI:** [.github/workflows/release-patch.yml](.github/workflows/release-patch.yml) usava Godot `4.3`, enquanto o APK é compilado com Godot `4.7.2` ([Build-Android.bat](Build-Android.bat)). O `updater.gd` validava `major.minor` e descartava o `.pck`.
2. **Timeout muito curto:** `http_version.timeout = 1.5` segundos em [scripts/ui/updater.gd](scripts/ui/updater.gd) causava falhas silenciosas em redes móveis.
3. **Ordem de carregamento do `Game`:** `updater.gd` acessava `Game` ([scripts/game.gd](scripts/game.gd)) no `_ready()` antes de `ProjectSettings.load_resource_pack()`, impedindo que patches atualizassem `game.gd`.
4. **Preset `Patch` rígido:** Em [export_presets.cfg](export_presets.cfg), o preset `Patch` excluía `assets/*` por completo e reempacotava todos os scripts/JSONs inteiros a cada release.

---

## Arquitetura: Estratégia A — Patches em Cadeia

### 1. Estrutura do `version.json`
O manifesto na raiz do repositório passa a listar a cadeia de patches a partir do APK base:

```json
{
  "latest_version": 9,
  "min_apk_version": 8,
  "patches": [
    {
      "version": 9,
      "tag": "v1.8",
      "url": "https://github.com/daviml/gt3-godot/releases/download/v1.8/patch_v9.pck",
      "changelog": "Ajustes de física e UI."
    }
  ]
}
```

- `latest_version`: maior número inteiro de versão disponível.
- `min_apk_version`: versão mínima do APK base compatível com a cadeia atual de patches.
- `patches`: lista ordenada por `version` crescente. Cada item representa **apenas o delta** daquela release.

### 2. Fluxo no Cliente (`scripts/ui/updater.gd`)
1. **Desacoplar `updater.gd` de `Game`:** Não referenciar `Game` nem outros scripts do jogo antes de montar os patches. Dados visuais iniciais do updater ficam autocontidos ou são lidos após os patches.
2. **Timeout e Anti-Cache:**
   - Aumentar `http_version.timeout` para `8.0`s e `http_download.timeout` para `60.0`s.
   - Consultar `version.json` com query string anti-cache (`?_ts=<unix_time>`) para evitar o cache de ~5 min do `raw.githubusercontent.com`.
3. **Validação de `min_apk_version`:**
   - Se `CURRENT_CLIENT_VERSION < min_apk_version`, exibir mensagem orientando baixar o novo APK base (e permitir jogar offline se aplicável ou abrir link da release).
4. **Download em Cadeia:**
   - Calcular `local_ver = max(CURRENT_CLIENT_VERSION, versão salva em user://installed_version.json)`.
   - Filtrar todos os itens de `patches` com `version > local_ver`, ordenados por `version`.
   - Baixar um a um para `user://patches/patch_v<N>.pck` (usando `.tmp` + validação `_is_pck_compatible()` antes de renomear).
   - Atualizar `installed_version.json` a cada patch concluído com sucesso (resiliente se cair a conexão no meio).
5. **Montagem dos Pacotes na Inicialização:**
   - Antes de carregar `garagem.tscn` (ou `Game`), listar todos os `user://patches/patch_v*.pck` com `version > CURRENT_CLIENT_VERSION` e montar **em ordem numérica crescente** via `ProjectSettings.load_resource_pack(path, true)`.
   - Quando um novo APK base for instalado (`CURRENT_CLIENT_VERSION >= versão do patch`), limpar os patches antigos de `user://patches/`.

### 3. Geração do `patch_vN.pck` Diferencial (CI + Local)
1. **Detecção de diferenças:**
   - `git diff --name-only <tag_anterior> HEAD -- scripts/ scenes/ data/ shaders/ assets/ icon.png`
2. **Exportação compatível com Android (Godot 4.7.2):**
   - Criar ferramenta/script auxiliar (ex.: `tools/build_diff_patch.py` ou `.gd`) que:
     - Verifica os arquivos modificados/adicionados do diff.
     - Atualiza temporariamente um preset de exportação Android (com `etc2_astc=true`, `s3tc_bptc=false`, `export_filter="resources"`) contendo apenas os caminhos alterados em `export_files`.
     - Executa `godot --headless --import` (no CI) e depois `godot --headless --export-pack "PatchAndroid" "build/packs/patch_v<N>.pck"`.
   - Dessa forma, o próprio Godot compila `.gd` -> `.gdc` e inclui os artefatos corretos de `.godot/imported/` quando houver alteração em texturas, modelos `.glb` ou áudios.

### 4. Automação no GitHub Actions (`.github/workflows/release-patch.yml`)
1. Atualizar engine no workflow para **Godot `4.7.2-stable`**.
2. Identificar automaticamente a tag anterior (`git describe --tags --abbrev=0 HEAD^` ou input do workflow).
3. Gerar `patch_v<N>.pck` apenas com o diff desde a tag anterior.
4. Criar a GitHub Release anexando `patch_v<N>.pck` (e opcionalmente `version.json`).
5. Atualizar `version.json` na branch `main` adicionando o novo item em `patches` e atualizando `latest_version`.

---

## Fases de Implementação
1. **Fase 1 — Cliente (`updater.gd`):** Desacoplar `Game`, implementar `user://patches/`, download sequencial, anti-cache e check de `min_apk_version`.
2. **Fase 2 — Script de Diff Pack (`tools/`):** Criar gerador de `.pck` diferencial compatível com Android/Godot 4.7.2 e testar localmente.
3. **Fase 3 — Workflow GitHub Actions:** Atualizar `release-patch.yml` para Godot 4.7.2 + geração diferencial + append no `version.json`.
4. **Fase 4 — APK Base Novo (`v1.7` / `version 8`):** Alinhar `CURRENT_CLIENT_VERSION = 8`, `export_presets.cfg` (`version/code=8`, `version/name="1.7"`), `version.json` (`latest_version: 8`, `min_apk_version: 8`, `patches: []`), compilar o APK completo (~180 MB) e validar com um patch `v9` de teste.
