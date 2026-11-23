"""Acha sozinho, nos quadros do Godot, onde amostrar cada tinta (PLANO-INTERLAGOS-DETALHES.md, Fase 1).

Marcar à mão retângulos finos de zebra e linha erra fácil (a zebra tem 1 m e fica a 10–30 m da câmera). Aqui:
1) `capture_compare.gd --atlas --ids` fotografa os mesmos metros com cada tinta numa cor-chave sem luz e o resto preto;
2) este script classifica cada pixel pela cor-chave de cromaticidade mais próxima, tira as bordas (erosão), tira a sombra (pixels bem
   mais escuros que a mediana da tinta no quadro normal, se ele for dado) e pega o maior retângulo dentro da máscara
   (limitado em tamanho, longe do horizonte);
3) grava os retângulos do lado "godot" de tools/ref/cores_interlagos.json só para as tintas (asfalto, grama, céu e
   sombra ficam como estão).

Uso:
  python tools/ref/regioes_tinta.py --ids build/ref/interlagos/godot/fase1_tinta/ids \
      --normal build/ref/interlagos/godot/fase1_tinta/antes [--gravar]
Sem --gravar só mostra o que acharia. Confira depois com tools/ref/cores.py (imagens regioes_sNNNN.jpg).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

RAIZ = Path(__file__).resolve().parents[2]

# cor-chave (sRGB 0–255) → material de tools/ref/cores.py. A zebra é desenhada com a própria textura sem luz, então as
# cores dela são as do gerador (TINTA em tools/cenario/interlagos/tintas.ts; só o tom importa, não o brilho); as outras
# são as IDS_TINTA do capture_compare.gd.
CHAVES = {
    "zebra_amarelo": [(132, 156, 0)],     # TINTA.amarelo (tools/cenario/interlagos/tintas.ts)
    "zebra_verde": [(9, 87, 16)],         # TINTA.verde
    "zebra_branco": [(115, 149, 155)],    # TINTA.branco
    "linha_branca": [(0, 255, 255)],
    "pintura_verde_zebra": [(255, 128, 0), (0, 0, 255)],  # escape verde (runMats.verde) + faixa verde atrás da zebra
    "pintura_verde_escape": [(255, 0, 255), (128, 0, 255)],  # verde da Reta Oposta + escape verde-água
    "pintura_vermelha": [(255, 0, 0)],
}
OUTRAS = [(255, 0, 128)]  # salsicha (só para não confundir)
# Classificação por cromaticidade (r, g, b divididos pela soma): a sujeira da textura da zebra escurece sem mudar o tom,
# e a zebra continua reconhecível depois que as cores do gerador mudarem de brilho.
CROMA_MAX = 0.09     # distância máxima de cromaticidade até a cor-chave
SOMA_MIN = 60        # r + g + b mínimo (o fundo é preto)
EROSAO = 2           # px tirados da borda da máscara
ALTURA_MAX = 36      # px (no quadro 1280x720)
LARGURA_MAX = 120
MIN_PX = 40          # área mínima do retângulo
Y_MIN = 0.30         # longe do horizonte (fração da altura)


def classificar(arr: np.ndarray) -> dict[str, np.ndarray]:
    cores, nomes = [], []
    for mat, cs in CHAVES.items():
        for c in cs:
            cores.append(c)
            nomes.append(mat)
    for c in OUTRAS:
        cores.append(c)
        nomes.append("")
    pal = np.array(cores, dtype=np.float32)
    pal = pal / pal.sum(axis=1, keepdims=True)
    p = arr.reshape(-1, 3).astype(np.float32)
    soma = p.sum(axis=1)
    c = p / np.maximum(soma, 1.0)[:, None]
    d = np.linalg.norm(c[:, None, :] - pal[None, :, :], axis=2)
    k = np.argmin(d, axis=1)
    ok = (d[np.arange(len(p)), k] <= CROMA_MAX) & (soma >= SOMA_MIN)
    h, w = arr.shape[:2]
    out = {}
    for mat in CHAVES:
        idx = [i for i, n in enumerate(nomes) if n == mat]
        out[mat] = (np.isin(k, idx) & ok).reshape(h, w)
    return out


def erodir(m: np.ndarray, r: int) -> np.ndarray:
    out = m.copy()
    for _ in range(r):
        e = out.copy()
        e[1:, :] &= out[:-1, :]
        e[:-1, :] &= out[1:, :]
        e[:, 1:] &= out[:, :-1]
        e[:, :-1] &= out[:, 1:]
        out = e
    return out


def maior_retangulo(m: np.ndarray) -> tuple[int, int, int, int] | None:
    """Maior retângulo (área, limitado a ALTURA_MAX x LARGURA_MAX) só com True; (x0, y0, x1, y1) exclusivo.
    Procura numa grade 2x mais grossa (bloco só vale se os 4 pixels valem) e dentro da caixa da máscara."""
    if not m.any():
        return None
    ys, xs = np.nonzero(m)
    oy, ox = ys.min() & ~1, xs.min() & ~1
    sub = m[oy:ys.max() + 2, ox:xs.max() + 2]
    sub = sub[: sub.shape[0] // 2 * 2, : sub.shape[1] // 2 * 2]
    g = sub[0::2, 0::2] & sub[1::2, 0::2] & sub[0::2, 1::2] & sub[1::2, 1::2]
    r = _maior(g, ALTURA_MAX // 2, LARGURA_MAX // 2, MIN_PX // 4)
    if r is None:
        return None
    x0, y0, x1, y1 = r
    return (ox + 2 * x0, oy + 2 * y0, ox + 2 * x1, oy + 2 * y1)


def _maior(m: np.ndarray, hmax: int, wmax: int, amin: int) -> tuple[int, int, int, int] | None:
    h, w = m.shape
    alt = np.zeros(w, dtype=np.int32)
    melhor, ret = 0, None
    for y in range(h):
        if not m[y].any():
            alt[:] = 0
            continue
        alt = np.where(m[y], np.minimum(alt + 1, hmax), 0)
        # maior retângulo no histograma (pilha), largura limitada
        pilha: list[int] = []
        for x in range(w + 1):
            a = alt[x] if x < w else 0
            while pilha and alt[pilha[-1]] >= a:
                hh = alt[pilha.pop()]
                x0 = pilha[-1] + 1 if pilha else 0
                ww = min(x - x0, wmax)
                if hh * ww > melhor:
                    melhor = hh * ww
                    xc = (x0 + x) // 2
                    ret = (xc - ww // 2, y - hh + 1, xc - ww // 2 + ww, y + 1)
            pilha.append(x)
    return ret if melhor >= amin else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ids", required=True, help="pasta com os quadros do --ids (sNNNN.png)")
    ap.add_argument("--normal", help="pasta com os quadros normais dos mesmos s (para tirar a sombra)")
    ap.add_argument("--regioes", default=str(RAIZ / "tools/ref/cores_interlagos.json"))
    ap.add_argument("--gravar", action="store_true")
    a = ap.parse_args()
    cfg = json.loads(Path(a.regioes).read_text(encoding="utf-8"))
    for par in cfg["pares"]:
        s = int(par["s"])
        f = Path(a.ids) / f"s{s:04d}.png"
        if not f.exists():
            print(f"s{s}: sem quadro --ids")
            continue
        arr = np.asarray(Image.open(f).convert("RGB"))
        h, w = arr.shape[:2]
        norm = None
        if a.normal and (Path(a.normal) / f"s{s:04d}.png").exists():
            norm = np.asarray(Image.open(Path(a.normal) / f"s{s:04d}.png").convert("RGB")).astype(np.float32)
        masks = classificar(arr)
        god = par.setdefault("godot", {})
        for mat in CHAVES:
            god.pop(mat, None)
        god.pop("pintura_verde", None)
        achados = []
        for mat, m in masks.items():
            m = erodir(m, EROSAO)
            m[: int(Y_MIN * h)] = False
            if norm is not None and m.sum() > 0:
                lum = norm.mean(axis=2)
                med = float(np.median(lum[m]))
                m &= lum > 0.6 * med  # sombra fora
                m = erodir(m, 1)
            r = maior_retangulo(m)
            if r is None:
                continue
            x0, y0, x1, y1 = r
            god[mat] = [[round(x0 / w, 4), round(y0 / h, 4), round(x1 / w, 4), round(y1 / h, 4)]]
            achados.append(f"{mat} {x1 - x0}x{y1 - y0}px")
        print(f"s{s}: " + (", ".join(achados) if achados else "nenhuma tinta"))
    if a.gravar:
        Path(a.regioes).write_text(json.dumps(cfg, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"gravado em {a.regioes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
