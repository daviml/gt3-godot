# Texturas por plataforma. O Godot não tem configuração de importação por plataforma: no PC as texturas usam
# alta qualidade (BPTC/ASTC) e até 2048 px; no Android isso dobra o APK (~180 → ~290 MB) e multiplica a memória de
# vídeo (risco de fechar em celular fraco). O Build-Android.bat chama:
#   python tools/texturas_android.py android   → high_quality=false e size_limit 2048→1024 em todos os .import de textura
#   (reimporta, exporta o APK)
#   python tools/texturas_android.py pc        → volta exatamente o que estava (guardado em build/texturas_pc.json)
# Se um build for interrompido, rodar "pc" de novo restaura.
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BACKUP = os.path.join(ROOT, 'build', 'texturas_pc.json')
SKIP = {'.godot', 'build', 'node_modules', '.git', 'deploy'}


def import_files():
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = [x for x in dirs if x not in SKIP and not os.path.exists(os.path.join(d, x, '.gdignore'))]
        for f in files:
            if f.endswith('.import'):
                yield os.path.join(d, f)


def read(p):
    with open(p, 'r', encoding='utf-8', newline='') as fh:
        return fh.read()


def write(p, s):
    with open(p, 'w', encoding='utf-8', newline='') as fh:
        fh.write(s)


def get(s, key):
    m = re.search(r'^' + re.escape(key) + r'=(.*)$', s, re.M)
    return m.group(1).rstrip('\r') if m else None


def put(s, key, val):
    return re.sub(r'^(' + re.escape(key) + r'=)[^\r\n]*', lambda m: m.group(1) + val, s, flags=re.M)


mode = sys.argv[1] if len(sys.argv) > 1 else ''
if mode == 'android':
    if os.path.exists(BACKUP):
        sys.exit('build/texturas_pc.json já existe (build anterior interrompido?): rode "pc" antes')
    saved, n = {}, 0
    for p in import_files():
        s = read(p)
        if get(s, 'importer') != '"texture"':
            continue
        hq, lim = get(s, 'compress/high_quality'), get(s, 'process/size_limit')
        if hq is None or lim is None:
            continue
        new = put(s, 'compress/high_quality', 'false')
        if lim == '2048':
            new = put(new, 'process/size_limit', '1024')
        if new != s:
            saved[os.path.relpath(p, ROOT)] = {'hq': hq, 'lim': lim}
            write(p, new)
            n += 1
    os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
    json.dump(saved, open(BACKUP, 'w'), indent=0)
    print(f'texturas: {n} arquivos em modo Android (1024 px, compressão normal)')
elif mode == 'pc':
    if not os.path.exists(BACKUP):
        print('texturas: já em modo PC')
        sys.exit(0)
    saved = json.load(open(BACKUP))
    for rel, v in saved.items():
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            s = put(put(read(p), 'compress/high_quality', v['hq']), 'process/size_limit', v['lim'])
            write(p, s)
    os.remove(BACKUP)
    print(f'texturas: {len(saved)} arquivos de volta ao modo PC')
else:
    sys.exit('uso: python tools/texturas_android.py android|pc')
