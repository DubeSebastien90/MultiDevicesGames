"""Synthesises the hold-to-confirm gauge: assets/sdk/sfx/hold_00.wav .. hold_11.wav.

One short plucked tick per step, each a little higher than the last, one octave
from bottom to top. Played one after another as the ring fills, they read as a
gauge climbing — and because each is its own one-shot, the pitch follows the
ring exactly, including a hold that resumes from halfway after a slip.

Synthesised rather than recorded, so it lives here as a script instead of in
the Audacity project. Re-run from the repo root after changing a number:

    python audio-src/gen_hold_steps.py
"""

import math
import struct
import wave

STEPS = 12
RATE = 44100
LOW_HZ = 440.0  # A4 — lower than this, a phone speaker barely answers.
OCTAVES = 1.0
LENGTH_S = 0.09
ATTACK_S = 0.003
DECAY_TAU_S = 0.028
TAIL_FADE_S = 0.008
# Loudest 50ms, in dBFS RMS. The same level as the character voices (see
# README.md, "Levels"): the gauge is feedback the player is waiting on.
TARGET_DB = -12.0

# A touch of the second and third harmonics: a bare sine on a phone speaker
# reads as a test tone, this reads as a small bell.
HARMONICS = [(1, 1.0), (2, 0.28), (3, 0.08)]


def loudest_window_rms(samples: list[float], rate: int, window_s: float = 0.05) -> float:
    """RMS of the loudest 50ms: how loud a sound *sounds* at its peak, which is
    what compares a 60ms click with a 1s voice fairly — whole-file RMS reads a
    short sound as quieter than it is heard."""
    win = max(1, int(rate * window_s))
    hop = max(1, win // 4)
    best = 0.0
    for i in range(0, max(1, len(samples) - win + 1), hop):
        seg = samples[i : i + win]
        best = max(best, math.sqrt(sum(x * x for x in seg) / len(seg)))
    return best


def normalise(samples: list[float], rate: int, target_db: float) -> list[float]:
    """Scales [samples] so their loudest 50ms sit at [target_db], never letting
    a peak past -1 dBFS."""
    gain = 10 ** (target_db / 20) / loudest_window_rms(samples, rate)
    ceiling = 10 ** (-1 / 20) / max(abs(x) for x in samples)
    return [x * min(gain, ceiling) for x in samples]


def tick(freq: float) -> list[float]:
    n = int(RATE * LENGTH_S)
    fade_n = int(RATE * TAIL_FADE_S)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / ATTACK_S) * math.exp(-t / DECAY_TAU_S)
        if i >= n - fade_n:
            env *= (n - i) / fade_n
        s = sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in HARMONICS)
        out.append(s * env)
    return normalise(out, RATE, TARGET_DB)


def write(path: str, samples: list[float]) -> None:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", round(s * 32767)) for s in samples))


if __name__ == "__main__":
    for k in range(STEPS):
        freq = LOW_HZ * 2 ** (OCTAVES * k / (STEPS - 1))
        write(f"assets/sdk/sfx/hold_{k:02d}.wav", tick(freq))
        print(f"hold_{k:02d}.wav  {freq:7.1f} Hz")
