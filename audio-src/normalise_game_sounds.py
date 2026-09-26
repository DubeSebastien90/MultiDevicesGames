"""Levels every game's own sounds: originals/games/<id>/* -> assets/games/<id>/*.wav

Drop the untouched export in audio-src/originals/games/<id>/, run this from the
repo root, and the bundled copy lands in assets/games/<id>/ with the same
treatment as the SDK's sounds (see README.md):

- downmixed to mono,
- leading silence trimmed,
- the loudest 50ms at TARGET_DB, peaks held under -1 dBFS.

Reads anything miniaudio decodes (wav, mp3, flac, ogg) and always writes a
16-bit wav:

    pip install miniaudio
    python audio-src/normalise_game_sounds.py            # every game
    python audio-src/normalise_game_sounds.py hotpotato  # one game
"""

import math
import pathlib
import struct
import sys
import wave

import miniaudio

ORIGINALS = pathlib.Path("audio-src/originals/games")
ASSETS = pathlib.Path("assets/games")
FORMATS = {".wav", ".mp3", ".flac", ".ogg"}

# Loudest 50ms, in dBFS RMS: the character voices' band (README.md, "Levels").
TARGET_DB = -11.0
SILENCE = 0.001  # -60 dBFS: anything quieter at the start is latency.


def load_mono(path: pathlib.Path) -> tuple[list[float], int]:
    d = miniaudio.decode_file(str(path), output_format=miniaudio.SampleFormat.FLOAT32)
    s, ch = d.samples, d.nchannels
    mono = [sum(s[i + c] for c in range(ch)) / ch for i in range(0, len(s), ch)]
    start = next((i for i, x in enumerate(mono) if abs(x) > SILENCE), 0)
    return mono[start:], d.sample_rate


def loudest_window_rms(samples: list[float], rate: int, window_s: float = 0.05) -> float:
    win = max(1, min(len(samples), int(rate * window_s)))
    hop = max(1, win // 4)
    best = 0.0
    for i in range(0, max(1, len(samples) - win + 1), hop):
        seg = samples[i : i + win]
        best = max(best, math.sqrt(sum(x * x for x in seg) / len(seg)))
    return best


def db(x: float) -> float:
    return 20 * math.log10(max(x, 1e-9))


def normalise(samples: list[float], rate: int) -> tuple[list[float], float]:
    gain = 10 ** (TARGET_DB / 20) / loudest_window_rms(samples, rate)
    ceiling = 10 ** (-1 / 20) / max(abs(x) for x in samples)
    g = min(gain, ceiling)
    return [x * g for x in samples], db(g)


def write(path: pathlib.Path, samples: list[float], rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(
            b"".join(
                struct.pack("<h", round(max(-1.0, min(1.0, x)) * 32767))
                for x in samples
            )
        )


if __name__ == "__main__":
    games = sys.argv[1:] or sorted(p.name for p in ORIGINALS.iterdir() if p.is_dir())
    for game in games:
        for src in sorted((ORIGINALS / game).iterdir()):
            if src.suffix.lower() not in FORMATS:
                continue
            mono, rate = load_mono(src)
            before = db(loudest_window_rms(mono, rate))
            out, gain = normalise(mono, rate)
            after = db(loudest_window_rms(out, rate))
            dst = ASSETS / game / (src.stem + ".wav")
            write(dst, out, rate)
            print(f"{game}/{dst.name:28} {before:6.1f} -> {after:6.1f} dB  ({gain:+.1f} dB)")
