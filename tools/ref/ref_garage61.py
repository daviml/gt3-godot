# -*- coding: utf-8 -*-
"""
Converte voltas do Garage 61 (CSV do iRacing, 60 Hz) para o s do jogo (0..4294, sentido e linha do
`data/track/track.json`), no mesmo formato de `data/reference/interlagos-r8.json` (passo 2 m).

Reimplementação em Python de `tools/referencia.ts` + `gt3-time-attack/scripts/ref-lib.ts`:
  1) lat/lon -> x/z do jogo (origem do data/tracks/interlagos.json do web: -23.7036, -46.6997);
  2) o GPS do iRacing não bate com o OSM (até ~40 m): ajusta rotação + escala + translação para a volta caber
     na largura da pista do jogo. Aqui o ajuste é ÚNICO para todas as voltas passadas (mesmo sistema de
     coordenadas do iRacing), como o `fitLaps` do web;
  3) projeta cada amostra na linha central (s, d) e reamostra a cada amostra da pista (2 m).

Uso (na raiz do repo):
  python tools/ref/ref_garage61.py                 # todas as voltas de Interlagos em garage61/
Saída: build/ref/interlagos/ref_<carro>.json (+ ajuste_gps.json). Não toca em data/ nem no jogo.
"""
import csv
import glob
import json
import math
import os
import re
import sys

import numpy as np

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TRACK = os.path.join(RAIZ, "data", "track", "track.json")
SAIDA = os.path.join(RAIZ, "build", "ref", "interlagos")
ORIGEM = (-23.7036, -46.6997)  # data/tracks/interlagos.json (gt3-time-attack)
HZ = 60.0

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


class Pista:
    def __init__(self):
        j = json.load(open(TRACK, encoding="utf-8"))
        st = int(j["stride"])
        a = np.asarray(j["s"], np.float64).reshape(-1, st)
        self.L = float(j["length"])
        self.passo = float(j["step"])
        self.P = a[:, [0, 2]]
        t = a[:, [3, 5]]
        self.T = t / np.linalg.norm(t, axis=1, keepdims=True)
        r = a[:, [6, 7]]
        self.R = r / np.linalg.norm(r, axis=1, keepdims=True)
        self.wl, self.wr = a[:, 8], a[:, 9]
        self.s = np.arange(len(a)) * self.passo

    def localiza(self, xz):
        """Amostra mais próxima -> (s, d, índice)."""
        out_k = np.empty(len(xz), np.int64)
        for i in range(0, len(xz), 2000):
            b = xz[i:i + 2000]
            d2 = ((b[:, None, :] - self.P[None, :, :]) ** 2).sum(-1)
            out_k[i:i + len(b)] = np.argmin(d2, 1)
        k = out_k
        rel = xz - self.P[k]
        s = self.s[k] + (rel * self.T[k]).sum(1)
        d = (rel * self.R[k]).sum(1)
        return s, d, k

    def fora(self, xz):
        _, d, k = self.localiza(xz)
        lim = np.where(d > 0, self.wr[k], self.wl[k])
        o = np.abs(d) - lim
        return float(np.sum(np.where(o > 0, o * o, 0.0)))


def le_volta(arq):
    with open(arq, encoding="utf-8") as f:
        linhas = list(csv.DictReader(f))
    col = lambda n: np.array([float(r[n]) for r in linhas])
    mlat = 111320.0
    mlon = 111320.0 * math.cos(math.radians(ORIGEM[0]))
    x = (col("Lon") - ORIGEM[1]) * mlon
    z = -(col("Lat") - ORIGEM[0]) * mlat
    for i in range(1, len(x) - 1):  # GPS com salto isolado
        mx, mz = (x[i - 1] + x[i + 1]) / 2, (z[i - 1] + z[i + 1]) / 2
        passo = math.hypot(x[i + 1] - x[i - 1], z[i + 1] - z[i - 1])
        if math.hypot(x[i] - mx, z[i] - mz) > 2 + passo:
            x[i], z[i] = mx, mz
    return {"x": x, "z": z, "v": col("Speed"), "thr": col("Throttle"), "brk": col("Brake"),
            "gear": col("Gear"), "rpm": col("RPM"), "yaw_rate": col("YawRate"), "lat_a": col("LatAccel"),
            "long_a": col("LongAccel"), "pct": col("LapDistPct")}


def aplica(f, x, z):
    c, s = math.cos(f["th"]), math.sin(f["th"])
    X, Z = (x - f["cx"]) * f["s"], (z - f["cz"]) * f["s"]
    return np.stack([f["cx"] + c * X - s * Z + f["dx"], f["cz"] + s * X + c * Z + f["dz"]], 1)


