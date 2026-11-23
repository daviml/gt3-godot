"""Inverte a cadeia albedo → tela das tintas (PLANO-INTERLAGOS-DETALHES.md, Fase 1).

Com a luz de Interlagos (sol 3,4 × exposição 1,3 → AgX → saturação 1,2), uma tinta clara e saturada usada como albedo
estoura e desbota na tela (vermelho → salmão, amarelo → creme). Em vez de tentar às cegas, este script acha o albedo
que dá na tela o sRGB medido no LMU: renderiza retalhos de teste no chão da pista (scripts/tests/calib_tinta.gd, mesmo
material das tintas, mesma câmera do --atlas) e faz Newton por tinta, com a jacobiana medida por diferenças finitas.

Uso:
  python tools/ref/calib_tinta.py                       # alvos padrão (medianas do LMU, tools/ref/cores.py)
  python tools/ref/calib_tinta.py --quality 0 --iter 3  # outro preset
  python tools/ref/calib_tinta.py --corrigir build/ref/interlagos/cores/<pasta>/relatorio.json --albedo <json>
      # segunda passada: parte dos albedos dados e corrige pela diferença medida nas capturas reais (tinta com
      # desgaste e textura), usando a jacobiana dos retalhos
Saída: tabela albedo → tela → ΔE00 e build/ref/interlagos/calib/albedos.json.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cores import de2000, srgb_para_lab  # noqa: E402

RAIZ = Path(__file__).resolve().parents[2]
GODOT = r"C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe"
PASTA = RAIZ / "build/ref/interlagos/calib"

# sRGB medido no LMU (média em luz linear das amostras, tools/ref/cores.py, 20/11/2026)
ALVOS = {
    "zebra_amarelo": [205, 208, 30],
    "zebra_verde": [42, 151, 39],
    "zebra_branco": [180, 198, 202],
    "linha_branca": [194, 202, 210],
    "pintura_verde_escape": [55, 126, 102],
    "pintura_verde_zebra": [48, 172, 100],
    "pintura_vermelha": [209, 12, 35],
}
PASSO = 10.0


def renderizar(cores: list, quality: int, s_lista: str, nome: str) -> np.ndarray:
    """Cor de tela (sRGB, média dos s) de cada albedo de teste."""
    PASTA.mkdir(parents=True, exist_ok=True)
    ent, sai = PASTA / f"{nome}_in.json", PASTA / f"{nome}_out.json"
    ent.write_text(json.dumps({"cores": [[int(round(v)) for v in c] for c in cores]}), encoding="utf-8")
    cmd = [GODOT, "--path", str(RAIZ), "--script", "res://scripts/tests/calib_tinta.gd", "--", "--track=interlagos",
           f"--in={ent.relative_to(RAIZ).as_posix()}", f"--out={sai.relative_to(RAIZ).as_posix()}",
           f"--quality={quality}", f"--s={s_lista}"]
    subprocess.run(cmd, cwd=RAIZ, capture_output=True, timeout=600)
    med = json.loads(sai.read_text(encoding="utf-8"))["medidas"]
    n = len(cores)
    out = np.zeros((n, 3))
    cnt = np.zeros(n)
    # as medidas vêm na ordem das cores, repetidas para cada s
    for k, m in enumerate(med):
        out[k % n] += m["out"]
        cnt[k % n] += 1
    return out / cnt[:, None]


def lab_jac(c: np.ndarray) -> np.ndarray:
    """dLab/dsRGB numérico em c."""
    J = np.zeros((3, 3))
    for i in range(3):
        d = np.zeros(3)
        d[i] = 1.0
        J[:, i] = (srgb_para_lab(np.clip(c + d, 0, 255)) - srgb_para_lab(np.clip(c - d, 0, 255))) / 2.0
    return J


def passo_newton(a: np.ndarray, J: np.ndarray, f0: np.ndarray, alvo: np.ndarray) -> np.ndarray:
    """Um passo de Newton em Lab (ΔE é medido em Lab), com conjunto ativo: canal de albedo encostado em 0 (ou 255)
    que pediria para passar do limite sai da conta e o passo é refeito com os outros (ex.: o azul do amarelo, que a
    luz não deixa chegar a 30 na tela)."""
    Jl = lab_jac(f0) @ J
    r = srgb_para_lab(alvo) - srgb_para_lab(f0)
    livres = [0, 1, 2]
    for _ in range(3):
        p = np.zeros(3)
        p[livres] = np.linalg.lstsq(Jl[:, livres], r, rcond=None)[0]
        presos = [c for c in livres if (a[c] <= 0.5 and p[c] < 0) or (a[c] >= 254.5 and p[c] > 0)]
        if not presos:
            break
        livres = [c for c in livres if c not in presos]
        if not livres:
            return a
    p = np.clip(p, -40, 40)
    return np.clip(a + 0.8 * p, 0, 255)


def de(a, b) -> float:
    return de2000(srgb_para_lab(a), srgb_para_lab(b))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quality", type=int, default=2)
    ap.add_argument("--s", default="900,1650,3400")
    ap.add_argument("--iter", type=int, default=4)
    ap.add_argument("--albedo", help="JSON {material: [r, g, b]} de partida (senão: alvo × 0,45)")
    ap.add_argument("--corrigir", help="relatorio.json do cores.py medido com --albedo: corrige pela diferença real")
    ap.add_argument("--saida", default=str(PASTA / "albedos.json"))
    a = ap.parse_args()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

    nomes = list(ALVOS)
    alvo = {k: np.array(v, float) for k, v in ALVOS.items()}
    A = {k: alvo[k] * 0.45 for k in nomes}
    if a.albedo:
        A.update({k: np.array(v, float) for k, v in json.loads(Path(a.albedo).read_text(encoding="utf-8")).items()
                  if k in alvo})
    iters = a.iter
    if a.corrigir:
        # alvo efetivo dos retalhos = alvo + (o que o retalho dá − o que a tinta real deu), por material
        rel = json.loads(Path(a.corrigir).read_text(encoding="utf-8"))["materiais"]
        base = renderizar([A[k] for k in nomes], a.quality, a.s, f"q{a.quality}_base")
        for i, k in enumerate(nomes):
            if k in rel:
                real = np.array(rel[k]["godot_srgb"], float)
                alvo[k] = np.clip(alvo[k] + base[i] - real, 0, 255)
                print(f"{k:<22} retalho {base[i].round()} real {real.round()} → alvo do retalho {alvo[k].round()}")
    for it in range(iters + 1):
        cores = []
        for k in nomes:
            cores.append(A[k])
            for c in range(3):
                d = np.zeros(3)
                d[c] = PASSO if A[k][c] + PASSO <= 255 else -PASSO
                cores.append(np.clip(A[k] + d, 0, 255))
        F = renderizar(cores, a.quality, a.s, f"q{a.quality}_it{it}")
        print(f"--- iteração {it}")
        for i, k in enumerate(nomes):
            f0 = F[4 * i]
            print(f"{k:<22} albedo {A[k].round().astype(int)} → tela {f0.round().astype(int)}  alvo "
                  f"{np.array(ALVOS[k])}  ΔE00 {de(f0, ALVOS[k]):.1f}")
            if it == iters:
                continue
            J = np.zeros((3, 3))
            for c in range(3):
                dc = cores[4 * i + 1 + c][c] - A[k][c]
                J[:, c] = (F[4 * i + 1 + c] - f0) / dc
            A[k] = passo_newton(A[k], J, f0, alvo[k])
    Path(a.saida).write_text(json.dumps({k: [int(round(v)) for v in A[k]] for k in nomes}, indent=1),
                             encoding="utf-8")
    print(f"albedos em {a.saida}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
