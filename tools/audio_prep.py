#!/usr/bin/env python3
"""Pipeline automatizado de preparo e inspeção de áudio para o gt3-godot.

Requer Python 3.13+ e FFmpeg (no PATH).

Modos de uso:
  python tools/audio_prep.py oneshot <entrada> <saida.wav> [--peak -1.5] [--hp 0] [--lp 0]
  python tools/audio_prep.py loop <entrada> <saida.wav> [--duration 1.5] [--crossfade 0.15] [--hp 0] [--lp 0] [--peak -3.0]
  python tools/audio_prep.py inspect [caminho] [--json relatorio.json]
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path
from typing import Any


TARGET_RATE = 44100


def _run_ffmpeg(args: list[str]) -> None:
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *args]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"FFmpeg falhou ({res.returncode}): {res.stderr.strip()}")


def _read_wav_mono_i16(path: Path) -> tuple[list[int], int]:
    with wave.open(str(path), "rb") as wf:
        ch = wf.getnchannels()
        sw = wf.getsampwidth()
        rate = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
    if sw != 2 or ch != 1:
        raise ValueError(f"Esperado WAV 16-bit mono, obtido {sw * 8}-bit {ch}ch em {path}")
    samples = list(struct.unpack(f"<{n}h", raw))
    return samples, rate


def _write_wav_mono_i16(path: Path, samples: list[int], rate: int, with_smpl_loop: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    clamped = [max(-32768, min(32767, int(round(s)))) for s in samples]
    pcm = struct.pack(f"<{len(clamped)}h", *clamped)

    if not with_smpl_loop:
        with wave.open(str(path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(rate)
            wf.writeframes(pcm)
        return

    # Monta WAV RIFF padrão com chunk 'smpl' para metadados de loop
    n_samples = len(clamped)
    fmt_chunk = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, 1, rate, rate * 2, 2, 16)
    data_chunk = struct.pack("<4sI", b"data", len(pcm)) + pcm

    sample_period_ns = int(round(1_000_000_000 / rate))
    # smpl: 9 uint32 + 1 loop (6 uint32) = 60 bytes
    smpl_body = struct.pack(
        "<IIIIIIIIIIIIIII",
        0,                  # manufacturer
        0,                  # product
        sample_period_ns,   # sample period (ns)
        60,                 # MIDI unity note
        0,                  # MIDI pitch fraction
        0,                  # SMPTE format
        0,                  # SMPTE offset
        1,                  # num sample loops
        0,                  # sampler data
        0,                  # loop cue point ID
        0,                  # loop type (0 = forward)
        0,                  # loop start (sample)
        max(0, n_samples - 1),  # loop end (sample)
        0,                  # fraction
        0,                  # play count (0 = infinite)
    )
    smpl_chunk = struct.pack("<4sI", b"smpl", len(smpl_body)) + smpl_body

    riff_size = 4 + len(fmt_chunk) + len(data_chunk) + len(smpl_chunk)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sI4s", b"RIFF", riff_size, b"WAVE"))
        f.write(fmt_chunk)
        f.write(data_chunk)
        f.write(smpl_chunk)


def _normalize_peak(samples: list[float], target_dbfs: float) -> list[int]:
    if not samples:
        return []
    peak = max(abs(s) for s in samples)
    if peak < 1.0:
        return [0] * len(samples)
    target_amp = 32767.0 * (10.0 ** (target_dbfs / 20.0))
    scale = target_amp / peak
    return [max(-32768, min(32767, int(round(s * scale)))) for s in samples]


def _find_zero_crossing(samples: list[float], target_idx: int, search_radius: int) -> int:
    n = len(samples)
    lo = max(1, target_idx - search_radius)
    hi = min(n - 1, target_idx + search_radius)
    best_idx = target_idx
    best_score = float("inf")
    for i in range(lo, hi + 1):
        prev_s = samples[i - 1]
        curr_s = samples[i]
        # Prefere cruzamento ascendente ou ponto mais próximo de zero
        crossed = (prev_s <= 0.0 <= curr_s) or (prev_s >= 0.0 >= curr_s)
        score = abs(curr_s) + (0.0 if crossed else 10000.0)
        if prev_s <= 0.0 <= curr_s:
            score -= 500.0
        if score < best_score:
            best_score = score
            best_idx = i
    return best_idx


def _pick_steadiest_window(samples: list[float], win_len: int, rate: int) -> int:
    n = len(samples)
    if n <= win_len:
        return 0
    block = max(1, int(rate * 0.05))  # blocos de 50 ms
    rms_blocks: list[float] = []
    for start in range(0, n - block + 1, block):
        seg = samples[start : start + block]
        rms_blocks.append(math.sqrt(sum(x * x for x in seg) / len(seg)))
    blocks_per_win = max(2, win_len // block)
    if len(rms_blocks) <= blocks_per_win:
        return 0

    best_b = 0
    best_score = float("inf")
    for b in range(0, len(rms_blocks) - blocks_per_win + 1):
        sub = rms_blocks[b : b + blocks_per_win]
        mean = sum(sub) / len(sub)
        if mean < 150.0:  # ignora trechos quase silenciosos
            continue
        var = sum((x - mean) ** 2 for x in sub) / len(sub)
        cv = math.sqrt(var) / max(1.0, mean)
        if cv < best_score:
            best_score = cv
            best_b = b
    return min(n - win_len, best_b * block)


def cmd_oneshot(args: argparse.Namespace) -> None:
    inp = Path(args.input)
    out = Path(args.output)
    if not inp.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {inp}")

    filters: list[str] = []
    if args.hp > 0:
        filters.append(f"highpass=f={args.hp}")
    if args.lp > 0:
        filters.append(f"lowpass=f={args.lp}")
    # Remove silêncio inicial e final
    filters.append("silenceremove=start_periods=1:start_duration=0:start_threshold=-50dB")
    filters.append("areverse")
    filters.append("silenceremove=start_periods=1:start_duration=0:start_threshold=-50dB")
    filters.append("areverse")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_wav = Path(tmp) / "clean.wav"
        _run_ffmpeg([
            "-i", str(inp),
            "-af", ",".join(filters),
            "-ac", "1",
            "-ar", str(args.rate),
            "-sample_fmt", "s16",
            str(tmp_wav),
        ])
        samples, rate = _read_wav_mono_i16(tmp_wav)

    if not samples:
        raise RuntimeError(f"Áudio resultante vazio após corte de silêncio: {inp}")

    # Pequeno fade-in/out de 2 ms para evitar estalo nas pontas
    fade_n = min(len(samples) // 4, max(1, int(rate * 0.002)))
    fsamples = [float(s) for s in samples]
    for i in range(fade_n):
        k = i / fade_n
        fsamples[i] *= k
        fsamples[-(i + 1)] *= k

    norm = _normalize_peak(fsamples, args.peak)
    _write_wav_mono_i16(out, norm, rate, with_smpl_loop=False)
    print(f"[oneshot] {inp.name} -> {out} ({len(norm) / rate:.3f}s, pico {args.peak:.1f} dBFS)")


def cmd_loop(args: argparse.Namespace) -> None:
    inp = Path(args.input)
    out = Path(args.output)
    if not inp.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {inp}")

    filters: list[str] = []
    if args.hp > 0:
        filters.append(f"highpass=f={args.hp}")
    if args.lp > 0:
        filters.append(f"lowpass=f={args.lp}")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_wav = Path(tmp) / "filtered.wav"
        ff_args = ["-i", str(inp)]
        if filters:
            ff_args += ["-af", ",".join(filters)]
        ff_args += ["-ac", "1", "-ar", str(args.rate), "-sample_fmt", "s16", str(tmp_wav)]
        _run_ffmpeg(ff_args)
        samples, rate = _read_wav_mono_i16(tmp_wav)

    fsamples = [float(s) for s in samples]
    xfade_n = max(16, int(round(args.crossfade * rate)))
    target_n = max(xfade_n * 2, int(round(args.duration * rate)))
    needed_n = target_n + xfade_n

    if len(fsamples) > needed_n:
        start = _pick_steadiest_window(fsamples, needed_n, rate)
        seg = fsamples[start : start + needed_n]
    else:
        seg = fsamples

    if len(seg) < xfade_n * 3:
        xfade_n = max(8, len(seg) // 4)

    # Ajusta pontas para cruzamento por zero
    search_r = min(int(rate * 0.015), len(seg) // 8)
    head_idx = _find_zero_crossing(seg, 0, search_r)
    tail_idx = _find_zero_crossing(seg, len(seg) - 1, search_r)
    if tail_idx - head_idx > xfade_n * 2:
        seg = seg[head_idx : tail_idx + 1]

    loop_len = len(seg) - xfade_n
    out_samples = list(seg[:loop_len])
    tail = seg[loop_len:]

    # Crossfade de mesma potência (cos/sin) entre fim (tail) e início (out_samples[:xfade_n])
    for i in range(xfade_n):
        t = i / float(xfade_n)
        w_head = math.sin(t * math.pi * 0.5)
        w_tail = math.cos(t * math.pi * 0.5)
        out_samples[i] = out_samples[i] * w_head + tail[i] * w_tail

    norm = _normalize_peak(out_samples, args.peak)
    _write_wav_mono_i16(out, norm, rate, with_smpl_loop=True)
    print(f"[loop] {inp.name} -> {out} ({len(norm) / rate:.3f}s, xfade {xfade_n * 1000 / rate:.0f} ms, pico {args.peak:.1f} dBFS)")


def _has_smpl_chunk(path: Path) -> bool:
    try:
        with open(path, "rb") as f:
            header = f.read(12)
            if len(header) < 12 or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
                return False
            while True:
                ch = f.read(8)
                if len(ch) < 8:
                    break
                cid, csize = struct.unpack("<4sI", ch)
                if cid == b"smpl":
                    return True
                f.seek(csize + (csize & 1), os.SEEK_CUR)
    except OSError:
        pass
    return False


def _dominant_freq_hz(samples: list[int], rate: int) -> float:
    if not samples:
        return 0.0
    # Pega janela de 2048 amostras ao redor do trecho de maior energia (com decimação para cobrir até ~11 kHz)
    win = 2048
    if len(samples) <= win:
        seg = [float(s) for s in samples]
    else:
        best_i = 0
        best_e = -1.0
        step = max(1, (len(samples) - win) // 16)
        for i in range(0, len(samples) - win + 1, step):
            e = sum(samples[j] * samples[j] for j in range(i, i + win, 8))
            if e > best_e:
                best_e = e
                best_i = i
        seg = [float(s) for s in samples[best_i : best_i + win]]

    n = len(seg)
    # Janela de Hann
    windowed = [seg[i] * (0.5 - 0.5 * math.cos(2.0 * math.pi * i / max(1, n - 1))) for i in range(n)]
    # Subamostragem 2x se n == 2048 -> 1024 pontos para DFT rápida em Python puro
    if n >= 1024:
        windowed = windowed[::2]
        eff_rate = rate / 2.0
    else:
        eff_rate = float(rate)

    m = len(windowed)
    # Avalia bins de 30 Hz até min(8000 Hz, eff_rate / 2)
    k_min = max(1, int(30.0 * m / eff_rate))
    k_max = min(m // 2 - 1, int(8000.0 * m / eff_rate))
    best_k = k_min
    best_mag2 = -1.0
    two_pi_over_m = 2.0 * math.pi / m
    for k in range(k_min, k_max + 1):
        w = two_pi_over_m * k
        cw = math.cos(w)
        coeff = 2.0 * cw
        s_prev = 0.0
        s_prev2 = 0.0
        for x in windowed:
            s_curr = x + coeff * s_prev - s_prev2
            s_prev2 = s_prev
            s_prev = s_curr
        mag2 = s_prev2 * s_prev2 + s_prev * s_prev - coeff * s_prev * s_prev2
        if mag2 > best_mag2:
            best_mag2 = mag2
            best_k = k
    return round(best_k * eff_rate / m, 1)


def _inspect_wav(path: Path, root_dir: Path) -> dict[str, Any]:
    with wave.open(str(path), "rb") as wf:
        ch = wf.getnchannels()
        sw = wf.getsampwidth()
        rate = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    if sw == 2:
        total = n_frames * ch
        vals = struct.unpack(f"<{total}h", raw)
        if ch > 1:
            mono = [sum(vals[i : i + ch]) // ch for i in range(0, total, ch)]
        else:
            mono = list(vals)
        max_val = 32768.0
    elif sw == 1:
        vals = struct.unpack(f"<{n_frames * ch}B", raw)
        mono = [(v - 128) * 256 for v in vals[::ch]]
        max_val = 32768.0
    else:
        mono = []
        max_val = 1.0

    peak = max((abs(s) for s in mono), default=0)
    rms = math.sqrt(sum(s * s for s in mono) / max(1, len(mono))) if mono else 0.0
    peak_dbfs = round(20.0 * math.log10(max(1e-9, peak / max_val)), 2)
    rms_dbfs = round(20.0 * math.log10(max(1e-9, rms / max_val)), 2)
    dom_hz = _dominant_freq_hz(mono, rate)

    try:
        rel = str(path.relative_to(root_dir)).replace("\\", "/")
    except ValueError:
        rel = str(path).replace("\\", "/")

    return {
        "file": rel,
        "duration_s": round(n_frames / max(1, rate), 3),
        "sample_rate": rate,
        "channels": ch,
        "bits": sw * 8,
        "rms_dbfs": rms_dbfs,
        "peak_dbfs": peak_dbfs,
        "dominant_hz": dom_hz,
        "has_smpl_loop": _has_smpl_chunk(path),
    }


def cmd_inspect(args: argparse.Namespace) -> None:
    target = Path(args.path)
    if not target.exists():
        raise FileNotFoundError(f"Caminho não encontrado: {target}")

    files = [target] if target.is_file() else sorted(target.rglob("*.wav"))
    root_dir = target.parent if target.is_file() else target
    results = [_inspect_wav(f, root_dir) for f in files]

    report = {
        "count": len(results),
        "files": results,
    }

    if args.json:
        out_json = Path(args.json)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"[inspect] Relatório salvo em {out_json} ({len(results)} arquivos)")
    else:
        print(json.dumps(report, indent=2, ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser(description="Pipeline de preparo e inspeção de áudio do gt3-godot.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_one = sub.add_parser("oneshot", help="Corta silêncio, normaliza e converte para WAV 44.1kHz mono.")
    p_one.add_argument("input")
    p_one.add_argument("output")
    p_one.add_argument("--peak", type=float, default=-1.5, help="Pico alvo em dBFS (padrão: -1.5).")
    p_one.add_argument("--hp", type=float, default=0.0, help="Filtro high-pass em Hz (0 = desligado).")
    p_one.add_argument("--lp", type=float, default=0.0, help="Filtro low-pass em Hz (0 = desligado).")
    p_one.add_argument("--rate", type=int, default=TARGET_RATE)
    p_one.set_defaults(func=cmd_oneshot)

    p_loop = sub.add_parser("loop", help="Cria loop contínuo sem estalos com crossfade e metadados smpl.")
    p_loop.add_argument("input")
    p_loop.add_argument("output")
    p_loop.add_argument("--duration", type=float, default=1.5, help="Duração alvo em segundos (padrão: 1.5).")
    p_loop.add_argument("--crossfade", type=float, default=0.15, help="Duração do crossfade em segundos (padrão: 0.15).")
    p_loop.add_argument("--peak", type=float, default=-3.0, help="Pico alvo em dBFS (padrão: -3.0).")
    p_loop.add_argument("--hp", type=float, default=0.0, help="Filtro high-pass em Hz (0 = desligado).")
    p_loop.add_argument("--lp", type=float, default=0.0, help="Filtro low-pass em Hz (0 = desligado).")
    p_loop.add_argument("--rate", type=int, default=TARGET_RATE)
    p_loop.set_defaults(func=cmd_loop)

    p_ins = sub.add_parser("inspect", help="Gera relatório JSON de duração, RMS, pico dBFS e frequência dominante.")
    p_ins.add_argument("path", nargs="?", default="assets/sounds", help="Diretório ou arquivo WAV.")
    p_ins.add_argument("--json", default="", help="Caminho opcional para salvar o relatório JSON.")
    p_ins.set_defaults(func=cmd_inspect)

    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