def ajusta(pista, voltas):
    x = np.concatenate([v["x"][::3] for v in voltas])
    z = np.concatenate([v["z"][::3] for v in voltas])
    f = {"th": 0.0, "s": 1.0, "dx": 0.0, "dz": 0.0, "cx": float(x.mean()), "cz": float(z.mean())}
    melhor = None
    for dx in range(-48, 49, 8):
        for dz in range(-48, 49, 8):
            c = dict(f, dx=float(dx), dz=float(dz))
            e = pista.fora(aplica(c, x[::4], z[::4]))
            if melhor is None or e < melhor[0]:
                melhor = (e, c)
    f = melhor[1]
    e = pista.fora(aplica(f, x, z))
    for passo in (8, 4, 2, 1, 0.5, 0.25):
        melhorou = True
        while melhorou:
            melhorou = False
            for k, d in (("dx", passo), ("dx", -passo), ("dz", passo), ("dz", -passo), ("th", passo * 0.002),
                         ("th", -passo * 0.002), ("s", passo * 0.002), ("s", -passo * 0.002)):
                c = dict(f)
                c[k] += d
                ec = pista.fora(aplica(c, x, z))
                if ec < e:
                    e, f, melhorou = ec, c, True
    return f, e


def converte(pista, volta, f, rotulo):
    xz = aplica(f, volta["x"], volta["z"])
    s, d, _ = pista.localiza(xz)
    # s contínuo (desenrola a passagem pela linha)
    off = 0.0
    sc = np.empty_like(s)
    for i in range(len(s)):
        v = s[i] + off
        if i and v < sc[i - 1] - pista.L / 2:
            off += pista.L
            v += pista.L
        sc[i] = v
    # força monotonicidade (ruído do GPS em baixa velocidade)
    sc = np.maximum.accumulate(sc)
    n = len(sc)
    lap = n / HZ
    out = {"label": rotulo, "lapTime": round(lap, 3), "step": pista.passo,
           "d": [], "v": [], "t": [], "throttle": [], "brake": [], "gear": [], "rpm": [], "yawRate": []}
    idx = np.arange(n, dtype=np.float64)
    alvo = pista.s.copy()
    alvo = np.where(alvo < sc[0], alvo + pista.L, alvo)
    alvo = np.where(alvo > sc[-1], alvo - pista.L, alvo)
    # sc pode ter platôs: usa interpolação em índice
    sc_u, iu = np.unique(sc, return_index=True)
    j = np.interp(alvo, sc_u, idx[iu])
    li = lambda a: np.interp(j, idx, a)
    out["d"] = np.round(li(d), 2).tolist()
    out["v"] = np.round(li(volta["v"]), 2).tolist()
    t = j / HZ
    out["t"] = np.round(np.where(t >= lap, t - lap, t), 3).tolist()
    out["throttle"] = np.round(li(volta["thr"]), 3).tolist()
    out["brake"] = np.round(li(volta["brk"]), 3).tolist()
    out["gear"] = [int(volta["gear"][int(round(x))]) for x in j]
    out["rpm"] = np.round(li(volta["rpm"])).astype(int).tolist()
    out["yawRate"] = np.round(li(volta["yaw_rate"]), 4).tolist()
    info = {"s_inicio_volta": round(float(sc[0]), 1), "s_fim_volta": round(float(sc[-1]), 1),
            "d_rms": round(float(np.sqrt(np.mean(d ** 2))), 2),
            "fora_da_pista_amostras": int(np.sum(np.abs(d) > np.maximum(pista.wl, pista.wr).max()))}
    return out, info


def slug(nome):
    m = re.search(r"Garage 61 - (.+?) - (.+?) - Aut", nome)
    carro = m.group(2) if m else nome
    return re.sub(r"[^a-z0-9]+", "-", carro.lower()).strip("-"), (m.group(1) if m else ""), carro


def main():
    os.makedirs(SAIDA, exist_ok=True)
    arqs = sorted(glob.glob(os.path.join(RAIZ, "garage61", "*Carlos Pace*.csv")))
    if not arqs:
        raise SystemExit("nenhuma volta de Interlagos em garage61/")
    pista = Pista()
    voltas = [le_volta(a) for a in arqs]
    f, e = ajusta(pista, voltas)
    print(f"ajuste do GPS (único p/ {len(voltas)} voltas): th={math.degrees(f['th']):.3f}° esc={f['s']:.4f} "
          f"dx={f['dx']:.2f} dz={f['dz']:.2f} (erro fora da pista {e:.1f})")
    resumo = {"ajuste": f, "voltas": {}}
    for a, v in zip(arqs, voltas):
        sl, piloto, carro = slug(os.path.basename(a))
        tempo = re.search(r"(\d\d\.\d\d\.\d\d\d)", os.path.basename(a))
        rot = f"iRacing — {carro} ({piloto}, {tempo.group(1) if tempo else ''}) [garage61, convertido por ref_garage61.py]"
        out, info = converte(pista, v, f, rot)
        destino = os.path.join(SAIDA, f"ref_{sl}.json")
        with open(destino, "w", encoding="utf-8") as fo:
            json.dump(out, fo, ensure_ascii=False)
        resumo["voltas"][sl] = {"arquivo": os.path.basename(destino), "csv": os.path.basename(a), **info}
        print(f"  {sl}: volta {out['lapTime']:.3f} s, s {info['s_inicio_volta']}..{info['s_fim_volta']}, "
              f"|d| rms {info['d_rms']} m -> build/ref/interlagos/{os.path.basename(destino)}")
    with open(os.path.join(SAIDA, "ajuste_gps.json"), "w", encoding="utf-8") as fo:
        json.dump(resumo, fo, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
