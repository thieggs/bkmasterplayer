#!/usr/bin/env python3
"""Gera uma biblioteca de músicas sintéticas com gabarito conhecido.

Cada faixa com batida tem BPM, tom e estrutura (intro/main/break/outro) exatos,
gravados em dev/music/ground_truth.json. Serve para testar o motor (gapless,
crossfade) e, principalmente, a análise e as transições do AutoMix.

Uso: python3 dev/tools/gen_test_music.py [pasta_saida]
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

SR = 44100
RNG = np.random.default_rng(42)

NOTE_INDEX = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
              "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
# Roda Camelot: (tônica, modo) -> código
CAMELOT = {
    ("G#", "minor"): "1A", ("D#", "minor"): "2A", ("A#", "minor"): "3A", ("F", "minor"): "4A",
    ("C", "minor"): "5A", ("G", "minor"): "6A", ("D", "minor"): "7A", ("A", "minor"): "8A",
    ("E", "minor"): "9A", ("B", "minor"): "10A", ("F#", "minor"): "11A", ("C#", "minor"): "12A",
    ("B", "major"): "1B", ("F#", "major"): "2B", ("C#", "major"): "3B", ("G#", "major"): "4B",
    ("D#", "major"): "5B", ("A#", "major"): "6B", ("F", "major"): "7B", ("C", "major"): "8B",
    ("G", "major"): "9B", ("D", "major"): "10B", ("A", "major"): "11B", ("E", "major"): "12B",
}


def midi_freq(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env_exp(n, decay_s):
    t = np.arange(n) / SR
    return np.exp(-t / decay_s)


def kick(n):
    t = np.arange(n) / SR
    f = 50 + 100 * np.exp(-t / 0.04)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * env_exp(n, 0.18)


def snare(n):
    noise = RNG.standard_normal(n)
    noise = np.diff(noise, prepend=0)  # passa-alta simples
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 185 * t)
    return (0.6 * noise * env_exp(n, 0.09) + 0.5 * tone * env_exp(n, 0.06)) * 0.7


def hat(n):
    noise = RNG.standard_normal(n)
    noise = np.diff(np.diff(noise, prepend=0), prepend=0)
    return noise * env_exp(n, 0.025) * 0.18


def add(buf, start, sig, gain=1.0):
    if start >= len(buf):
        return
    end = min(len(buf), start + len(sig))
    buf[start:end] += sig[: end - start] * gain


def chord_midis(root, mode, degree):
    """Tríade do grau (0..6) na escala maior/menor natural, em torno de C4."""
    major = [0, 2, 4, 5, 7, 9, 11]
    minor = [0, 2, 3, 5, 7, 8, 10]
    scale = major if mode == "major" else minor
    base = 60 + NOTE_INDEX[root]
    notes = []
    for k in (0, 2, 4):
        idx = degree + k
        notes.append(base + scale[idx % 7] + 12 * (idx // 7))
    return notes


def pad(n, midis, gain):
    t = np.arange(n) / SR
    sig = sum(np.sin(2 * np.pi * midi_freq(m) * t) + 0.3 * np.sin(4 * np.pi * midi_freq(m) * t)
              for m in midis)
    fade = min(n // 4, int(0.05 * SR))
    env = np.ones(n)
    env[:fade] = np.linspace(0, 1, fade)
    env[-fade:] = np.linspace(1, 0, fade)
    return sig * env * gain / len(midis)


def beat_track(bpm, root, mode, sections):
    """sections: lista de (nome, compassos, elementos)."""
    beat = 60.0 / bpm
    bar = 4 * beat
    total_bars = sum(b for _, b, _ in sections)
    n = int(round(total_bars * bar * SR)) + SR // 2
    out = np.zeros(n)
    progression = [0, 5, 3, 4] if mode == "minor" else [0, 4, 5, 3]
    bar_idx = 0
    section_times = []
    for name, bars, elems in sections:
        section_times.append({"name": name, "start": round(bar_idx * bar, 6),
                              "bars": bars})
        for b in range(bars):
            bar_start = (bar_idx + b) * bar
            degree = progression[(bar_idx + b) % 4]
            for q in range(4):
                s = int(round((bar_start + q * beat) * SR))
                if "kick" in elems:
                    add(out, s, kick(int(0.35 * SR)), 0.9)
                if "snare" in elems and q in (1, 3):
                    add(out, s, snare(int(0.25 * SR)), 0.8)
                if "hat" in elems:
                    add(out, s + int(beat * SR / 2), hat(int(0.08 * SR)))
                if "bass" in elems:
                    root_midi = chord_midis(root, mode, degree)[0] - 24
                    bn = int(beat * SR / 2)
                    tt = np.arange(bn) / SR
                    bass_sig = np.sin(2 * np.pi * midi_freq(root_midi) * tt) * env_exp(bn, 0.12)
                    add(out, s + int(beat * SR / 2), bass_sig, 0.5)
            if "pad" in elems:
                s = int(round(bar_start * SR))
                add(out, s, pad(int(bar * SR), chord_midis(root, mode, degree), 0.35))
        bar_idx += bars
    return out, section_times


STRUCT = [
    ("intro", 8, {"kick", "hat"}),
    ("main", 16, {"kick", "snare", "hat", "bass", "pad"}),
    ("break", 4, {"pad"}),
    ("main2", 8, {"kick", "snare", "hat", "bass", "pad"}),
    ("outro", 8, {"kick", "hat"}),
]

BEAT_ALBUMS = [
    {
        "artist": "Sintético Beats", "album": "Pista Um", "year": 2024, "genre": "House",
        "color": ("0x1e3a8a", "0x9333ea"),
        "tracks": [("Abertura", 120, "A", "minor"), ("Segundo Passo", 122, "E", "minor"),
                   ("Terceira Via", 124, "C", "major"), ("Quarta Luz", 126, "G", "major")],
        "fmt": "flac",
    },
    {
        "artist": "Sintético Beats", "album": "Pista Dois", "year": 2025, "genre": "Electronic",
        "color": ("0x065f46", "0xfacc15"),
        "tracks": [("Velocidade", 128, "D", "minor"), ("Quebrada", 174, "F", "minor"),
                   ("Meio Tempo", 87, "F", "minor"), ("Cem", 100, "B", "major")],
        "fmt": "mp3",
    },
    {
        "artist": "Coletivo Ritmo", "album": "Formatos", "year": 2023, "genre": "Techno",
        "color": ("0x7f1d1d", "0xf97316"),
        "tracks": [("Em Ogg", 125, "A", "minor"), ("Em AAC", 125, "C", "major"),
                   ("Em Opus", 130, "E", "minor")],
        "fmt": ["ogg", "m4a", "opus"],
    },
]


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def make_cover(path, c0, c1, seed):
    run(["ffmpeg", "-y", "-f", "lavfi", "-i",
         f"gradients=s=600x600:c0={c0}:c1={c1}:seed={seed}:nb_colors=2",
         "-frames:v", "1", "-q:v", "3", path])


def encode(samples, path, fmt, tags):
    stereo = np.stack([samples, samples * 0.98], axis=1)
    peak = np.max(np.abs(stereo)) or 1.0
    stereo = (stereo / peak * 0.8).astype(np.float32)
    with tempfile.NamedTemporaryFile(suffix=".f32") as tmp:
        stereo.tofile(tmp.name)
        cmd = ["ffmpeg", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", tmp.name]
        for k, v in tags.items():
            cmd += ["-metadata", f"{k}={v}"]
        codec = {"flac": ["-c:a", "flac"], "mp3": ["-c:a", "libmp3lame", "-b:a", "192k"],
                 "ogg": ["-c:a", "libvorbis", "-q:a", "5"], "m4a": ["-c:a", "aac", "-b:a", "192k"],
                 "opus": ["-c:a", "libopus", "-b:a", "128k"]}[fmt]
        run(cmd + codec + [path])


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "music")
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    truth = {"sample_rate": SR, "tracks": []}
    seed = 1

    for alb in BEAT_ALBUMS:
        adir = os.path.join(out_dir, alb["artist"], alb["album"])
        os.makedirs(adir, exist_ok=True)
        make_cover(os.path.join(adir, "cover.jpg"), *alb["color"], seed)
        seed += 1
        for i, (title, bpm, root, mode) in enumerate(alb["tracks"], start=1):
            fmt = alb["fmt"][i - 1] if isinstance(alb["fmt"], list) else alb["fmt"]
            samples, sections = beat_track(bpm, root, mode, STRUCT)
            fname = f"{i:02d} - {title}.{fmt}"
            key_name = f"{root}{'m' if mode == 'minor' else ''}"
            tags = {"title": title, "artist": alb["artist"], "album_artist": alb["artist"],
                    "album": alb["album"], "track": f"{i}/{len(alb['tracks'])}",
                    "date": str(alb["year"]), "genre": alb["genre"], "BPM": str(bpm),
                    "TBPM": str(bpm), "INITIALKEY": key_name, "TKEY": key_name}
            encode(samples, os.path.join(adir, fname), fmt, tags)
            truth["tracks"].append({
                "path": os.path.relpath(os.path.join(adir, fname), out_dir),
                "title": title, "artist": alb["artist"], "album": alb["album"],
                "bpm": bpm, "key": key_name, "camelot": CAMELOT[(root, mode)],
                "first_downbeat": 0.0, "beats_per_bar": 4, "sections": sections,
                "duration": round(len(samples) / SR, 3),
            })
            print("ok", fname)

    # Faixa sem batida (fallback do AutoMix)
    adir = os.path.join(out_dir, "Onda Calma", "Ambiente")
    os.makedirs(adir, exist_ok=True)
    make_cover(os.path.join(adir, "cover.jpg"), "0x0f172a", "0x38bdf8", seed)
    seed += 1
    for i, (title, root, mode) in enumerate([("Névoa", "D", "major"), ("Maré", "A", "minor")], 1):
        n_bars = 12
        seg = int(4 * SR)
        buf = np.zeros(n_bars * seg + SR)
        prog = [0, 3, 4, 0]
        for b in range(n_bars):
            add(buf, b * seg, pad(seg, chord_midis(root, mode, prog[b % 4]), 0.6))
        fname = f"{i:02d} - {title}.flac"
        key_name = f"{root}{'m' if mode == 'minor' else ''}"
        encode(buf, os.path.join(adir, fname), "flac",
               {"title": title, "artist": "Onda Calma", "album_artist": "Onda Calma",
                "album": "Ambiente", "track": f"{i}/2", "date": "2022", "genre": "Ambient"})
        truth["tracks"].append({"path": os.path.relpath(os.path.join(adir, fname), out_dir),
                                "title": title, "artist": "Onda Calma", "album": "Ambiente",
                                "bpm": None, "key": key_name, "camelot": CAMELOT[(root, mode)],
                                "duration": round(len(buf) / SR, 3)})
        print("ok", fname)

    # Álbum gapless: uma varredura senoidal contínua cortada em 3 faixas em pontos
    # que não caem em fronteira de frame. Qualquer gap/clique entre faixas é detectável.
    t_total = 75.0
    n = int(t_total * SR)
    t = np.arange(n) / SR
    f = 220 * (880 / 220) ** (t / t_total)
    sweep = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.7
    cuts = [0, int(23.3217 * SR), int(51.0071 * SR), n]
    for fmt, album in (("flac", "Contínuo (FLAC)"), ("mp3", "Contínuo (MP3)")):
        adir = os.path.join(out_dir, "Teste Gapless", album)
        os.makedirs(adir, exist_ok=True)
        make_cover(os.path.join(adir, "cover.jpg"), "0x111827", "0x10b981", seed)
        seed += 1
        for i in range(3):
            fname = f"{i + 1:02d} - Parte {i + 1}.{fmt}"
            encode(sweep[cuts[i]:cuts[i + 1]], os.path.join(adir, fname), fmt,
                   {"title": f"Parte {i + 1}", "artist": "Teste Gapless",
                    "album_artist": "Teste Gapless", "album": album, "track": f"{i + 1}/3",
                    "date": "2021", "genre": "Test"})
            print("ok", fname)
        truth.setdefault("gapless_albums", []).append(
            {"album": album, "cut_samples": cuts, "sweep": {"f0": 220, "f1": 880, "seconds": t_total}})

    with open(os.path.join(out_dir, "ground_truth.json"), "w", encoding="utf-8") as fh:
        json.dump(truth, fh, ensure_ascii=False, indent=2)
    print("gabarito:", os.path.join(out_dir, "ground_truth.json"))


if __name__ == "__main__":
    main()
