"""Builds the menu button sound: assets/sdk/sfx/boup_0.wav .. boup_4.wav.

Five copies of originals/snd_boup.mp3, each at a slightly different pitch
between -0.9% and +1.1%, so a run of taps does not sound like one sample on
repeat. The app picks one at random per press.

Pre-rendered rather than varied at playback: on iOS, audioplayers changes rate
with a pitch-preserving algorithm, so a playback-rate trick would be heard on
Android and not on an iPhone.

Same treatment as the other assets (see README.md): mono, leading silence
trimmed. Needs the `miniaudio` package to decode the mp3:

    pip install miniaudio
    python audio-src/gen_boup_variants.py
"""

import math
import struct
import wave

import miniaudio

SOURCE = "audio-src/originals/snd_boup.mp3"
PITCHES = [-0.009, -0.004, 0.001, 0.006, 0.011]
SILENCE = 0.001  # -60 dBFS: anything quieter at the start is latency.

# Loudest 50ms, in dBFS RMS. Six under the voices and the gauge (see
# README.md, "Levels"): it answers every tap in every menu, and a sound heard
# that often should sit under the ones that mean something.
TARGET_DB = -18.0


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


def load_mono(path: str) -> tuple[list[float], int]:
    d = miniaudio.decode_file(path, output_format=miniaudio.SampleFormat.FLOAT32)
    s, ch = d.samples, d.nchannels
    mono = [sum(s[i + c] for c in range(ch)) / ch for i in range(0, len(s), ch)]
    start = next((i for i, x in enumerate(mono) if abs(x) > SILENCE), 0)
    return mono[start:], d.sample_rate


def repitch(samples: list[float], pitch: float) -> list[float]:
    """Plays [samples] faster by (1 + pitch): higher and a touch shorter."""
    rate = 1 + pitch
    out = []
    pos = 0.0
    while pos < len(samples) - 1:
        i = int(pos)
        frac = pos - i
        out.append(samples[i] * (1 - frac) + samples[i + 1] * frac)
        pos += rate
    return out


def write(path: str, samples: list[float], rate: int) -> None:
    with wave.open(path, "wb") as w:
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
    mono, rate = load_mono(SOURCE)
    mono = normalise(mono, rate, TARGET_DB)
    for k, pitch in enumerate(PITCHES):
        write(f"assets/sdk/sfx/boup_{k}.wav", repitch(mono, pitch), rate)
        print(f"boup_{k}.wav  {pitch * 100:+.1f}%")
