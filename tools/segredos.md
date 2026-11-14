# Token do ranking (segredos.cfg)

O ranking compartilhado fica no repositório privado `daviml/gt3-tempos`. O jogo lê e grava direto nele pela API do
GitHub, sem servidor no meio. Para isso precisa de um token, guardado em `segredos.cfg` na raiz do projeto.

- `segredos.cfg` está no `.gitignore`: **nunca vai para o GitHub**. Em cada PC onde for exportar o jogo, crie de novo.
- Os perfis **Windows**, **Android** e **iOS** do `export_presets.cfg` levam o arquivo para dentro do jogo.
  **DataPack** e **Patch** (que vão para o release público) excluem o arquivo.
- Sem o arquivo, o jogo funciona: mostra a última cópia do ranking e guarda as voltas no aparelho; elas sobem
  sozinhas na próxima vez que o jogo abrir com token e internet.
- Quem tem um APK/instalador antigo sem o token precisa reinstalar uma vez (patch não leva o token).

## Criar o token
GitHub → Settings → Developer settings → Fine-grained tokens → Generate new token:
- Repository access: **Only select repositories → gt3-tempos**
- Permissions → Repository → **Contents: Read and write** (nada mais)

## Criar o segredos.cfg
Salve o token num arquivo de texto (ex.: `tok.txt`) e rode na raiz do projeto:

```
node -e "const fs=require('fs');const t=fs.readFileSync(process.argv[1],'utf8').replace(/\s+/g,'');const k=Buffer.from('gt3-interlagos-2026');const b=Buffer.from(t);for(let i=0;i<b.length;i++)b[i]^=k[i%k.length];fs.writeFileSync('segredos.cfg','[ranking]\n\ngithub_token_x=\"'+b.toString('base64')+'\"\n')" tok.txt
```

Depois apague o `tok.txt`. (Também funciona `github_token="..."` em texto puro, mas embaralhado evita que buscas
automáticas achem o token no pacote.)

## Se o token vazar
Apague o token no GitHub, crie outro, refaça o `segredos.cfg` e exporte o APK/instalador de novo. Qualquer estrago no
ranking se desfaz revertendo commits no `gt3-tempos`.
