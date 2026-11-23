"""Cor medida por material, LMU × Godot (PLANO-INTERLAGOS-DETALHES.md, Fase 1 — "Cor medida, não no olho").

Lê as regiões marcadas à mão em tools/ref/cores_interlagos.json (retângulos em fração 0–1 da imagem, separados
por lado porque o enquadramento LMU × Godot não é idêntico), amostra cada retângulo com mediana robusta e compara
por material (cada lado = média em luz linear de todas as suas amostras; ΔE por par quando o mesmo s tem os dois): sRGB médio, Lab (D65), ΔE CIEDE2000 (e CIE76), ΔL, Δcroma e Δmatiz. Também mede o contraste de
sombra do asfalto (luminância Y sombra/sol) nos dois lados.

Uso:
  python tools/ref/cores.py                                   # mede com as capturas padrão
  python tools/ref/cores.py --godot build/ref/interlagos/godot/chase_v2   # remede após um ajuste
  python tools/ref/cores.py --grade 600 1000                  # só gera grades de marcação (ajuda a editar o JSON)

Saídas (em --out, padrão build/ref/interlagos/cores):
  relatorio.md, relatorio.json, regioes_sNNNN.jpg (retângulos desenhados e rotulados, para conferência humana),
  paleta.png (LMU × Godot por material, amostra a amostra).
Sinal das diferenças: sempre Godot − LMU (ΔL > 0 = nosso mais claro; Δcroma > 0 = nosso mais saturado;
Δmatiz > 0 = nosso matiz girado no sentido anti-horário a*→b*, p.ex. vermelho→amarelo→verde).
Código de saída 0 sempre (é uma ferramenta de medição; a tabela marca OK/FORA contra --meta).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parents[2]
EXT = (".jpg", ".png", ".jpeg")

# Ordem de exibição e cor do contorno nas imagens de conferência.
MATERIAIS = {
    "asfalto": (255, 255, 255),
    "sombra_asfalto": (40, 40, 40),
    "grama": (60, 255, 60),
    "zebra_amarelo": (255, 230, 0),
    "zebra_verde": (0, 160, 0),
    "zebra_branco": (0, 200, 255),
    "pintura_verde_escape": (0, 255, 200),   # verde-azulado dos escapes (Reta Oposta)
    "pintura_verde_zebra": (120, 255, 0),    # verde vivo logo atrás da zebra
    "pintura_vermelha": (255, 0, 255),
    "linha_branca": (255, 140, 0),
    "ceu": (0, 90, 255),
}
DESVIO_SUSPEITO = 14.0   # desvio-padrão sRGB (média dos 3 canais) acima disso → região possivelmente contaminada
DESCARTE_SUSPEITO = 0.30  # fração de pixels descartada como outlier acima disso → idem


# ---------------------------------------------------------------- cor
def srgb_para_linear(c: np.ndarray) -> np.ndarray:
    c = np.asarray(c, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_para_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, 1.0)
    return 255.0 * np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


M_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
BRANCO_D65 = np.array([0.95047, 1.0, 1.08883])


def luminancia(rgb255) -> float:
    """Luminância relativa Y (linear, 0–1)."""
    return float(srgb_para_linear(rgb255) @ M_XYZ[1])


def srgb_para_lab(rgb255) -> np.ndarray:
    xyz = M_XYZ @ srgb_para_linear(rgb255) / BRANCO_D65
    e, k = 216 / 24389, 24389 / 27
    f = np.where(xyz > e, np.cbrt(xyz), (k * xyz + 16) / 116)
    return np.array([116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])])


def croma_matiz(lab) -> tuple[float, float]:
    c = math.hypot(lab[1], lab[2])
    h = math.degrees(math.atan2(lab[2], lab[1])) % 360
    return c, h


def de76(a, b) -> float:
    return float(np.linalg.norm(np.asarray(a) - np.asarray(b)))


def de2000(lab1, lab2) -> float:
    """CIEDE2000 (Sharma, Wu & Dalal 2005), kL = kC = kH = 1."""
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if C1p else 0.0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if C2p else 0.0
    dLp = L2 - L1
    dCp = C2p - C1p
    if C1p * C2p == 0:
        dhp = 0.0
    else:
        dhp = h2p - h1p
        if dhp > 180:
            dhp -= 360
        elif dhp < -180:
            dhp += 360
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp / 2))
    Lpm = (L1 + L2) / 2
    Cpm = (C1p + C2p) / 2
    if C1p * C2p == 0:
        hpm = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hpm = (h1p + h2p) / 2
    elif h1p + h2p < 360:
        hpm = (h1p + h2p + 360) / 2
    else:
        hpm = (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hpm - 30)) + 0.24 * math.cos(math.radians(2 * hpm))
         + 0.32 * math.cos(math.radians(3 * hpm + 6)) - 0.20 * math.cos(math.radians(4 * hpm - 63)))
    dtheta = 30 * math.exp(-(((hpm - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(Cpm ** 7 / (Cpm ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lpm - 50) ** 2 / math.sqrt(20 + (Lpm - 50) ** 2)
    Sc = 1 + 0.045 * Cpm
    Sh = 1 + 0.015 * Cpm * T
    Rt = -math.sin(math.radians(2 * dtheta)) * Rc
    return math.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))


def comparar(lab_lmu, lab_god) -> dict:
    c1, h1 = croma_matiz(lab_lmu)
    c2, h2 = croma_matiz(lab_god)
    dh = (h2 - h1 + 180) % 360 - 180
    return {
        "dE2000": round(de2000(lab_lmu, lab_god), 2),
        "dE76": round(de76(lab_lmu, lab_god), 2),
        "dL": round(float(lab_god[0] - lab_lmu[0]), 2),
        "dCroma": round(c2 - c1, 2),
        "dMatiz_graus": round(dh, 1),
        "matiz_confiavel": bool(min(c1, c2) >= 5.0),  # abaixo de croma 5 o matiz é quase ruído
    }


# ---------------------------------------------------------------- amostragem
def achar(pasta: Path, s: int) -> Path | None:
    for ext in EXT:
        p = pasta / f"s{s:04d}{ext}"
        if p.exists():
            return p
    return None


def px(ret, w, h) -> tuple[int, int, int, int]:
    x0, y0, x1, y1 = ret
    return (round(min(x0, x1) * w), round(min(y0, y1) * h), round(max(x0, x1) * w), round(max(y0, y1) * h))


def amostrar(arr: np.ndarray, rets: list) -> dict | None:
    """Mediana robusta dos pixels de um ou mais retângulos (fração 0–1).

    1) mediana por canal; 2) distância de cada pixel à mediana; 3) descarta quem passa de 3·σ_MAD (mín. 6 níveis);
    4) cor = mediana por canal dos que sobraram; desvio = σ médio dos 3 canais dos que sobraram.
    """
    h, w = arr.shape[:2]
    blocos = []
    for r in rets:
        x0, y0, x1, y1 = px(r, w, h)
        if x1 - x0 < 2 or y1 - y0 < 2:
            continue
        blocos.append(arr[y0:y1, x0:x1].reshape(-1, 3))
    if not blocos:
        return None
    p = np.concatenate(blocos).astype(np.float64)
    med = np.median(p, axis=0)
    d = np.linalg.norm(p - med, axis=1)
    lim = max(3.0 * 1.4826 * float(np.median(d)), 6.0)
    ok = p[d <= lim]
    if len(ok) < 10:
        ok = p
    cor = np.median(ok, axis=0)
    desvio = float(np.mean(np.std(ok, axis=0)))
    descarte = 1.0 - len(ok) / len(p)
    return {
        "srgb": [round(float(v), 1) for v in cor],
        "desvio": round(desvio, 1),
        "descarte": round(descarte, 3),
        "n_px": int(len(p)),
        "suspeita": bool(desvio > DESVIO_SUSPEITO or descarte > DESCARTE_SUSPEITO),
    }


def media_linear(cores: list[list[float]]) -> np.ndarray:
    """Média das amostras em luz linear (fisicamente correta), devolvida em sRGB 0–255."""
    return linear_para_srgb(np.mean([srgb_para_linear(c) for c in cores], axis=0))


# ---------------------------------------------------------------- pista (rumo para a análise de sombra)
def rumo_pista(track_json: Path, s: float) -> float | None:
    """Rumo da pista no metro s, em graus no mundo Godot: 0 = −Z, 90 = +X (sentido horário visto de cima)."""
    try:
        t = json.loads(track_json.read_text(encoding="utf-8"))
        st, passo, n = int(t["stride"]), float(t["step"]), int(t["n"])
        i = int(round(s / passo)) % n
        o = i * st
        tx, tz = t["s"][o + 3], t["s"][o + 5]
        return round(math.degrees(math.atan2(tx, -tz)) % 360, 1)
    except (OSError, ValueError, KeyError, IndexError):
        return None


# ---------------------------------------------------------------- desenho
def fonte(tam: int) -> ImageFont.ImageFont:
    for nome in ("arialbd.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(nome, tam)
        except OSError:
            pass
    return ImageFont.load_default()


def desenhar_regioes(im: Image.Image, regioes: dict, amostras: dict, titulo: str) -> Image.Image:
    im = im.convert("RGB").copy()
    dr = ImageDraw.Draw(im)
    f = fonte(15)
    w, h = im.size
    for mat, rets in regioes.items():
        cor = MATERIAIS.get(mat, (255, 0, 0))
        am = amostras.get(mat)
        for k, r in enumerate(rets):
            x0, y0, x1, y1 = px(r, w, h)
            dr.rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), outline=(0, 0, 0), width=1)
            dr.rectangle((x0, y0, x1, y1), outline=cor, width=2)
            if k == 0:
                rot = mat + (f" σ{am['desvio']:.0f}" if am else "") + (" ?" if am and am["suspeita"] else "")
                tx, ty = x0 + 2, max(0, y0 - 18)
                bb = dr.textbbox((tx, ty), rot, font=f)
                dr.rectangle(bb, fill=(0, 0, 0))
                dr.text((tx, ty), rot, font=f, fill=cor)
    dr.rectangle((0, 0, 220, 26), fill=(0, 0, 0))
    dr.text((6, 4), titulo, font=fonte(18), fill=(255, 255, 255))
    return im


def grade(im: Image.Image, titulo: str) -> Image.Image:
    """Imagem com grade a cada 0,05 (rótulo a cada 0,1) para marcar retângulos no JSON."""
    im = im.convert("RGB").copy()
    dr = ImageDraw.Draw(im)
    w, h = im.size
    f = fonte(14)
    for i in range(1, 20):
        forte = i % 2 == 0
        cor = (255, 0, 255) if forte else (0, 255, 255)
        x, y = round(i * w / 20), round(i * h / 20)
        dr.line((x, 0, x, h), fill=cor, width=1)
        dr.line((0, y, w, y), fill=cor, width=1)
        if forte:
            dr.text((x + 2, 2), f"{i / 20:.1f}", font=f, fill=(255, 255, 0))
            dr.text((2, y + 1), f"{i / 20:.1f}", font=f, fill=(255, 255, 0))
    dr.text((w // 2 - 60, h - 20), titulo, font=fonte(16), fill=(255, 255, 0))
    return im


def lado_a_lado(a: Image.Image, b: Image.Image) -> Image.Image:
    w, h = a.size
    if b.size != (w, h):
        b = b.resize((w, h), Image.LANCZOS)
    out = Image.new("RGB", (w * 2 + 8, h), (24, 24, 28))
    out.paste(a, (0, 0))
    out.paste(b, (w + 8, 0))
    return out


def paleta(por_mat: dict, destino: Path) -> None:
    """Uma linha por material: média LMU | média Godot, depois as amostras de cada lado (LMU em cima, Godot embaixo)."""
    lin = [m for m in MATERIAIS if m in por_mat]
    if not lin:
        return
    q, rot = 56, 230
    maxn = max(max(len(por_mat[m]["amostras"]["lmu"]), len(por_mat[m]["amostras"]["godot"])) for m in lin)
    W = rot + 2 * q + 24 + maxn * (q + 4)
    H = 30 + len(lin) * (q + 26)
    img = Image.new("RGB", (W, H), (30, 30, 34))
    dr = ImageDraw.Draw(img)
    f, fp = fonte(16), fonte(12)
    dr.text((8, 6), "material      média LMU | Godot      amostras: LMU em cima, Godot embaixo (rótulo = s)", font=f,
            fill=(230, 230, 230))
    for i, m in enumerate(lin):
        d = por_mat[m]
        y = 30 + i * (q + 26)
        dr.text((8, y + q // 2 - 18), m, font=f, fill=(255, 255, 255))
        dr.text((8, y + q // 2 + 2), f"ΔE00 {d['dE2000']:.1f}  n={d['n_lmu']}/{d['n_godot']}", font=fp,
                fill=(200, 200, 200))
        x = rot
        dr.rectangle((x, y, x + q, y + q), fill=tuple(round(v) for v in d["lmu_srgb"]))
        dr.rectangle((x + q, y, x + 2 * q, y + q), fill=tuple(round(v) for v in d["godot_srgb"]))
        x0 = x + 2 * q + 24
        for k, lado in enumerate(("lmu", "godot")):
            for j, a in enumerate(d["amostras"][lado]):
                xx = x0 + j * (q + 4)
                yy = y + k * (q // 2)
                dr.rectangle((xx, yy, xx + q, yy + q // 2 - 1), fill=tuple(round(v) for v in a["srgb"]))
                dr.text((xx + 2, yy + 2), f"{a['s']}", font=fp, fill=(0, 0, 0))
    img.save(destino)


# ---------------------------------------------------------------- principal
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--regioes", default=str(RAIZ / "tools/ref/cores_interlagos.json"))
    ap.add_argument("--lmu", default=str(RAIZ / "build/ref/interlagos/chase"))
    ap.add_argument("--godot", default=str(RAIZ / "build/ref/interlagos/godot/chase"),
                    help="pasta com as capturas do Godot (sNNNN.png) — troque para remedir após cada ajuste")
    ap.add_argument("--out", default=str(RAIZ / "build/ref/interlagos/cores"))
    ap.add_argument("--meta", type=float, default=8.0, help="ΔE2000 máximo por material (padrão 8)")
    ap.add_argument("--track", default=str(RAIZ / "data/track/track.json"))
    ap.add_argument("--grade", type=int, nargs="*", metavar="S",
                    help="só gera grade_sNNNN.jpg (LMU|Godot com grade 0,05) para marcar regiões, e sai")
    a = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

    lmu_dir, god_dir, out = Path(a.lmu), Path(a.godot), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    if a.grade is not None:
        for s in a.grade:
            pl, pg = achar(lmu_dir, s), achar(god_dir, s)
            if pl is None or pg is None:
                print(f"aviso: s={s:04d} sem par")
                continue
            with Image.open(pl) as il, Image.open(pg) as ig:
                img = lado_a_lado(grade(il, f"LMU s{s}"), grade(ig.resize(il.size), f"Godot s{s}"))
            img.save(out / f"grade_s{s:04d}.jpg", quality=90)
            print(out / f"grade_s{s:04d}.jpg")
        return 0

    try:
        cfg = json.loads(Path(a.regioes).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"erro lendo regiões {a.regioes}: {e}", file=sys.stderr)
        return 0

    # Cada lado é agregado com TODAS as suas amostras (a cor de um material não depende do metro; o enquadramento
    # LMU × Godot não é idêntico, então nem todo material aparece nos dois lados no mesmo s). O ΔE por par só sai
    # quando o material aparece nos dois lados do mesmo s.
    amostras: dict[str, dict[str, list]] = {}
    razoes: dict[str, list] = {"lmu": [], "godot": []}
    obs_sombra: list[dict] = []
    for par in cfg.get("pares", []):
        s = int(par["s"])
        pl, pg = achar(lmu_dir, s), achar(god_dir, s)
        if pl is None or pg is None:
            print(f"aviso: s={s:04d} sem {'LMU' if pl is None else 'Godot'}, pulando")
            continue
        with Image.open(pl) as il, Image.open(pg) as ig:
            il, ig = il.convert("RGB"), ig.convert("RGB")
            res = {"lmu": {}, "godot": {}}
            for lado, arr in (("lmu", np.asarray(il)), ("godot", np.asarray(ig))):
                for mat, rets in par.get(lado, {}).items():
                    r = amostrar(arr, rets)
                    if r:
                        res[lado][mat] = r
                        amostras.setdefault(mat, {"lmu": [], "godot": []})[lado].append({"s": s, **r})
                if "asfalto" in res[lado] and "sombra_asfalto" in res[lado]:
                    razoes[lado].append({"s": s, "razao": round(luminancia(res[lado]["sombra_asfalto"]["srgb"])
                                                               / luminancia(res[lado]["asfalto"]["srgb"]), 3)})
            if "sombra_obs" in par:
                obs_sombra.append({"s": s, "rumo_pista_graus": rumo_pista(Path(a.track), s), **par["sombra_obs"]})
            img = lado_a_lado(desenhar_regioes(il, par.get("lmu", {}), res["lmu"], f"LMU s{s}"),
                              desenhar_regioes(ig, par.get("godot", {}), res["godot"], f"Godot s{s}"))
            img.save(out / f"regioes_s{s:04d}.jpg", quality=90)

    por_mat: dict[str, dict] = {}
    for mat in MATERIAIS:
        am = amostras.get(mat)
        if not am or not am["lmu"] or not am["godot"]:
            if am:
                print(f"aviso: {mat} só tem amostras de um lado, fora da comparação")
            continue
        cl = media_linear([x["srgb"] for x in am["lmu"]])
        cg = media_linear([x["srgb"] for x in am["godot"]])
        ll, lg = srgb_para_lab(cl), srgb_para_lab(cg)
        gs = {x["s"]: x for x in am["godot"]}
        pares_mesmo_s = [{"s": x["s"], "dE2000": round(de2000(srgb_para_lab(x["srgb"]),
                                                               srgb_para_lab(gs[x["s"]]["srgb"])), 2)}
                         for x in am["lmu"] if x["s"] in gs]
        d = comparar(ll, lg)
        por_mat[mat] = {
            "lmu_srgb": [round(float(v), 1) for v in cl], "godot_srgb": [round(float(v), 1) for v in cg],
            "lmu_lab": [round(float(v), 2) for v in ll], "godot_lab": [round(float(v), 2) for v in lg],
            "lmu_croma_matiz": [round(v, 2) for v in croma_matiz(ll)],
            "godot_croma_matiz": [round(v, 2) for v in croma_matiz(lg)],
            **d,
            "ok": d["dE2000"] <= a.meta,
            "n_lmu": len(am["lmu"]), "n_godot": len(am["godot"]),
            # espalhamento entre trechos: ΔE2000 de cada amostra até a média do próprio lado (máximo)
            "espalhamento_lmu": round(max(de2000(srgb_para_lab(x["srgb"]), ll) for x in am["lmu"]), 1),
            "espalhamento_godot": round(max(de2000(srgb_para_lab(x["srgb"]), lg) for x in am["godot"]), 1),
            "suspeitas": [f"s{x['s']}:{l}" for l in ("lmu", "godot") for x in am[l] if x["suspeita"]],
            "amostras": am,
            "pares_mesmo_s": pares_mesmo_s,
        }

    contraste = None
    if razoes["lmu"] and razoes["godot"]:
        contraste = {l: round(float(np.mean([x["razao"] for x in razoes[l]])), 3) for l in ("lmu", "godot")}

    if not por_mat:
        print("nenhum material medido (pastas/quadros conferem?) — relatório anterior mantido", file=sys.stderr)
        return 0

    # ---- terminal
    cab = (f"{'material':<17}{'sRGB LMU':>14}{'sRGB Godot':>14}{'ΔE00':>7}{'ΔE76':>7}{'ΔL':>7}{'ΔC':>7}{'Δh°':>7}"
           f"{'n L/G':>7}{'esp L/G':>10}  meta")
    print(cab)
    print("-" * len(cab))
    linhas_md = []
    for mat, d in por_mat.items():
        fl = "/".join(f"{v:.0f}" for v in d["lmu_srgb"])
        fg = "/".join(f"{v:.0f}" for v in d["godot_srgb"])
        dh = f"{d['dMatiz_graus']:+.0f}" + ("" if d["matiz_confiavel"] else "*")
        st = "OK" if d["ok"] else "FORA"
        n = f"{d['n_lmu']}/{d['n_godot']}"
        esp = f"{d['espalhamento_lmu']:.0f}/{d['espalhamento_godot']:.0f}"
        print(f"{mat:<17}{fl:>14}{fg:>14}{d['dE2000']:>7.1f}{d['dE76']:>7.1f}{d['dL']:>+7.1f}{d['dCroma']:>+7.1f}"
              f"{dh:>7}{n:>7}{esp:>10}  {st}" + ("  (suspeita: " + ", ".join(d["suspeitas"]) + ")"
                                                 if d["suspeitas"] else ""))
        linhas_md.append(f"| {mat} | {fl} | {fg} | {d['dE2000']:.1f} | {d['dE76']:.1f} | {d['dL']:+.1f} | "
                         f"{d['dCroma']:+.1f} | {dh} | {n} | {esp} | {st} |")
    print("* matiz pouco confiável (croma < 5 em um dos lados)   esp = maior ΔE00 de uma amostra até a média do lado")
    if contraste:
        print(f"contraste de sombra do asfalto (Y sombra/sol): LMU {contraste['lmu']:.2f} ({len(razoes['lmu'])} quadros)"
              f"  Godot {contraste['godot']:.2f} ({len(razoes['godot'])} quadros)")

    # ---- relatório
    md = [
        "# Cor por material — LMU × Godot (Interlagos)",
        "",
        f"Capturas Godot: `{god_dir.as_posix()}` · regiões: `{Path(a.regioes).name}` · meta ΔE2000 ≤ {a.meta:g}",
        "",
        "Diferenças = Godot − LMU. ΔL > 0: nosso mais claro. ΔC > 0: nosso mais saturado. Δh em graus no plano a*b* "
        "(* = croma < 5, matiz pouco confiável). Cada lado é a média, em luz linear, de todas as suas amostras "
        "(n L/G). esp = maior ΔE00 de uma amostra até a média do próprio lado (variação entre trechos).",
        "",
        "| material | sRGB LMU | sRGB Godot | ΔE00 | ΔE76 | ΔL | ΔC | Δh° | n L/G | esp L/G | meta |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
        *linhas_md,
        "",
    ]
    if contraste:
        md += ["## Contraste de sombra do asfalto (Y sombra / Y sol, mesmo quadro)", "",
               "| lado | quadros (s: razão) | média |", "|---|---|---|",
               *[f"| {l} | " + ", ".join(f"{x['s']}: {x['razao']:.2f}" for x in razoes[l])
                 + f" | **{contraste[l]:.2f}** |" for l in ("lmu", "godot")], ""]
    if obs_sombra:
        md += ["## Direção da sombra do carro (observada nos quadros)", "",
               "Rumo da pista: graus no mundo Godot, 0 = −Z, 90 = +X (horário visto de cima).", "",
               "| s | rumo pista | LMU | Godot |", "|---|---|---|---|",
               *[f"| {o['s']} | {o['rumo_pista_graus']} | {o.get('lmu', '')} | {o.get('godot', '')} |"
                 for o in obs_sombra], ""]
    md += ["## Amostras (sRGB, σ = desvio dentro da região, ? = suspeita)", ""]
    for mat, d in por_mat.items():
        for l in ("lmu", "godot"):
            md.append(f"**{mat} · {l}** — " + "; ".join(
                f"s{x['s']}: {'/'.join(f'{v:.0f}' for v in x['srgb'])} σ{x['desvio']:.0f}"
                + (" ?" if x["suspeita"] else "") for x in d["amostras"][l]))
            md.append("")
        if d["pares_mesmo_s"]:
            md.append(f"**{mat} · ΔE00 no mesmo s** — " + "; ".join(
                f"s{x['s']}: {x['dE2000']:.1f}" for x in d["pares_mesmo_s"]))
            md.append("")
    (out / "relatorio.md").write_text("\n".join(md), encoding="utf-8")
    (out / "relatorio.json").write_text(json.dumps({
        "godot": god_dir.as_posix(), "lmu": lmu_dir.as_posix(), "meta_dE2000": a.meta,
        "materiais": por_mat, "contraste_sombra": {"quadros": razoes, "media": contraste},
        "direcao_sombra": obs_sombra,
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    paleta(por_mat, out / "paleta.png")
    print(f"saídas em {out}")
    return 0


if __name__ == "__main__":
    main()
    sys.exit(0)
