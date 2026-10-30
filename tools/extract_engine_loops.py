"""Cut seamless, constant-pitch engine loops out of real car recordings for MANA OORU.

Each loop is resampled along the measured engine-order track so its pitch is constant
(a sweeping rev becomes a steady note), high-passed, loudness-matched and crossfaded
into a seamless loop. The native rpm goes into the file name, so the game can pitch
it as rpm / native_rpm.

Sources (Pixabay Content License, see ASSET_LICENSES.md):
  thar:    u_u5w7jl2icv-thar-jeep-on-offroad-185664.mp3  (Mahindra Thar off-road drive)
  porsche: freesound_community-porsche-105500.mp3         (Porsche 911 992 start + rev)

Needs ffmpeg and numpy.
Run: python3 tools/extract_engine_loops.py <thar.mp3> <porsche.mp3> assets/audio
"""
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 24000
TARGET_RMS = 0.2
PEAK_LIMIT = 0.9
CROSSFADE = 0.12


def decode(path: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    spectrum *= 1.0 / (1.0 + (cutoff / np.maximum(freqs, 1e-3)) ** 4)
    return np.fft.irfft(spectrum, n=len(x))


def track_order(x: np.ndarray, lo: float, hi: float, hop: float = 0.025, window: float = 0.25) -> tuple[np.ndarray, np.ndarray]:
    """Frequency (Hz) of the strongest spectral line between lo and hi, sampled every hop seconds."""
    size = int(window * RATE)
    times, freqs = [], []
    taper = np.hanning(size)
    for start in range(0, len(x) - size, int(hop * RATE)):
        spec = np.abs(np.fft.rfft(x[start:start + size] * taper, n=RATE * 4))
        bins = np.fft.rfftfreq(RATE * 4, 1.0 / RATE)
        band = (bins >= lo) & (bins <= hi)
        times.append((start + size / 2) / RATE)
        freqs.append(bins[band][np.argmax(spec[band])])
    freqs = np.array(freqs)
    # A short median filter removes single-frame jumps to a neighbouring harmonic.
    smoothed = np.array([np.median(freqs[max(0, i - 3):i + 4]) for i in range(len(freqs))])
    return np.array(times), smoothed


def flatten_pitch(x: np.ndarray, times: np.ndarray, freqs: np.ndarray, target: float) -> np.ndarray:
    """Resample so the tracked line sits at `target` Hz throughout."""
    t = np.arange(len(x)) / RATE
    inst = np.interp(t, times, freqs)
    phase = np.cumsum(inst) / RATE
    out_len = int(phase[-1] / target * RATE)
    out_phase = np.arange(out_len) * target / RATE
    source_time = np.interp(out_phase, phase, t)
    return np.interp(source_time, t, x)


def make_loop(x: np.ndarray) -> np.ndarray:
    fade = int(CROSSFADE * RATE)
    body = x[:-fade].copy()
    ramp = np.linspace(0.0, np.pi / 2, fade)
    body[:fade] = x[:fade] * np.sin(ramp) + x[-fade:] * np.cos(ramp)
    return body


def normalise(x: np.ndarray) -> np.ndarray:
    x = x - np.mean(x)
    x *= TARGET_RMS / np.sqrt(np.mean(x ** 2))
    peak = np.max(np.abs(x))
    if peak > PEAK_LIMIT:
        x *= PEAK_LIMIT / peak
    return x


def write_wav(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    print(f"WROTE {path} {len(x) / RATE:.2f}s rms={np.sqrt(np.mean(x ** 2)):.3f} peak={np.max(np.abs(x)):.3f}")


def cut(x: np.ndarray, start: float, end: float) -> np.ndarray:
    return x[int(start * RATE):int(end * RATE)]


def loop_from(x: np.ndarray, start: float, end: float, lo: float, hi: float, order: float, native_rpm: float,
              hp: float) -> np.ndarray:
    """`order` converts the tracked line to engine rpm: rpm = freq * 60 / order."""
    segment = highpass(cut(x, start, end), hp)
    times, freqs = track_order(segment, lo, hi)
    print(f"TRACK {start:.2f}-{end:.2f}s line {freqs.min():.1f}-{freqs.max():.1f} Hz "
          f"= {freqs.min() * 60 / order:.0f}-{freqs.max() * 60 / order:.0f} rpm")
    flat = flatten_pitch(segment, times, freqs, native_rpm * order / 60.0)
    return normalise(make_loop(flat))


def main() -> None:
    thar_path, porsche_path, out_dir = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    thar = decode(thar_path)
    # Four-cylinder four-stroke: 2 firings per revolution; the strongest line is the 4th firing harmonic (order 8).
    write_wav(out_dir / "thar_recorded" / "drive_2000rpm.wav",
              loop_from(thar, 20.0, 23.2, 240.0, 300.0, 8.0, 2000.0, 45.0))

    porsche = decode(porsche_path)
    # Flat-six four-stroke: 3 firings per revolution (order 3), the firing line is the lowest strong line.
    write_wav(out_dir / "porsche_911" / "idle_1150rpm.wav",
              loop_from(porsche, 2.25, 3.85, 50.0, 70.0, 3.0, 1150.0, 30.0))
    write_wav(out_dir / "porsche_911" / "rev_2600rpm.wav",
              loop_from(porsche, 4.55, 5.9, 90.0, 145.0, 3.0, 2600.0, 30.0))
    start = highpass(cut(porsche, 0.0, 1.45), 30.0)
    start *= np.minimum(1.0, (len(start) - np.arange(len(start))) / (0.25 * RATE))
    write_wav(out_dir / "porsche_911" / "start.wav", normalise(start))


main()
