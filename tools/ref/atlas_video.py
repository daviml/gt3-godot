# -*- coding: utf-8 -*-
"""
Atlas do vídeo de referência (LMU) indexado por METRO DA PISTA — Fase 0A do PLANO-INTERLAGOS-DETALHES.md (§2).

O vídeo `INTERLAGOS-IN-LE-MANS-ULTIMATE-LMGT3-Track.mp4` traz a mesma volta (1:33.525) duas vezes:
câmera de perseguição (chase) e onboard (cockpit). Este script:

  1. lê a velocidade (km/h) e a marcha no mostrador do canto inferior direito, quadro a quadro, por
     comparação com gabaritos de dígitos (`tools/ref/gabaritos_velocimetro.png` = 0..9 e
     `tools/ref/gabaritos_marcha.png` = 1..6,N), e limpa a leitura com consistência temporal;
  2. integra v·dt para ter a distância percorrida em cada metade;
  3. alinha o perfil v(distância) com a telemetria de referência no s do jogo — padrão: a volta do Porsche
     911 GT3 R (992) do Garage 61 (mesmo carro do vídeo), convertida por `tools/ref/ref_garage61.py` para
     `build/ref/interlagos/ref_porsche-911-gt3-r-992.json`; alternativa `--ref r8` (build/interlagos/interlagos-r8_antigo.json).
     Deslocamento + escala global e depois âncoras locais (mínimas, fins de reta, inícios de freada, retomadas de
     acelerador), δ suavizado pela mediana das vizinhas, correção linear por trechos entre as âncoras;
  4. confere as duas metades entre si (é a mesma volta) e extrai 1 quadro a cada N metros por câmera.

Saídas em `build/ref/interlagos/`:
  velocidade.json      cache da leitura bruta (não relê o vídeo se existir; use --reler para forçar)
  atlas.json           metadados, resíduos, lista por s de cada câmera e tabela densa t -> s
  chase/sNNNN.jpg      quadros 1280x720 da perseguição
  onboard/sNNNN.jpg    quadros 1280x720 do onboard
  qa_auto.jpg          folha de checagem: 10 valores de s, chase | onboard lado a lado
  speed_fit.png        v(s) do vídeo x referência, com as âncoras marcadas

Uso (na raiz do repo):
  python tools/ref/atlas_video.py                 # tudo (lê o vídeo só se não houver cache)
  python tools/ref/atlas_video.py --so-leitura    # só lê o velocímetro e grava o cache
  python tools/ref/atlas_video.py --passo 10      # espaçamento dos quadros em metros (padrão 10)
  python tools/ref/atlas_video.py --sem-quadros   # recalcula atlas.json/QA sem reextrair os 2x430 JPGs
  python tools/ref/atlas_video.py --reler         # ignora o cache e relê o vídeo
  python tools/ref/atlas_video.py --ref r8        # ancora na volta do Audi R8 (versão antiga)
Antes, uma vez: python tools/ref/ref_garage61.py  (converte as voltas de garage61/ para o s do jogo)

Requer ffmpeg/ffprobe no PATH, Python 3 com NumPy e Pillow.
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
VIDEO = os.path.join(RAIZ, "INTERLAGOS-IN-LE-MANS-ULTIMATE-LMGT3-Track.mp4")
# Fase 2B (etapa E): o atlas da Fase 0 é no s da pista ANTIGA (4.294 m); a pista e a referência R8 antigas ficam
# em build/interlagos/ (data/ passou a ter a pista nova). A etapa F remapeia pelo tools/tracks/interlagos/s_antigo_novo.json.
REF = os.path.join(RAIZ, "build", "interlagos", "interlagos-r8_antigo.json")
TRACK = os.path.join(RAIZ, "build", "interlagos", "track_antigo.json")
SAIDA = os.path.join(RAIZ, "build", "ref", "interlagos")
GAB_VEL = os.path.join(RAIZ, "tools", "ref", "gabaritos_velocimetro.png")
GAB_MARCHA = os.path.join(RAIZ, "tools", "ref", "gabaritos_marcha.png")
MARCHAS = ["1", "2", "3", "4", "5", "6", "N"]

TEMPO_VOLTA = 93.525  # s, mostrado no vídeo

# Recorte do mostrador em 1920x1080 (cobre marcha + velocidade). Coordenadas abaixo são relativas a ele.
REC_X, REC_Y, REC_W, REC_H = 1670, 800, 160, 200
# Velocidade: gabarito 23x34; topo da faixa de dígitos e x do 1º pixel de cada casa (chase, antes da calibração)
VEL_Y = 118
CASAS3 = (45, 69, 93)  # 3 dígitos (já com -1 de margem)
CASAS2 = (57, 81)      # 2 dígitos (centralizado)
# Marcha: gabarito 80x88
MAR_Y, MAR_X = 14, 40

# Limiares da leitura
CONF_MIN = 0.80   # correlação mínima do pior dígito para aceitar a leitura
SALTO_MAX = 8.0   # km/h: diferença máxima para a mediana móvel


def log(*a):
    print(*a, flush=True)


try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


# ----------------------------------------------------------------------------------------------------------
# 1. Leitura do vídeo
# ----------------------------------------------------------------------------------------------------------
def info_video():
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=r_frame_rate,nb_frames,width,height,duration", "-of", "json", VIDEO],
        capture_output=True, text=True, check=True).stdout
    s = json.loads(out)["streams"][0]
    num, den = s["r_frame_rate"].split("/")
    return {"fps": float(num) / float(den), "n": int(s["nb_frames"]), "w": int(s["width"]),
            "h": int(s["height"]), "duracao": float(s["duration"])}


def ffmpeg_raw(vf, w, h, destino):
    """Decodifica o vídeo inteiro com o filtro `vf` para um arquivo raw em cinza e devolve um memmap."""
    with open(destino, "wb") as f:
        subprocess.run(["ffmpeg", "-v", "error", "-i", VIDEO, "-vf", vf + ",format=gray", "-f", "rawvideo", "-"],
                       stdout=f, check=True)
    return np.memmap(destino, np.uint8, "r").reshape(-1, h, w)


def normaliza(x):
    """Normaliza vetores (última dimensão) para correlação: média 0, norma 1."""
    x = x - x.mean(-1, keepdims=True)
    return x / (np.linalg.norm(x, axis=-1, keepdims=True) + 1e-6)


def carrega_gabaritos(caminho, n):
    img = np.asarray(Image.open(caminho).convert("L"), np.float32)
    w = img.shape[1] // n
    return normaliza(np.stack([img[:, i * w:(i + 1) * w].reshape(-1) for i in range(n)])), img.shape[0], w


def acha_corte(peq):
    """Acha o corte chase -> onboard. No onboard o topo da tela fica preto; o corte é o maior salto de imagem
    no segundo anterior ao topo escurecer. Devolve (quadro do corte, início do clarão branco antes dele)."""
    topo = peq[:, 0:4, :].astype(np.float32).mean((1, 2))
    escuro = topo < 40
    n = len(topo)
    ini = None
    for i in range(n // 4, n - 600):
        if escuro[i:i + 600].all():
            ini = i
            break
    if ini is None:
        raise RuntimeError("não achei o trecho onboard (topo preto)")
    dif = np.abs(np.diff(peq[ini - 90:ini + 1].astype(np.float32), axis=0)).mean((1, 2))
    corte = ini - 90 + 1 + int(np.argmax(dif))
    # clarão: topo muito claro logo antes do corte
    clarao = corte
    while clarao > 0 and topo[clarao - 1] > topo[corte - 40] + 25:
        clarao -= 1
    return corte, clarao


def janelas(F, y, x, h, w):
    return F[:, y:y + h, x:x + w].reshape(len(F), -1)


def le_casas(F, T, th, tw, y0, xs, desl):
    """Para cada casa (x em xs) devolve (dígito, correlação, 2ª melhor correlação) por quadro,
    procurando o melhor deslocamento em `desl`."""
    res = []
    for x in xs:
        melhor = None
        for dy, dx in desl:
            c = normaliza(janelas(F, y0 + dy, x + dx, th, tw)) @ T.T  # (N, K)
            melhor = c if melhor is None else np.maximum(melhor, c)
        o = np.sort(melhor, 1)
        res.append((np.argmax(melhor, 1), o[:, -1], o[:, -2]))
    return res


def le_velocidade(F, T, th, tw, dy, dx, fino=True):
    desl = [(a, b) for a in (-1, 0, 1) for b in (-1, 0, 1)] if fino else [(0, 0)]
    y0 = VEL_Y + dy
    r3 = le_casas(F, T, th, tw, y0, [x + dx for x in CASAS3], desl)
    r2 = le_casas(F, T, th, tw, y0, [x + dx for x in CASAS2], desl)
    c3 = np.min([r[1] for r in r3], 0)
    c2 = np.min([r[1] for r in r2], 0)
    v3 = r3[0][0] * 100 + r3[1][0] * 10 + r3[2][0]
    v2 = r2[0][0] * 10 + r2[1][0]
    usa3 = (c3 >= c2) & (r3[0][0] != 0)
    v = np.where(usa3, v3, v2)
    conf = np.where(usa3, c3, c2)
    return v, conf


def calibra(F, T, th, tw, y_base, x_base, faixa_y, faixa_x, leitor):
    """Acha o deslocamento global (dy, dx) do mostrador numa metade, pela maior correlação média."""
    melhor = (-9, 0, 0)
    for dy in faixa_y:
        for dx in faixa_x:
            _, conf = leitor(F, dy, dx)
            m = float(np.mean(conf))
            if m > melhor[0]:
                melhor = (m, dy, dx)
    return melhor


def ler_video():
    os.makedirs(SAIDA, exist_ok=True)
    inf = info_video()
    log(f"vídeo: {inf['w']}x{inf['h']} {inf['fps']:.0f} fps, {inf['n']} quadros, {inf['duracao']:.2f} s")
    if (inf["w"], inf["h"]) != (1920, 1080):
        raise RuntimeError("as coordenadas do mostrador assumem 1920x1080")
    tmp_p = os.path.join(SAIDA, "_peq.raw")
    tmp_c = os.path.join(SAIDA, "_painel.raw")
    log("decodificando miniaturas (corte de câmera)...")
    peq = ffmpeg_raw("scale=160:90:flags=area", 160, 90, tmp_p)
    corte, clarao = acha_corte(peq)
    # início útil do chase: depois do clarão de abertura do vídeo
    # diferença média entre quadros vizinhos (miniatura): serve para achar trechos congelados do vídeo
    dif = np.zeros(len(peq), np.float32)
    for i in range(1, len(peq), 2000):
        bloco = np.asarray(peq[i - 1:i + 2000], np.float32)
        dif[i:i + len(bloco) - 1] = np.abs(np.diff(bloco, axis=0)).mean((1, 2))
    del peq
    log(f"corte chase->onboard no quadro {corte} ({corte / inf['fps']:.3f} s); clarão desde {clarao}")
    log("decodificando recorte do mostrador...")
    pan = ffmpeg_raw(f"crop={REC_W}:{REC_H}:{REC_X}:{REC_Y}", REC_W, REC_H, tmp_c)
    n = len(pan)

    Tv, thv, twv = carrega_gabaritos(GAB_VEL, 10)
    Tm, thm, twm = carrega_gabaritos(GAB_MARCHA, len(MARCHAS))

    vel = np.zeros(n, np.int32)
    conf = np.zeros(n, np.float32)
    marcha = np.zeros(n, np.int32)
    conf_m = np.zeros(n, np.float32)
    metades = {"chase": (0, clarao), "onboard": (corte, n)}
    calib = {}
    for nome, (a, b) in metades.items():
        amostra = np.asarray(pan[a:b:25], np.float32)
        lv = lambda F, dy, dx: le_velocidade(F, Tv, thv, twv, dy, dx, fino=False)
        mv, dyv, dxv = calibra(amostra, Tv, thv, twv, VEL_Y, 0, range(-6, 14), range(-4, 5), lv)

        def lm(F, dy, dx):
            r = le_casas(F, Tm, thm, twm, MAR_Y + dy, [MAR_X + dx], [(0, 0)])[0]
            return r[0], r[1]
        mm, dym, dxm = calibra(amostra, Tm, thm, twm, MAR_Y, MAR_X, range(-6, 14), range(-4, 5), lm)
        calib[nome] = {"vel_dy": dyv, "vel_dx": dxv, "vel_corr_media": round(mv, 3),
                       "marcha_dy": dym, "marcha_dx": dxm, "marcha_corr_media": round(mm, 3)}
        log(f"  {nome}: velocidade dy={dyv} dx={dxv} (corr {mv:.3f}); marcha dy={dym} dx={dxm} (corr {mm:.3f})")
        for i in range(a, b, 500):
            F = np.asarray(pan[i:min(i + 500, b)], np.float32)
            v, c = le_velocidade(F, Tv, thv, twv, dyv, dxv)
            vel[i:i + len(F)] = v
            conf[i:i + len(F)] = c
            desl = [(p, q) for p in (-1, 0, 1) for q in (-1, 0, 1)]
            g, cg, _ = le_casas(F, Tm, thm, twm, MAR_Y + dym, [MAR_X + dxm], desl)[0]
            marcha[i:i + len(F)] = g
            conf_m[i:i + len(F)] = cg
    # quadros do clarão (entre as metades) ficam sem leitura
    conf[clarao:corte] = 0
    conf_m[clarao:corte] = 0
    del pan
    for t in (tmp_p, tmp_c):
        try:
            os.remove(t)
        except OSError:
            pass
    cache = {
        "video": os.path.basename(VIDEO), "fps": inf["fps"], "n_quadros": n, "duracao": inf["duracao"],
        "corte_quadro": int(corte), "corte_t": round(corte / inf["fps"], 4),
        "clarao_quadro": int(clarao), "clarao_t": round(clarao / inf["fps"], 4),
        "calibracao": calib, "conf_min": CONF_MIN,
        "v_kmh": vel.tolist(), "conf": np.round(conf, 3).tolist(),
        "marcha": [MARCHAS[g] for g in marcha], "conf_marcha": np.round(conf_m, 3).tolist(),
        "dif_img": np.round(dif, 2).tolist(),
    }
    with open(os.path.join(SAIDA, "velocidade.json"), "w", encoding="utf-8") as f:
        json.dump(cache, f)
    log("cache gravado em build/ref/interlagos/velocidade.json")
    return cache


# ----------------------------------------------------------------------------------------------------------
# 2. Limpeza da leitura e integração
# ----------------------------------------------------------------------------------------------------------
CONGELA_DIF = 0.8   # diferença média (0-255) abaixo da qual o quadro é cópia do anterior
CONGELA_MIN = 6     # quadros seguidos para considerar o vídeo congelado


def mediana_movel(x, n):
    pad = n // 2
    xp = np.pad(x, pad, mode="edge")
    return np.median(np.lib.stride_tricks.sliding_window_view(xp, n), axis=1)


def moda_movel(rot, ok, n=9):
    """Marcha: valor mais frequente entre as leituras confiáveis vizinhas."""
    out = []
    m = len(rot)
    for i in range(m):
        viz = [rot[j] for j in range(max(0, i - n // 2), min(m, i + n // 2 + 1)) if ok[j]]
        out.append(max(set(viz), key=viz.count) if viz else None)
    return out


def acha_congelados(dif, a, b):
    """Trechos [q0, q1) em que o vídeo repete o mesmo quadro (o tempo do jogo não anda)."""
    baixo = dif < CONGELA_DIF
    trechos = []
    i = a + 1
    while i < b:
        if baixo[i]:
            j = i
            while j < b and baixo[j]:
                j += 1
            if j - i >= CONGELA_MIN:
                trechos.append((i, j))
            i = j
        else:
            i += 1
    return trechos


def prepara_metade(cache, nome, a, b):
    """Limpa a leitura de [a, b) e integra a distância. Devolve dicionário com arrays por quadro."""
    fps = cache["fps"]
    v = np.asarray(cache["v_kmh"][a:b], np.float64)
    conf = np.asarray(cache["conf"][a:b])
    dif = np.asarray(cache["dif_img"])
    ok = conf >= CONF_MIN
    # descarta o começo/fim sem leitura (vinheta, fade)
    idx_ok = np.where(ok)[0]
    a2, b2 = a + idx_ok[0], a + idx_ok[-1] + 1
    v, conf, ok = v[a2 - a:b2 - a], conf[a2 - a:b2 - a], ok[a2 - a:b2 - a]
    q = np.arange(a2, b2)
    i = np.arange(len(v))
    vi = np.interp(i, i[ok], v[ok])
    med = mediana_movel(vi, 15)
    bom = ok & (np.abs(v - med) <= SALTO_MAX)
    vlimpa = np.interp(i, i[bom], v[bom])
    # passo de tempo real: zero nos quadros congelados
    congel = acha_congelados(dif, a2, b2)
    dt = np.full(len(v), 1.0 / fps)
    dt[0] = 0.0
    for q0, q1 in congel:
        dt[q0 - a2:q1 - a2] = 0.0
    tau = np.cumsum(dt)  # tempo "de jogo" desde o início útil da metade
    ds = np.concatenate([[0.0], (vlimpa[1:] + vlimpa[:-1]) / 2.0 / 3.6]) * dt
    dist = np.cumsum(ds)
    conf_m = np.asarray(cache["conf_marcha"][a2:b2]) >= 0.85
    marcha = moda_movel(cache["marcha"][a2:b2], conf_m)
    info = {"quadro_ini": int(a2), "quadro_fim": int(b2), "quadros": int(len(v)),
            "lidos_confiaveis": int(ok.sum()), "taxa_confiavel": round(float(ok.mean()), 4),
            "rejeitados_por_salto": int((ok & ~bom).sum()),
            "taxa_final": round(float(bom.mean()), 4),
            "congelamentos": [{"q0": int(x), "q1": int(y), "t0": round(x / fps, 3), "t1": round(y / fps, 3),
                               "quadros": int(y - x)} for x, y in congel]}
    log(f"  {nome}: quadros {a2}..{b2 - 1}, leitura confiável {ok.mean() * 100:.2f}%, "
        f"rejeitadas por salto {int((ok & ~bom).sum())}, congelamentos {[(int(x), int(y)) for x, y in congel]}, "
        f"distância integrada total {dist[-1]:.1f} m em {tau[-1]:.2f} s de jogo")
    return {"nome": nome, "q": q, "v": vlimpa, "tau": tau, "dist": dist, "marcha": marcha, "info": info}


# ----------------------------------------------------------------------------------------------------------
# 3. Alinhamento com a referência
# ----------------------------------------------------------------------------------------------------------
REFS = {
    "porsche": os.path.join(SAIDA, "ref_porsche-911-gt3-r-992.json"),  # gerado por tools/ref/ref_garage61.py
    "r8": REF,
}


def carrega_ref(nome):
    caminho = REFS.get(nome, nome)
    if not os.path.exists(caminho):
        raise SystemExit(f"referência {caminho} não existe (rode antes: python tools/ref/ref_garage61.py)")
    ref = json.load(open(caminho, encoding="utf-8"))
    passo = float(ref["step"])
    r = {"arquivo": os.path.relpath(caminho, RAIZ).replace("\\", "/"), "rotulo": ref.get("label", ""),
         "v": np.asarray(ref["v"], np.float64) * 3.6}  # m/s -> km/h
    r["s"] = np.arange(len(r["v"])) * passo
    for k in ("brake", "throttle", "gear"):
        r[k] = np.asarray(ref[k], np.float64) if k in ref else None
    return r


def suaviza(x, n):
    k = np.ones(n) / n
    return np.convolve(np.pad(x, n, mode="wrap"), k, "same")[n:-n]


def extremos(x, s, janela_m, prom, tipo):
    """Mínimos (tipo='min') ou máximos locais de x(s) em janela ±janela_m com proeminência >= prom (km/h)."""
    passo = s[1] - s[0]
    w = int(janela_m / passo)
    n = len(x)
    res = []
    for i in range(n):
        viz = np.take(x, range(i - w, i + w + 1), mode="wrap")
        if tipo == "min" and x[i] == viz.min() and viz.max() - x[i] >= prom:
            res.append(i)
        if tipo == "max" and x[i] == viz.max() and x[i] - viz.min() >= prom:
            res.append(i)
    # remove repetições em platôs
    out = []
    for i in res:
        if not out or i - out[-1] > w:
            out.append(i)
    return out


def ajuste_global(m, s_ref, v_ref, L):
    """s ≈ k·(dist − D0). Maximiza a correlação entre v_video(s) e v_ref(s) na volta inteira."""
    dist, v = m["dist"], m["v"]

    def corr(k, D0):
        x = np.interp(D0 + s_ref / k, dist, v)
        return np.corrcoef(x, v_ref)[0, 1]
    melhor = (-2, 1.0, 0.0)
    for k in np.arange(0.96, 1.04, 0.002):
        for D0 in np.arange(-300, 400, 4.0):
            if D0 + L / k > dist[-1] + 300:
                continue
            c = corr(k, D0)
            if c > melhor[0]:
                melhor = (c, k, D0)
    _, k0, d0 = melhor
    for k in np.arange(k0 - 0.003, k0 + 0.003, 0.0002):
        for D0 in np.arange(d0 - 5, d0 + 5, 0.25):
            c = corr(k, D0)
            if c > melhor[0]:
                melhor = (c, k, D0)
    return melhor


def corr_janela(v_video_em, s_ref, v_ref, centro, meia, busca=60.0):
    """Melhor deslocamento δ (m) do vídeo em relação à referência numa janela [centro±meia].
    `v_video_em(ss)` devolve a velocidade do vídeo nas posições ss (na escala de s em teste)."""
    L = s_ref[-1] + (s_ref[1] - s_ref[0])
    ss = np.arange(centro - meia, centro + meia + 0.1, 2.0)
    vr = np.interp(np.mod(ss, L), s_ref, v_ref, period=L)
    melhor = (-2, 0.0)
    for d in np.arange(-busca, busca + 0.01, 0.5):
        x = v_video_em(ss + d)
        if np.ptp(x) < 1:
            continue
        c = np.corrcoef(x, vr)[0, 1]
        if c > melhor[0]:
            melhor = (c, d)
    return melhor


RAIO_MEDIANA = 150.0   # m: âncoras vizinhas combinadas pela mediana
LIMITE_DISCORDA = 15.0  # m: âncora descartada se difere disso da mediana das vizinhas (±500 m)


def dist_circ(a, b, L):
    d = abs(a - b) % L
    return min(d, L - d)


def centros_ancora(ref, L):
    """Pontos da referência que viram âncoras: mínimas de velocidade, máximas (fim de reta), inícios de freada
    (freio cruza 20%) e retomadas de acelerador pleno (cruza 98%). Pontos a menos de 20 m de um já escolhido
    são descartados (a janela de ±100 m seria praticamente a mesma)."""
    s, v = ref["s"], ref["v"]
    vs = suaviza(v, 5)
    cand = [("mínima de curva", float(s[i])) for i in extremos(vs, s, 80, 15, "min")]
    cand += [("fim de reta (v máx)", float(s[i])) for i in extremos(vs, s, 80, 15, "max")]
    if ref.get("brake") is not None:
        b = ref["brake"]
        cand += [("início de freada", float(s[i])) for i in range(1, len(b)) if b[i] >= 0.2 > b[i - 1]]
    if ref.get("throttle") is not None:
        th = ref["throttle"]
        cand += [("acelerador pleno", float(s[i])) for i in range(1, len(th)) if th[i] >= 0.98 > th[i - 1]]
    out = []
    for tipo, sa in cand:
        if all(min(abs(sa - x), L - abs(sa - x)) >= 20 for _, x in out):
            out.append((tipo, sa))
    return sorted(out, key=lambda x: x[1])


def alinha(m, ref, L, centros):
    s_ref, v_ref = ref["s"], ref["v"]
    c, k, D0 = ajuste_global(m, s_ref, v_ref, L)
    log(f"  {m['nome']}: ajuste global k={k:.4f} D0={D0:.1f} m (corr {c:.4f})")
    ancoras = []
    v_em = lambda ss: np.interp(D0 + ss / k, m["dist"], m["v"])
    for tipo, sa in centros:
        cc, d = corr_janela(v_em, s_ref, v_ref, sa, 100.0)
        ancoras.append({"tipo": tipo, "s_ref": sa, "v_ref": round(float(np.interp(sa, s_ref, v_ref)), 1),
                        "delta_m": round(float(d), 1), "corr": round(float(cc), 3)})
    ancoras.sort(key=lambda x: x["s_ref"])
    # rejeita âncoras fracas ou que discordam das vizinhas. Mesmo com o mesmo carro, piloto e simulador são
    # outros: pontos de freada/retomada variam ~±10 m por piloto. Por isso a correção usa a MEDIANA das âncoras
    # num raio de ±RAIO_MEDIANA m (δ suavizado), não cada âncora crua.
    for a in ancoras:
        a["usada"] = a["corr"] >= 0.9
        if not a["usada"]:
            a["motivo"] = "correlação baixa"
    for _ in range(2):
        usadas = [a for a in ancoras if a["usada"]]
        for a in usadas:
            viz = [b["delta_m"] for b in usadas if b is not a and dist_circ(b["s_ref"], a["s_ref"], L) < 500]
            if len(viz) >= 2 and abs(a["delta_m"] - float(np.median(viz))) > LIMITE_DISCORDA:
                a["usada"] = False
                a["motivo"] = "discorda das vizinhas"

    def curva_delta(lista):
        """δ suavizado em cada âncora da lista -> (x_g ordenado, δ) periódicos para interpolar."""
        xs, ds = [], []
        for a in lista:
            viz = [b["delta_m"] for b in lista if dist_circ(b["s_ref"], a["s_ref"], L) <= RAIO_MEDIANA]
            dm = float(np.median(viz))
            xs.append(a["s_ref"] + dm)
            ds.append(dm)
        xs, ds = np.array(xs), np.array(ds)
        o = np.argsort(xs)
        xs, ds = xs[o], ds[o]
        return np.concatenate([xs - L, xs, xs + L]), np.concatenate([ds, ds, ds])

    us = [a for a in ancoras if a["usada"]]
    xs_p, ds_p = curva_delta(us)
    for a in ancoras:
        a["delta_suave_m"] = round(float(np.interp(a["s_ref"] + a["delta_m"], xs_p, ds_p)), 1)

    def s_de_dist(dist):
        sg = k * (np.asarray(dist) - D0)
        return sg - np.interp(sg, xs_p, ds_p)
    s = s_de_dist(m["dist"])
    # resíduo "deixa-um-fora": a correção montada SEM a âncora erra quanto nela? (estimativa honesta do erro
    # entre âncoras, já incluindo a diferença de pilotagem). Para as não usadas, compara com a correção final.
    for a in ancoras:
        xo, do = curva_delta([b for b in us if b is not a])
        pred = np.interp(a["s_ref"] + a["delta_m"], xo, do)
        a["residuo_m"] = round(float(a["delta_m"] - pred), 1)
    return {"k": k, "D0": D0, "corr_global": c, "ancoras": ancoras, "s": s, "s_de_dist": s_de_dist}


def compara_metades(ch, on):
    """As duas metades são a mesma volta: acha o deslocamento de tempo de jogo entre elas pela velocidade e
    mede a diferença de s no mesmo instante."""
    grade = np.arange(0, min(ch["tau"][-1], on["tau"][-1]), 0.01)
    vc = np.interp(grade, ch["tau"], ch["v"])
    melhor = (1e9, 0.0)
    for off in np.arange(-3.0, 3.0, 0.005):
        g = grade + off
        sel = (g >= 0) & (g <= on["tau"][-1])
        e = np.mean(np.abs(np.interp(g[sel], on["tau"], on["v"]) - vc[sel]))
        if e < melhor[0]:
            melhor = (e, off)
    e, off = melhor
    g = grade + off
    sel = (g >= 0) & (g <= on["tau"][-1])
    tau_c = grade[sel]
    s_c = np.interp(tau_c, ch["tau"], ch["s"])
    s_o = np.interp(tau_c + off, on["tau"], on["s"])
    dif = s_o - s_c
    return {"desloc_tau_s": round(float(off), 3), "dif_media_v_kmh": round(float(e), 3),
            "erro_max_m": round(float(np.max(np.abs(dif))), 2), "erro_rms_m": round(float(np.sqrt(np.mean(dif ** 2))), 2),
            "s_pior": round(float(s_c[np.argmax(np.abs(dif))]), 0)}


def nome_trecho(s, secoes):
    for sec in secoes:
        if sec["s0"] <= s <= sec["s1"]:
            return sec["name"]
    antes = [sec for sec in secoes if sec["s1"] < s]
    if not antes or s > 4146:
        return "Reta dos boxes"
    return "após " + antes[-1]["name"]


def escolhe_quadros(m, alvos, L):
    """Para cada s alvo, o quadro da metade cujo s (desenrolado) é o mais próximo. Prefere a volta propriamente
    dita (0 <= s < L); se o trecho não estiver coberto, usa o mesmo ponto da volta anterior/seguinte (s ± L)."""
    s = m["s"]
    res = []
    for alvo in alvos:
        escolha = None
        for cand in (alvo, alvo + L, alvo - L):
            if s[0] - 0.5 <= cand <= s[-1] + 0.5:
                j = int(np.searchsorted(s, cand))
                j = min(max(j, 0), len(s) - 1)
                if j > 0 and abs(s[j - 1] - cand) <= abs(s[j] - cand):
                    j -= 1
                escolha = (j, cand)
                break
        res.append(escolha)
    return res


def extrai_quadros(quadros_nomes, pasta):
    """Extrai os quadros (número absoluto no vídeo) em 1280x720 com um único passe do ffmpeg."""
    os.makedirs(pasta, exist_ok=True)
    for f in os.listdir(pasta):
        if f.endswith(".jpg"):
            os.remove(os.path.join(pasta, f))
    unicos = sorted(set(q for q, _ in quadros_nomes))
    # soma em árvore balanceada: uma corrente longa de "+" estoura o analisador de expressões do ffmpeg
    def arvore(lst):
        if len(lst) == 1:
            return f"eq(n\\,{lst[0]})"
        meio = len(lst) // 2
        return f"({arvore(lst[:meio])}+{arvore(lst[meio:])})"
    expr = arvore(unicos)
    tmp = os.path.join(pasta, "_tmp_%04d.jpg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", VIDEO, "-vf", f"select='{expr}',scale=1280:720:flags=lanczos",
                    "-fps_mode", "passthrough", "-q:v", "3", "-start_number", "0", tmp], check=True)
    pos = {q: i for i, q in enumerate(unicos)}
    usados = {}
    for q, nome in quadros_nomes:
        src = os.path.join(pasta, f"_tmp_{pos[q]:04d}.jpg")
        dst = os.path.join(pasta, nome)
        if q in usados:
            import shutil
            shutil.copyfile(usados[q], dst)
        else:
            os.replace(src, dst)
            usados[q] = dst


def fonte(tam):
    for f in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(f, tam)
        except OSError:
            continue
    return ImageFont.load_default()


def folha_qa(atlas, secoes, destino, valores):
    W, H = 640, 360
    img = Image.new("RGB", (2 * W + 10, len(valores) * (H + 34) + 40), (24, 24, 24))
    d = ImageDraw.Draw(img)
    f1, f2 = fonte(22), fonte(16)
    d.text((10, 8), "QA automático do atlas — esquerda: chase | direita: onboard (mesmo s)", fill=(255, 255, 255), font=f1)
    por_s = {cam: {e["s"]: e for e in atlas[cam]} for cam in ("chase", "onboard")}
    for r, s in enumerate(valores):
        y = 40 + r * (H + 34)
        d.text((10, y + 4), f"s = {s} m — {nome_trecho(s, secoes)}", fill=(255, 220, 80), font=f1)
        for c, cam in enumerate(("chase", "onboard")):
            e = por_s[cam].get(s)
            x = c * (W + 10)
            if e and e.get("arquivo"):
                p = os.path.join(SAIDA, e["arquivo"])
                if os.path.exists(p):
                    img.paste(Image.open(p).resize((W, H)), (x, y + 30))
                d.text((x + 8, y + 36), f"{cam}  t={e['t_video']:.2f}s  {e['v_kmh']:.0f} km/h  marcha {e['marcha']}",
                       fill=(255, 255, 255), font=f2, stroke_width=2, stroke_fill=(0, 0, 0))
    img.save(destino, quality=88)


def grafico(s_ref, v_ref, metades, alin, destino, L, secoes):
    esc = 0.5  # px por metro
    W, H, mg = int(L * esc) + 80, 520, 40
    img = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(img)
    f = fonte(13)
    y_de = lambda v: H - mg - (v - 50) / (280 - 50) * (H - 2 * mg)
    x_de = lambda s: mg + s * esc
    for sec in secoes:
        d.rectangle([x_de(sec["s0"]), mg, x_de(sec["s1"]), H - mg], fill=(240, 240, 248))
        d.text((x_de(sec["s0"]) + 2, H - mg + 4), sec["name"], fill=(90, 90, 90), font=f)
    for v in range(50, 300, 50):
        d.line([mg, y_de(v), W - mg, y_de(v)], fill=(220, 220, 220))
        d.text((4, y_de(v) - 7), str(v), fill=(90, 90, 90), font=f)
    for s in range(0, int(L) + 1, 500):
        d.text((x_de(s) - 10, mg - 18), f"{s}", fill=(90, 90, 90), font=f)
    d.line([(x_de(s), y_de(v)) for s, v in zip(s_ref, v_ref)], fill=(40, 40, 40), width=2)
    cores = {"chase": (220, 60, 40), "onboard": (40, 110, 220)}
    for nome, m in metades.items():
        sel = (m["s"] >= 0) & (m["s"] < L)
        pts = [(x_de(s), y_de(v)) for s, v in zip(m["s"][sel][::6], m["v"][sel][::6])]
        d.line(pts, fill=cores[nome], width=1)
    for a in alin["chase"]["ancoras"]:
        x = x_de(a["s_ref"])
        cor = (0, 150, 0) if a["usada"] else (200, 0, 200)
        d.line([x, mg, x, H - mg], fill=cor, width=1)
        d.text((x + 2, mg + 2 + (14 if a["tipo"].startswith("in") else 0)), f"{a['delta_m']:+.0f}", fill=cor, font=f)
    d.text((W - 520, H - 22), "preto: referência  vermelho: chase  azul: onboard  verde/roxo: âncora usada/rejeitada",
           fill=(0, 0, 0), font=f)
    img.save(destino)


def main():
    ap = argparse.ArgumentParser(description="Atlas do vídeo LMU de Interlagos por metro de pista")
    ap.add_argument("--passo", type=int, default=10, help="espaçamento dos quadros em metros (padrão 10)")
    ap.add_argument("--so-leitura", action="store_true", help="só lê o velocímetro e grava o cache")
    ap.add_argument("--reler", action="store_true", help="ignora o cache e relê o vídeo")
    ap.add_argument("--ref", default="porsche",
                    help="referência p/ âncoras: porsche (padrão, mesmo carro do vídeo), r8, ou caminho de um .json")
    ap.add_argument("--sem-quadros", action="store_true", help="não reextrai os JPGs por s")
    args = ap.parse_args()

    cam_cache = os.path.join(SAIDA, "velocidade.json")
    if args.reler or not os.path.exists(cam_cache):
        cache = ler_video()
    else:
        with open(cam_cache, encoding="utf-8") as f:
            cache = json.load(f)
        log("usando cache de leitura: build/ref/interlagos/velocidade.json")
    if args.so_leitura:
        return

    fps = cache["fps"]
    L = float(json.load(open(TRACK, encoding="utf-8"))["length"])
    log("limpeza e integração:")
    metades = {
        "chase": prepara_metade(cache, "chase", 0, cache["clarao_quadro"]),
        "onboard": prepara_metade(cache, "onboard", cache["corte_quadro"], cache["n_quadros"]),
    }
    ref = carrega_ref(args.ref)
    s_ref, v_ref, rotulo_ref = ref["s"], ref["v"], ref["rotulo"]
    centros = centros_ancora(ref, L)
    log(f"referência: {rotulo_ref} ({ref['arquivo']}); {len(centros)} candidatas a âncora: "
        f"{[(t[:5], int(x)) for t, x in centros]}")
    log("alinhamento:")
    alin = {}
    for nome, m in metades.items():
        al = alinha(m, ref, L, centros)
        alin[nome] = al
        m["s"] = al["s"]
        for a in al["ancoras"]:
            log(f"    {a['tipo']:17s} s_ref={a['s_ref']:6.0f}  δ={a['delta_m']:6.1f}  corr={a['corr']:.3f}  "
                f"suave={a['delta_suave_m']:6.1f}  resíduo(deixa-um-fora)={a['residuo_m']:6.1f}  {'ok' if a['usada'] else 'NÃO USADA: ' + a.get('motivo', '')}")
        # distância integrada de UMA volta (tempo de volta do vídeo) a partir da linha, antes de qualquer correção
        t0 = float(np.interp(0.0, m["s"], m["tau"]))
        d0 = float(np.interp(t0, m["tau"], m["dist"]))
        d1 = float(np.interp(t0 + TEMPO_VOLTA, m["tau"], m["dist"])) if m["tau"][-1] >= t0 + TEMPO_VOLTA else None
        al["dist_volta_integrada_m"] = None if d1 is None else round(d1 - d0, 1)
        al["dist_linha_a_linha_m"] = round(L / al["k"], 1)
        log(f"  {nome}: distância integrada (bruta) linha->linha = {L / al['k']:.1f} m; em {TEMPO_VOLTA} s de jogo "
            f"a partir da linha = {al['dist_volta_integrada_m']} m")

    chk = compara_metades(metades["chase"], metades["onboard"])
    log(f"checagem chase x onboard: deslocamento {chk['desloc_tau_s']} s, |Δv| médio {chk['dif_media_v_kmh']} km/h, "
        f"erro de s máx {chk['erro_max_m']} m (em s≈{chk['s_pior']:.0f}), rms {chk['erro_rms_m']} m")

    secoes = json.load(open(TRACK, encoding="utf-8"))["sections"]
    alvos = list(range(0, int(L), args.passo))
    atlas = {}
    for nome, m in metades.items():
        lista = []
        ext = []
        for alvo, esc in zip(alvos, escolhe_quadros(m, alvos, L)):
            if esc is None:
                lista.append({"s": alvo, "t_video": None, "quadro": None, "v_kmh": None, "marcha": None,
                              "arquivo": None})
                continue
            j, cand = esc
            q = int(m["q"][j])
            arq = f"{nome}/s{alvo:04d}.jpg"
            e = {"s": alvo, "t_video": round(q / fps, 3), "quadro": q, "v_kmh": round(float(m["v"][j]), 1),
                 "marcha": m["marcha"][j], "s_quadro": round(float(m["s"][j]) - (cand - alvo), 2),
                 "arquivo": arq}
            if cand != alvo:
                e["obs"] = "fora da volta gravada: quadro da volta " + ("seguinte" if cand > alvo else "anterior")
            lista.append(e)
            ext.append((q, f"s{alvo:04d}.jpg"))
        atlas[nome] = lista
        if not args.sem_quadros:
            log(f"extraindo {len(ext)} quadros de {nome}...")
            extrai_quadros(ext, os.path.join(SAIDA, nome))
        # marca quadros com brilho fora do normal da câmera (vinheta de abertura, fade final do vídeo)
        brilho = {}
        for e in lista:
            p = os.path.join(SAIDA, e["arquivo"]) if e["arquivo"] else None
            if p and os.path.exists(p):
                brilho[e["s"]] = float(np.asarray(Image.open(p).convert("L").reduce(8), np.float32).mean())
        if brilho:
            med = float(np.median(list(brilho.values())))
            for e in lista:
                b = brilho.get(e["s"])
                # só o escurecimento é marcado: textos grandes do "track guide" clareiam quadros normais
                # (só perto das pontas da metade, onde há vinheta/fade; no meio são sombras normais)
                perto_ponta = e["quadro"] is not None and (e["quadro"] - m["q"][0] < fps or m["q"][-1] - e["quadro"] < 3 * fps)
                if b is not None and b < 0.8 * med and perto_ponta:
                    e["obs"] = (e.get("obs", "") + "; " if e.get("obs") else "") + "quadro escurecido (fade do vídeo)"
                # começo da perseguição: o vídeo abre com efeito de fumaça/clarão na tela
                if nome == "chase" and e["quadro"] is not None and e["quadro"] - m["q"][0] < 0.5 * fps:
                    e["obs"] = ((e.get("obs", "") + "; ") if e.get("obs") else "") + \
                        "vinheta de abertura do vídeo (fumaça/clarão sobre a imagem)"
            ruins = [e["s"] for e in lista if "fade" in e.get("obs", "") or "vinheta" in e.get("obs", "")]
            if ruins:
                log(f"  {nome}: {len(ruins)} quadros com brilho anormal (s {ruins[0]}..{ruins[-1]})")

    tabela = {}
    for nome, m in metades.items():
        t = m["q"] / fps
        tt = np.arange(np.ceil(t[0] * 10) / 10, t[-1], 0.1)
        tabela[nome] = [[round(float(a), 1), round(float(b), 2)] for a, b in zip(tt, np.interp(tt, t, m["s"]))]

    def resumo_alin(al):
        us = [a for a in al["ancoras"] if a["usada"]]
        r = np.array([a["residuo_m"] for a in us])
        return {"k_escala": round(al["k"], 5), "D0_m": round(al["D0"], 2), "corr_global": round(al["corr_global"], 4),
                "dist_linha_a_linha_integrada_m": al["dist_linha_a_linha_m"],
                "dist_integrada_em_um_tempo_de_volta_m": al["dist_volta_integrada_m"],
                "ancoras_usadas": len(us), "residuo_deixa_um_fora_rms_m": round(float(np.sqrt(np.mean(r ** 2))), 2),
                "residuo_deixa_um_fora_max_m": round(float(np.max(np.abs(r))), 2), "ancoras": al["ancoras"]}

    saida = {
        "video": cache["video"], "fps": fps, "n_quadros": cache["n_quadros"], "duracao_s": cache["duracao"],
        "tempo_volta_s": TEMPO_VOLTA, "comprimento_pista_m": L, "passo_m": args.passo,
        "corte": {"chase": [metades["chase"]["info"]["quadro_ini"], metades["chase"]["info"]["quadro_fim"]],
                  "onboard": [metades["onboard"]["info"]["quadro_ini"], metades["onboard"]["info"]["quadro_fim"]],
                  "corte_camera_quadro": cache["corte_quadro"], "corte_camera_t": cache["corte_t"],
                  "clarao_quadro": cache["clarao_quadro"], "clarao_t": cache["clarao_t"]},
        "referencia": {"arquivo": ref["arquivo"], "rotulo": rotulo_ref},
        "metodo": ("velocímetro lido por correlação com gabaritos de dígitos (tools/ref/gabaritos_*.png); "
                   "limpeza: confiança >= %.2f, mediana móvel de 15 quadros, salto <= %.0f km/h, interpolação; "
                   "quadros congelados (vídeo parado) têm dt = 0; distância = soma de v·dt (trapézio); "
                   "s = k·(dist − D0) por correlação global com a referência, depois correção linear por trechos "
                   "com âncoras (correlação local ±100 m de v(s) em mínimas, fins de reta, inícios de freada e "
                   "retomadas de acelerador pleno da referência; δ = mediana das âncoras a ±150 m; âncora que "
                   "difere >15 m das vizinhas é descartada)"
                   % (CONF_MIN, SALTO_MAX)),
        "leitura": {n: m["info"] for n, m in metades.items()},
        "calibracao_mostrador": cache.get("calibracao"),
        "alinhamento": {n: resumo_alin(a) for n, a in alin.items()},
        "checagem_chase_x_onboard": chk,
        "cameras": atlas,
        "tabela_t_s": {"passo_s": 0.1, "obs": "[t_video, s desenrolado: <0 antes da linha, >L depois]", **tabela},
    }
    with open(os.path.join(SAIDA, "atlas.json"), "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, indent=1)
    log("atlas.json gravado")
    qa = [40, 220, 330, 680, 1000, 1440, 2040, 2480, 3170, 3950]
    folha_qa(atlas, secoes, os.path.join(SAIDA, "qa_auto.jpg"), [x - x % args.passo for x in qa])
    grafico(s_ref, v_ref, metades, alin, os.path.join(SAIDA, "speed_fit.png"), L, secoes)
    log("qa_auto.jpg e speed_fit.png gravados")


if __name__ == "__main__":
    main()
