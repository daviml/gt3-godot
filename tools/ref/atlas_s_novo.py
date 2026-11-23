# -*- coding: utf-8 -*-
"""
Atlas do vídeo do LMU no s da pista NOVA de Interlagos (Fase 2B, etapa F do PLANO-INTERLAGOS-DETALHES.md).

O atlas da Fase 0 (`build/ref/interlagos/atlas.json`, `chase/`, `onboard/`, feito por atlas_video.py) é indexado pelo
s da pista ANTIGA (4.294 m). Desde a etapa F o jogo e o cenário usam a pista nova (4.308 m) e o
`capture_compare.gd --atlas` fotografa no s novo. Este script não relê o vídeo: leva a tabela t → s de cada câmera
pelo mapa `tools/tracks/interlagos/s_antigo_novo.json` (as mesmas âncoras de velocidade, o mesmo quadro para o mesmo
lugar físico) e reextrai os quadros numa grade do s NOVO:

  build/ref/interlagos/atlas_v2.json     igual ao atlas.json, com `comprimento_pista_m` 4.308, `cameras` na grade do
                                         s novo (cada entrada com `s_antigo`) e `tabela_t_s` no s novo
  build/ref/interlagos/chase_v2/sNNNN.jpg, onboard_v2/sNNNN.jpg
                                         quadros 1280x720; **NNNN = s NOVO** (nas pastas chase/ e onboard/ da Fase 0,
                                         NNNN continua sendo o s antigo). Ex.: o quadro chase/s0350.jpg (antigo) é o
                                         mesmo lugar de chase_v2/s0352.jpg (novo; sNovo(350) = 351,6).

Uso (na raiz do repo):
  python tools/ref/atlas_s_novo.py                       # grade de 10 m (0..4300) nas duas câmeras
  python tools/ref/atlas_s_novo.py --lista 352,382,445   # também esses metros (s novo), além da grade
  python tools/ref/atlas_s_novo.py --sem-quadros         # só o atlas_v2.json

Requer ffmpeg no PATH (o mesmo extrator de atlas_video.py).
"""
import argparse
import json
import os
import sys

import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import atlas_video as AV  # noqa: E402  (extrai_quadros, VIDEO, SAIDA)

RAIZ = os.path.normpath(os.path.join(AQUI, "..", ".."))
MAPA = os.path.join(RAIZ, "tools", "tracks", "interlagos", "s_antigo_novo.json")
ATLAS = os.path.join(AV.SAIDA, "atlas.json")

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def carrega_mapa():
    m = json.load(open(MAPA, encoding="utf-8"))
    L0, L1 = float(m["comprimentoAntigo"]), float(m["comprimentoNovo"])
    xa = np.append(np.array(m["s_antigo"], float), L0)
    xn = np.append(np.maximum(np.array(m["s_novo"], float), 0.0), L1)

    def s_novo(sa):
        sa = np.asarray(sa, float)
        k = np.floor(sa / L0)
        return np.interp(sa - k * L0, xa, xn) + k * L1

    def s_antigo(sn):
        sn = np.asarray(sn, float)
        k = np.floor(sn / L1)
        return np.interp(sn - k * L1, xn, xa) + k * L0

    return L0, L1, s_novo, s_antigo


