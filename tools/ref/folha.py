"""Folhas lado a lado LMU × Godot por metro de pista (PLANO-INTERLAGOS-DETALHES.md §2, Fase 0).

Esquerda: quadro do vídeo do LMU (build/ref/interlagos/<camera>/sNNNN.jpg, gerado por atlas_video.py).
Direita: print do Godot no mesmo s (capture_compare.gd --atlas, sNNNN.png).
Cada linha leva "s = NNNN m" e o nome do trecho (data/track/track.json → sections).

Uso:
  python tools/ref/folha.py --lmu build/ref/interlagos/chase --godot build/ref/interlagos/godot/chase \
      --out build/ref/interlagos/folhas/chase --s0 0 --s1 4290 --passo 50
  --s1 < --s0 cruza a linha de chegada (ex.: --s0 3884 --s1 250). --lista 352,382,… no lugar de --s0/--s1/--passo.
  Interlagos desde a Fase 2B etapa F: --lmu build/ref/interlagos/chase_v2 (quadros no s novo, atlas_s_novo.py).
Gera folha_01.jpg, folha_02.jpg… com --por-pagina linhas cada (padrão 6). s faltando em um dos lados: avisa e pula.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parents[2]
EXT = (".jpg", ".png", ".jpeg")
MARGEM = 8
FAIXA = 44  # altura da faixa de texto de cada linha


def achar(pasta: Path, s: int) -> Path | None:
    for ext in EXT:
        p = pasta / f"s{s:04d}{ext}"
        if p.exists():
            return p
    return None


def secoes(track_json: Path) -> list[dict]:
    try:
        return json.loads(track_json.read_text(encoding="utf-8")).get("sections", [])
    except (OSError, ValueError) as e:
        print(f"aviso: sem seções ({track_json}: {e})", file=sys.stderr)
        return []


def nome_trecho(secs: list[dict], s: float) -> str:
    for sec in secs:
        if sec["s0"] <= s < sec["s1"]:
            return sec["name"]
    return ""


def fonte(tam: int) -> ImageFont.ImageFont:
    for nome in ("arialbd.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(nome, tam)
        except OSError:
            pass
    return ImageFont.load_default()


def lista_s(s0: float, s1: float, passo: float, comprimento: float) -> list[int]:
    """Mesma regra do capture_compare.gd --atlas: se s1 < s0, cruza a chegada e recomeça em 0, passo, 2·passo…"""
    out: list[int] = []
    cruza = s1 < s0
    s = s0
    while s < comprimento - 1e-6 and (cruza or s <= s1 + 1e-6):
        out.append(round(s))
        s += passo
    if cruza:
        s = 0.0
        while s <= s1 + 1e-6:
            out.append(round(s))
            s += passo
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lmu", required=True, help="pasta com os quadros do LMU (sNNNN.jpg)")
    ap.add_argument("--godot", required=True, help="pasta com os prints do Godot (sNNNN.png)")
    ap.add_argument("--out", required=True, help="pasta de saída das folhas")
    ap.add_argument("--s0", type=float, default=0.0)
    ap.add_argument("--s1", type=float, default=4290.0)
    ap.add_argument("--passo", type=float, default=50.0)
    ap.add_argument("--lista", default="", help="metros livres separados por vírgula (no lugar de --s0/--s1/--passo)")
    ap.add_argument("--por-pagina", type=int, default=6)
    ap.add_argument("--largura", type=int, default=960, help="largura de cada imagem na folha (px)")
    ap.add_argument("--track", default=str(RAIZ / "data/track/track.json"), help="track.json com as seções")
    ap.add_argument("--qualidade", type=int, default=88, help="qualidade do JPEG")
    a = ap.parse_args()

    lmu, godot, out = Path(a.lmu), Path(a.godot), Path(a.out)
    track_json = Path(a.track)
    secs = secoes(track_json)
    try:
        comprimento = float(json.loads(track_json.read_text(encoding="utf-8")).get("length", 1e9))
    except (OSError, ValueError):
        comprimento = 1e9

    pares: list[tuple[int, Path, Path]] = []
    metros = [round(float(x)) for x in a.lista.split(",") if x.strip()] if a.lista else lista_s(a.s0, a.s1, a.passo, comprimento)
    for s in metros:
        pl, pg = achar(lmu, s), achar(godot, s)
        if pl is None or pg is None:
            falta = " e ".join(n for n, p in (("LMU", pl), ("Godot", pg)) if p is None)
            print(f"aviso: s={s:04d} sem {falta}, pulando")
            continue
        pares.append((s, pl, pg))
    if not pares:
        print("nenhum par encontrado", file=sys.stderr)
        return 1

    out.mkdir(parents=True, exist_ok=True)
    w = a.largura
    h = round(w * 9 / 16)
    f_grande, f_peq = fonte(28), fonte(20)
    por = max(1, a.por_pagina)
    paginas = [pares[i:i + por] for i in range(0, len(pares), por)]
    for np_, pagina in enumerate(paginas, 1):
        larg = MARGEM * 3 + w * 2
        alt = MARGEM + len(pagina) * (FAIXA + h + MARGEM)
        folha = Image.new("RGB", (larg, alt), (24, 24, 28))
        dr = ImageDraw.Draw(folha)
        y = MARGEM
        for s, pl, pg in pagina:
            trecho = nome_trecho(secs, s)
            texto = f"s = {s:04d} m" + (f"  —  {trecho}" if trecho else "")
            dr.text((MARGEM, y + 6), texto, font=f_grande, fill=(255, 255, 255))
            dr.text((MARGEM * 2 + w - 70, y + 14), "LMU", font=f_peq, fill=(255, 120, 220))
            dr.text((larg - MARGEM - 80, y + 14), "Godot", font=f_peq, fill=(120, 220, 255))
            y += FAIXA
            for k, p in enumerate((pl, pg)):
                with Image.open(p) as im:
                    im = im.convert("RGB")
                    if im.size != (w, h):
                        im = im.resize((w, h), Image.LANCZOS)
                    folha.paste(im, (MARGEM + k * (w + MARGEM), y))
            y += h + MARGEM
        destino = out / f"folha_{np_:02d}.jpg"
        folha.save(destino, quality=a.qualidade)
        print(f"{destino}  ({len(pagina)} pares: s {pagina[0][0]}–{pagina[-1][0]})")
    print(f"{len(pares)} pares em {len(paginas)} folhas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
