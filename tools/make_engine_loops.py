"""Cut seamless steady-rpm engine loops for the Thar from a CC0 diesel recording.

Source: "vw diesel engine.mp3" by Evilmikie (VW New Beetle 1.9 TDI, a four-cylinder
turbo-diesel like the Thar's 2.2 mHawk), CC0, https://freesound.org/s/448217/
Download the HQ preview, convert it, then run:
  ffmpeg -i 448217_8690770-hq.mp3 -ac 1 -ar 44100 -sample_fmt s16 vw44.wav
  python tools/make_engine_loops.py vw44.wav assets/audio/thar_diesel
Needs numpy and scipy. Each held rev is pitch-flattened to one firing frequency,
trimmed to a whole number of firing cycles and crossfaded tail-into-head, so the
game can loop it without a click or a wobble and pitch it by rpm.
"""
import os
import sys

import numpy as np
import scipy.io.wavfile as wavfile
import scipy.signal as signal

# (start s, end s, approximate firing frequency Hz) of steady held revs in the source.
SEGMENTS = [(71.9, 74.0, 29.9), (30.0, 33.5, 59.5), (82.0, 85.5, 72.9), (77.6, 79.4, 81.4), (35.4, 36.6, 104.0)]
XFADE_SECONDS = 0.04
TRACK_WINDOW = 0.12
TRACK_HOP = 0.01


def track_firing(seg: np.ndarray, sr: int, guess: float) -> tuple[np.ndarray, np.ndarray]:
    """Firing frequency over time from the strongest harmonic comb within ±20 % of the guess."""
    win = int(TRACK_WINDOW * sr)
    hop = int(TRACK_HOP * sr)
    n = 1 << 16
    freqs = np.fft.rfftfreq(n, 1 / sr)
    candidates = np.linspace(guess * 0.8, guess * 1.2, 241)
    combs = [np.searchsorted(freqs, np.arange(1, 9) * f) for f in candidates]
    times, track = [], []
    for start in range(0, len(seg) - win, hop):
        spectrum = np.log(np.abs(np.fft.rfft(seg[start:start + win] * np.hanning(win), n)) + 1e-9)
        scores = [spectrum[comb].sum() for comb in combs]
        times.append((start + win / 2) / sr)
        track.append(candidates[int(np.argmax(scores))])
    return np.array(times), signal.medfilt(np.array(track), 7)


def flatten(seg: np.ndarray, sr: int, guess: float) -> tuple[np.ndarray, float]:
    """Time-warps the segment so its firing frequency holds at the segment's median."""
    times, track = track_firing(seg, sr, guess)
    target = float(np.median(track))
    t = np.arange(len(seg)) / sr
    f = np.interp(t, times, track)
    phase = np.cumsum(f) / sr
    out_t = np.arange(int(phase[-1] / target * sr)) / sr
    source_t = np.interp(out_t * target, phase, t)
    return np.interp(source_t, t, seg), target


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    sr, raw = wavfile.read(src)
    x = raw.astype(np.float64) / 32768
    b, a = signal.butter(2, 22 / (sr / 2), "high")
    x = signal.filtfilt(b, a, x)
    xfade = int(XFADE_SECONDS * sr)
    fade = np.sin(np.linspace(0, np.pi / 2, xfade)) ** 2
    loops = []
    for start, end, guess in SEGMENTS:
        seg, firing = flatten(x[int(start * sr):int(end * sr)], sr, guess)
        period = sr / firing
        length = int(round(int((len(seg) - xfade) / period) * period))
        loop = seg[:length].copy()
        loop[:xfade] = seg[:xfade] * fade + seg[length:length + xfade] * (1 - fade)
        loops.append((round(firing * 30), loop))
    peak = max(np.abs(loop).max() for _, loop in loops)
    os.makedirs(out, exist_ok=True)
    for rpm, loop in loops:
        name = f"diesel_{rpm}rpm.wav"
        wavfile.write(os.path.join(out, name), sr, (loop / peak * 0.89 * 32767).astype(np.int16))
        rms = 20 * np.log10(np.sqrt(np.mean(loop ** 2)) / peak)
        print(f"{name}  {len(loop) / sr:.2f} s  rms {rms:.1f} dBFS")


main()
