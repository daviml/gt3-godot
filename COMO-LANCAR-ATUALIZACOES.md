# Como Lançar Atualizações no GitHub Actions

Este guia descreve o fluxo oficial para publicar atualizações automáticas (patches incrementais leves) e quando é necessário gerar um novo APK base.

---

## Resumo Rápido: Patch Automático vs. APK Novo

| O que você alterou? | Precisa mandar APK novo? | Como lançar? |
| :--- | :---: | :--- |
| Scripts (`.gd`), física, UI, cenas (`.tscn`), JSONs (`data/`), shaders | **Não** | Push + Tag `v*` (ou `workflow_dispatch`) |
| Carros (`.glb`), texturas, sons, pista (`assets/`) | **Não** | Push + Tag `v*` (baixa só os assets alterados) |
| Versão do Godot (ex: 4.7 → 4.8), permissões Android, pacote/ícone, ou o próprio `updater.gd` | **Sim** | Gerar novo APK base e subir `min_apk_version` |
| Cadeia de patches ficou muito longa (ex: 15+ patches acumulados) | **Opcional** | Gerar novo APK base para "zerar" a cadeia |

---

## Passo a Passo: Lançar uma Atualização Automática (Patch)

### 1. Faça seus commits normalmente na `main`
Teste o jogo localmente no editor/Windows/Android e envie as alterações para o GitHub:
```bash
git add .
git commit -m "feat: melhoria na fisica e ajuste de UI"
git push origin main
```

### 2. Dispare a Release no GitHub Actions
Você tem **duas formas** de disparar:

#### Opção A — Via Tag Git (Recomendado)
Crie e envie uma tag seguindo o padrão `v*` (ex: `v1.8`, `v1.9`):
```bash
git tag v1.8
git push origin v1.8
```

#### Opção B — Manual pela Interface do GitHub
1. Abra o repositório no GitHub → aba **Actions**.
2. Selecione o workflow **Publicar Atualizacao (Release Patch)**.
3. Clique em **Run workflow**, preencha:
   - **version**: próximo número inteiro sequencial (ex: `9`, `10`, `11` — sempre maior que `latest_version` do `version.json`).
   - **tag_name**: nome da tag (ex: `v1.8`).
   - **changelog**: descrição curta do que mudou.

### 3. O que o GitHub Actions faz automaticamente
1. Baixa o **Godot 4.7.2** headless e importa o projeto.
2. Compara os arquivos alterados desde a **tag anterior** (`git diff --name-only <tag_anterior> HEAD`).
3. Empacota **somente os arquivos modificados/adicionados** em `patch_v<N>.pck` (formato Android `etc2_astc`).
4. Cria a **GitHub Release** com a tag informada e anexa o `patch_v<N>.pck`.
5. Atualiza o `version.json` na branch `main` adicionando o novo patch na lista `patches` e atualizando `latest_version`.

> **Importante:** Após rodar o workflow, faça `git pull origin main` no seu PC antes de continuar trabalhando, para puxar o commit automático do `version.json`.

---

## Passo a Passo: Quando Precisar Lançar um Novo APK Base

Faça isso apenas quando mudar a versão do Godot, o `updater.gd`, configurações do Android, ou quando quiser zerar a cadeia de patches antigos:

1. **Atualize os números de versão** (todos devem bater):
   - `scripts/ui/updater.gd`: `CURRENT_CLIENT_VERSION = <NOVO_N>`
   - `export_presets.cfg` (preset `Android`): `version/code=<NOVO_N>` e `version/name="<X.Y>"`
   - `version.json`:
     ```json
     {
       "latest_version": <NOVO_N>,
       "min_apk_version": <NOVO_N>,
       "patches": []
     }
     ```
2. **Compile o APK** localmente rodando [Build-Android.bat](Build-Android.bat) (gera `build/android/GT3 Time Attack.apk` com ~180 MB).
3. **Commit, push e crie a tag base** (ex: `v2.0`) na mesma versão `<NOVO_N>` e anexe o APK manualmente na Release do GitHub para distribuir aos seus amigos.
4. A partir daí, todas as próximas atualizações voltam a ser patches automáticos leves (`<NOVO_N + 1>`, `<NOVO_N + 2>`, ...).

---

## Cuidados para Não Quebrar o Sistema
- **Nunca delete uma tag ou Release antiga** que ainda esteja listada em `patches` no `version.json`, pois amigos que não atualizam há algumas versões precisam baixar os elos da cadeia em ordem.
- **Nunca faça force-push** alterando histórico de tags já publicadas.
- **Sempre mantenha a versão do Godot** no [.github/workflows/release-patch.yml](.github/workflows/release-patch.yml) idêntica à usada no [Build-Android.bat](Build-Android.bat) (`4.7.2-stable`).
- **Não dependa de `Game` ou outros scripts no `updater.gd`**, para que qualquer script do jogo possa ser atualizado via patch sem exigir APK novo.
