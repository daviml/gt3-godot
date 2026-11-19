#!/usr/bin/env python3
"""Gera amostras-base sintéticas de alta qualidade para FX GT3 e UI em build/audio_raw/
e processa todas via tools/audio_prep.py para assets/sounds/fx/.
"""

from __future__ import annotations

import math
import random
import struct
import subprocess
import sys
import wave
from pathlib import Path

RATE = 44100
ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "build" / "audio_raw"
FX_DIR = ROOT / "assets" / "sounds" / "fx"
PREP = ROOT / "tools" / "audio_prep.py"


def write_raw(name: str, samples: list[float]) -> Path:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    path = RAW_DIR / name
    peak = max((abs(s) for s in samples), default=1.0)
    scale = 28000.0 / max(1e-6, peak)
    pcm = struct.pack(
        f"<{len(samples)}h",
        *[max(-32768, min(32767, int(round(s * scale)))) for s in samples],
    )
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(RATE)
        wf.writeframes(pcm)
    return path


def gen_kerb_loop(dur: float = 2.4) -> Path:
    n = int(dur * RATE)
    rng = random.Random(101)
    out: list[float] = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        # Vibração grave de zebra (~52 Hz + harmônico 104 Hz + modulação suave)
        rumble = (
            0.65 * math.sin(2.0 * math.pi * 52.0 * t)
            + 0.30 * math.sin(2.0 * math.pi * 104.0 * t + 0.4)
            + 0.15 * math.sin(2.0 * math.pi * 156.0 * t + 0.9)
        )
        # Batida periódica suave a ~18 Hz
        pulse = 0.65 + 0.35 * math.sin(2.0 * math.pi * 18.0 * t)
        noise = rng.uniform(-1.0, 1.0)
        lp = lp * 0.92 + noise * 0.08
        out.append(rumble * pulse + lp * 0.45)
    return write_raw("kerb_loop_raw.wav", out)


def gen_bottom_scrape(dur: float = 0.32) -> Path:
    n = int(dur * RATE)
    rng = random.Random(303)
    out: list[float] = []
    bp = 0.0
    bp2 = 0.0
    for i in range(n):
        t = i / RATE
        env_hit = math.exp(-t / 0.045)
        env_scrape = math.exp(-t / 0.14) * (1.0 - math.exp(-t / 0.004))
        thump = math.sin(2.0 * math.pi * (95.0 - 40.0 * min(1.0, t * 5.0)) * t) * env_hit
        grit = rng.uniform(-1.0, 1.0)
        # Filtro ressonante simples para som metálico/fibra raspando
        bp = bp * 0.72 + grit * 0.28
        bp2 = bp2 * 0.88 + (grit - bp) * 0.25
        scrape = (grit - bp + bp2 * 1.4) * env_scrape
        mod = 0.7 + 0.3 * math.sin(2.0 * math.pi * 65.0 * t)
        out.append(thump * 0.6 + scrape * mod * 0.85)
    return write_raw("bottom_scrape_raw.wav", out)


def gen_backfire(idx: int) -> Path:
    """Pipoco de escape GT3 grave e encorpado (sub-thump + corpo médio-grave, sem chiado agudo)."""
    rng = random.Random(400 + idx)
    pops = {
        1: [(0.004, 0.048, 72.0, 1.0)],
        2: [(0.004, 0.044, 78.0, 1.0), (0.072, 0.038, 64.0, 0.74)],
        3: [(0.004, 0.036, 76.0, 0.88), (0.056, 0.042, 66.0, 1.0), (0.118, 0.034, 82.0, 0.60)],
    }[idx]
    dur = 0.22 if idx == 1 else (0.26 if idx == 2 else 0.30)
    n = int(dur * RATE)
    out: list[float] = []
    lp_noise = 0.0
    lp_noise2 = 0.0
    for i in range(n):
        t = i / RATE
        raw_n = rng.uniform(-1.0, 1.0)
        # Dois estágios de passa-baixa para textura encorpada de combustão (~400-900 Hz, zero chiado agudo)
        lp_noise = lp_noise * 0.86 + raw_n * 0.14
        lp_noise2 = lp_noise2 * 0.78 + lp_noise * 0.22
        val = 0.0
        for t0, tau, freq, amp in pops:
            if t >= t0:
                dt = t - t0
                env = math.exp(-dt / tau) * (1.0 - math.exp(-dt / 0.0025))
                # Fase integrada do pitch drop (evita artefatos de FM)
                phase = 2.0 * math.pi * freq * (1.0 - math.exp(-dt * 5.0)) / 5.0
                sub = math.sin(phase)
                body = 0.50 * math.sin(phase * 1.95 + 0.35) * math.exp(-dt / (tau * 0.80))
                bark = math.tanh((sub + body + lp_noise2 * 1.65) * 1.45)
                val += amp * env * bark
        out.append(val)
    return write_raw(f"backfire_{idx}_raw.wav", out)


