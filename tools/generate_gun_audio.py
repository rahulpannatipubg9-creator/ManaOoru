#!/usr/bin/env python3
"""Generates the original gun sounds in assets/audio/guns/ (standard library only, no source recordings).

Run from the project root: python tools/generate_gun_audio.py
The seed is fixed, so the same files come out every time. scripts/gameplay/gun_feel.gd plays them.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join("assets", "audio", "guns")

# Each rifle's character. body_hz: chamber thump; crack: bright muzzle snap; tail: how long the town rings.
RIFLES = {
    "m416": {"body_hz": 165.0, "crack": 0.9, "body": 0.8, "tail": 0.32, "tail_seconds": 0.34, "tone": 0.35},
    "ak47": {"body_hz": 115.0, "crack": 0.75, "body": 1.0, "tail": 0.4, "tail_seconds": 0.42, "tone": 0.25},
    # The Bren in the game carries a suppressor: less snap and a shorter ring.
    "bren2": {"body_hz": 190.0, "crack": 0.35, "body": 0.55, "tail": 0.14, "tail_seconds": 0.2, "tone": 0.45},
}
VARIATIONS = 4


def write(name, samples, peak=0.89):
    biggest = max(max(abs(s) for s in samples), 1e-6)
    gain = peak / biggest
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * gain * 32767)) for s in samples))


def blank(seconds):
    return [0.0] * int(seconds * RATE)


def add(target, source, at=0.0, gain=1.0):
    start = int(at * RATE)
    for index, value in enumerate(source):
        if start + index >= len(target):
            break
        target[start + index] += value * gain


def low_pass(samples, cutoff):
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out = []
    level = 0.0
    for value in samples:
        level += alpha * (value - level)
        out.append(level)
    return out


def high_pass(samples, cutoff):
    smooth = low_pass(samples, cutoff)
    return [a - b for a, b in zip(samples, smooth)]


def noise(seconds, decay, rng):
    count = int(seconds * RATE)
    return [rng.uniform(-1.0, 1.0) * math.exp(-i / RATE / decay) for i in range(count)]


def sweep(start_hz, end_hz, seconds, decay):
    out = []
    phase = 0.0
    count = int(seconds * RATE)
    for i in range(count):
        t = i / count
        phase += 2.0 * math.pi * (start_hz + (end_hz - start_hz) * t) / RATE
        out.append(math.sin(phase) * math.exp(-i / RATE / decay))
    return out


def clip(samples, drive):
    return [math.tanh(s * drive) for s in samples]


def shot(profile, rng):
    wobble = rng.uniform(0.94, 1.06)
    seconds = 0.12 + profile["tail_seconds"]
    mix = blank(seconds)
    add(mix, high_pass(noise(0.03, 0.0035, rng), 1800.0), gain=profile["crack"] * 1.6)
    body = sweep(profile["body_hz"] * 2.3 * wobble, profile["body_hz"] * 0.55, 0.12, 0.032)
    add(mix, body, 0.0008, profile["body"] * 1.3)
    add(mix, low_pass(noise(0.12, 0.03, rng), 2400.0), 0.0005, profile["body"] * 1.1)
    tail = low_pass(noise(profile["tail_seconds"], profile["tail_seconds"] * 0.28, rng), 900.0 + 1500.0 * profile["tone"])
    add(mix, tail, 0.012, profile["tail"] * 2.2)
    # Two walls answering back: the street, not an empty room.
    add(mix, low_pass(body, 1200.0), rng.uniform(0.03, 0.045), 0.32 * profile["tail"] / 0.32)
    add(mix, low_pass(body, 800.0), rng.uniform(0.075, 0.1), 0.18 * profile["tail"] / 0.32)
    return clip(mix, 1.5)


def distant(rng):
    seconds = 0.7
    mix = blank(seconds)
    add(mix, low_pass(noise(0.1, 0.03, rng), 500.0), 0.0, 2.2)
    add(mix, low_pass(noise(0.65, 0.17, rng), 320.0), 0.02, 2.4)
    return clip(mix, 1.2)


def near_crack(rng):
    mix = blank(0.09)
    add(mix, high_pass(noise(0.012, 0.0014, rng), 2600.0), 0.0, 1.6)
    add(mix, low_pass(noise(0.08, 0.018, rng), 1700.0), 0.003, 0.25)
    return mix


def click(rng, hz=2100.0, seconds=0.05, gain=1.0):
    mix = blank(seconds)
    add(mix, high_pass(noise(0.012, 0.0016, rng), 1400.0), 0.0, 1.0 * gain)
    add(mix, sweep(hz, hz * 0.7, seconds, 0.006), 0.0, 0.4 * gain)
    return mix


def mag_out(rng):
    mix = blank(0.3)
    add(mix, click(rng, 1500.0, 0.05), 0.0)
    add(mix, low_pass(noise(0.2, 0.05, rng), 2300.0), 0.02, 0.32)
    add(mix, click(rng, 900.0, 0.05, 0.55), 0.19)
    return mix


def mag_in(rng):
    mix = blank(0.24)
    add(mix, low_pass(noise(0.09, 0.025, rng), 2000.0), 0.0, 0.3)
    add(mix, sweep(420.0, 260.0, 0.05, 0.012), 0.06, 0.6)
    add(mix, click(rng, 1800.0, 0.05, 1.1), 0.065)
    return mix


def bolt(rng):
    mix = blank(0.3)
    add(mix, click(rng, 1250.0, 0.05, 0.9), 0.0)
    add(mix, low_pass(noise(0.09, 0.03, rng), 3000.0), 0.012, 0.22)
    add(mix, click(rng, 2300.0, 0.05, 1.2), 0.17)
    add(mix, sweep(330.0, 210.0, 0.05, 0.012), 0.175, 0.4)
    return mix


def hit_body(rng):
    mix = blank(0.12)
    add(mix, sweep(230.0, 80.0, 0.1, 0.022), 0.0, 1.0)
    add(mix, low_pass(noise(0.08, 0.012, rng), 1500.0), 0.0, 0.8)
    return clip(mix, 1.4)


def hit_head(rng):
    mix = blank(0.2)
    for hz, gain, decay in [(1850.0, 0.7, 0.045), (2960.0, 0.5, 0.03), (4310.0, 0.3, 0.018)]:
        add(mix, sweep(hz, hz * 0.985, 0.2, decay), 0.0, gain)
    add(mix, high_pass(noise(0.01, 0.0015, rng), 2000.0), 0.0, 0.5)
    return mix


def kill_confirm():
    mix = blank(0.3)
    add(mix, sweep(740.0, 735.0, 0.1, 0.035), 0.0, 0.7)
    add(mix, sweep(1110.0, 1100.0, 0.2, 0.06), 0.075, 0.8)
    return mix


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(20261030)
    for rifle, profile in RIFLES.items():
        for variation in range(1, VARIATIONS + 1):
            write("%s_%d" % (rifle, variation), shot(profile, rng))
    for variation in range(1, 3):
        write("distant_%d" % variation, distant(rng), 0.8)
    write("near_crack", near_crack(rng), 0.7)
    write("dry_click", click(rng), 0.45)
    write("mag_out", mag_out(rng), 0.6)
    write("mag_in", mag_in(rng), 0.65)
    write("bolt", bolt(rng), 0.65)
    write("hit_body", hit_body(rng), 0.75)
    write("hit_head", hit_head(rng), 0.6)
    write("kill_confirm", kill_confirm(), 0.55)


if __name__ == "__main__":
    main()