def main():
    ap = argparse.ArgumentParser(description="atlas do LMU no s da pista nova")
    ap.add_argument("--passo", type=int, default=10)
    ap.add_argument("--lista", default="", help="metros extras (s novo), separados por vírgula")
    ap.add_argument("--sem-quadros", action="store_true")
    a = ap.parse_args()

    atlas = json.load(open(ATLAS, encoding="utf-8"))
    L0, L1, s_novo, s_antigo = carrega_mapa()
    if abs(float(atlas["comprimento_pista_m"]) - L0) > 0.5:
        raise SystemExit(f"atlas.json com comprimento {atlas['comprimento_pista_m']} m, o mapa espera {L0} m (pista antiga)")
    fps = float(atlas["fps"])
    alvos = list(range(0, int(L1), a.passo))
    extras = sorted({int(round(float(x))) for x in a.lista.split(",") if x.strip()})
    alvos = sorted(set(alvos) | set(extras))

    novo = dict(atlas)
    novo["comprimento_pista_m"] = L1
    novo["passo_m"] = a.passo
    novo["s"] = ("s da pista NOVA (data/track/track.json, 4.308 m). Derivado de atlas.json (s antigo, 4.294 m) por "
                 "tools/ref/atlas_s_novo.py com o mapa tools/tracks/interlagos/s_antigo_novo.json: tabela t → s levada "
                 "pelo mapa, quadros reextraídos na grade do s novo (pastas chase_v2/ e onboard_v2/: sNNNN = s novo).")
    tabelas = {}
    cams = {}
    for nome in ("chase", "onboard"):
        tab = np.array(atlas["tabela_t_s"][nome], float)  # [t, s antigo desenrolado]
        t, sa = tab[:, 0], tab[:, 1]
        sn = s_novo(sa)
        tabelas[nome] = [[round(float(x), 1), round(float(y), 2)] for x, y in zip(t, sn)]
        antigos = atlas["cameras"][nome]
        sa_cam = np.array([e["s"] for e in antigos], float)
        lista = []
        ext = []
        for alvo in alvos:
            escolha = None
            for cand in (alvo, alvo + L1, alvo - L1):
                if sn[0] - 0.5 <= cand <= sn[-1] + 0.5:
                    escolha = cand
                    break
            if escolha is None:
                lista.append({"s": alvo, "s_antigo": round(float(s_antigo(alvo)), 2), "t_video": None, "quadro": None,
                              "arquivo": None})
                continue
            # primeiro instante em que a câmera passa por esse s (a tabela é monotônica, com platôs nos congelamentos)
            k = int(np.searchsorted(sn, escolha))
            k = min(max(k, 1), len(sn) - 1)
            tt = t[k - 1] + (t[k] - t[k - 1]) * ((escolha - sn[k - 1]) / max(1e-9, sn[k] - sn[k - 1]))
            q = int(round(tt * fps))
            s_q = float(np.interp(q / fps, t, sn)) - (escolha - alvo)
            sa_alvo = float(s_antigo(alvo))
            # velocidade e marcha da entrada antiga mais próxima (grade de 10 m do s antigo)
            j = int(np.argmin(np.abs(((sa_cam - sa_alvo + L0 / 2) % L0) - L0 / 2)))
            e = {"s": alvo, "s_antigo": round(sa_alvo, 2), "t_video": round(q / fps, 3), "quadro": q,
                 "v_kmh": antigos[j].get("v_kmh"), "marcha": antigos[j].get("marcha"), "s_quadro": round(s_q, 2),
                 "arquivo": f"{nome}_v2/s{alvo:04d}.jpg"}
            obs = antigos[j].get("obs")
            if obs:
                e["obs"] = obs
            if escolha != alvo:
                e["obs"] = (e.get("obs", "") + "; " if e.get("obs") else "") + \
                    "fora da volta gravada: quadro da volta " + ("seguinte" if escolha > alvo else "anterior")
            lista.append(e)
            ext.append((q, f"s{alvo:04d}.jpg"))
        cams[nome] = lista
        if not a.sem_quadros:
            print(f"extraindo {len(ext)} quadros de {nome} → {nome}_v2/ ...", flush=True)
            AV.extrai_quadros(ext, os.path.join(AV.SAIDA, f"{nome}_v2"))
    novo["cameras"] = cams
    novo["tabela_t_s"] = {"passo_s": 0.1, "obs": "[t_video, s NOVO desenrolado: <0 antes da linha, >L depois]", **tabelas}
    # conferência: o s do quadro escolhido × o alvo
    err = [abs(e["s_quadro"] - e["s"]) for c in cams.values() for e in c if e.get("quadro") is not None]
    novo["conferencia_s_quadro_menos_alvo_m"] = {"max": round(max(err), 2), "mediana": round(float(np.median(err)), 2)}
    with open(os.path.join(AV.SAIDA, "atlas_v2.json"), "w", encoding="utf-8") as f:
        json.dump(novo, f, ensure_ascii=False, indent=1)
    print("atlas_v2.json gravado;", len(alvos), "metros por câmera; |s do quadro − alvo|:", novo["conferencia_s_quadro_menos_alvo_m"])


if __name__ == "__main__":
    main()