def gen_ui_click() -> Path:
    dur = 0.045
    n = int(dur * RATE)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t / 0.007) * (1.0 - math.exp(-t / 0.0005))
        f = 1350.0 - 700.0 * min(1.0, t / 0.02)
        out.append(math.sin(2.0 * math.pi * f * t) * env)
    return write_raw("ui_click_raw.wav", out)


def gen_ui_tab() -> Path:
    dur = 0.075
    n = int(dur * RATE)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t / 0.015) * (1.0 - math.exp(-t / 0.001))
        f = 760.0 if t < 0.022 else 1080.0
        out.append(math.sin(2.0 * math.pi * f * t) * env)
    return write_raw("ui_tab_raw.wav", out)


def gen_ui_start() -> Path:
    dur = 0.28
    n = int(dur * RATE)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t / 0.075) * (1.0 - math.exp(-t / 0.003))
        s = (
            0.55 * math.sin(2.0 * math.pi * 220.0 * t)
            + 0.35 * math.sin(2.0 * math.pi * 330.0 * t)
            + 0.25 * math.sin(2.0 * math.pi * 440.0 * t)
        )
        out.append(s * env)
    return write_raw("ui_start_raw.wav", out)


def gen_lap_valid() -> Path:
    dur = 0.32
    n = int(dur * RATE)
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        n1 = math.sin(2.0 * math.pi * 880.0 * t) * math.exp(-t / 0.07) * (1.0 - math.exp(-t / 0.002))
        n2 = 0.0
        if t >= 0.075:
            dt = t - 0.075
            n2 = math.sin(2.0 * math.pi * 1174.66 * dt) * math.exp(-dt / 0.09) * (1.0 - math.exp(-dt / 0.002))
        out.append(n1 * 0.7 + n2 * 0.85)
    return write_raw("lap_valid_raw.wav", out)


def gen_lap_pb() -> Path:
    dur = 0.46
    n = int(dur * RATE)
    notes = [(0.0, 880.0, 0.08), (0.085, 1174.66, 0.09), (0.175, 1760.0, 0.14)]
    out: list[float] = []
    for i in range(n):
        t = i / RATE
        val = 0.0
        for t0, freq, tau in notes:
            if t >= t0:
                dt = t - t0
                val += math.sin(2.0 * math.pi * freq * dt) * math.exp(-dt / tau) * (1.0 - math.exp(-dt / 0.002))
        out.append(val)
    return write_raw("lap_pb_raw.wav", out)


def run_prep(args: list[str]) -> None:
    res = subprocess.run([sys.executable, str(PREP), *args], check=True)
    if res.returncode != 0:
        raise RuntimeError(f"audio_prep falhou: {args}")


def main() -> None:
    kerb_raw = gen_kerb_loop()
    scrape_raw = gen_bottom_scrape()
    bf1_raw = gen_backfire(1)
    bf2_raw = gen_backfire(2)
    bf3_raw = gen_backfire(3)
    click_raw = gen_ui_click()
    tab_raw = gen_ui_tab()
    start_raw = gen_ui_start()
    lap_ok_raw = gen_lap_valid()
    lap_pb_raw = gen_lap_pb()

    run_prep(["loop", str(kerb_raw), str(FX_DIR / "kerb_loop.wav"), "--duration", "1.6", "--crossfade", "0.15", "--hp", "30", "--lp", "450", "--peak", "-3.0"])
    # brake_squeal e gearbox_whine sintéticos removidos (usar gravações reais CC0 quando reativar)
    run_prep(["oneshot", str(scrape_raw), str(FX_DIR / "bottom_scrape.wav"), "--hp", "90", "--lp", "6500", "--peak", "-1.5"])
    run_prep(["oneshot", str(bf1_raw), str(FX_DIR / "backfire_1.wav"), "--hp", "38", "--lp", "1350", "--peak", "-1.2"])
    run_prep(["oneshot", str(bf2_raw), str(FX_DIR / "backfire_2.wav"), "--hp", "38", "--lp", "1350", "--peak", "-1.2"])
    run_prep(["oneshot", str(bf3_raw), str(FX_DIR / "backfire_3.wav"), "--hp", "38", "--lp", "1350", "--peak", "-1.2"])
    run_prep(["oneshot", str(click_raw), str(FX_DIR / "ui_click.wav"), "--peak", "-4.0"])
    run_prep(["oneshot", str(tab_raw), str(FX_DIR / "ui_tab.wav"), "--peak", "-4.5"])
    run_prep(["oneshot", str(start_raw), str(FX_DIR / "ui_start.wav"), "--peak", "-3.0"])
    run_prep(["oneshot", str(lap_ok_raw), str(FX_DIR / "lap_valid.wav"), "--peak", "-3.0"])
    run_prep(["oneshot", str(lap_pb_raw), str(FX_DIR / "lap_pb.wav"), "--peak", "-2.5"])

    print("Todos os novos FX e sons de UI foram gerados e preparados em assets/sounds/fx/.")


if __name__ == "__main__":
    main()
