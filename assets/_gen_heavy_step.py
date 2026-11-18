"""Erzeugt ein schweres, dumpfes Schrittgeraeusch fuer den Stalker."""
import math
import random
import struct
import wave

ROOT = "C:/Users/Tamino/Documents/horror-game"
OUT = f"{ROOT}/assets/audio/heavy_step.wav"

SR = 44100
DUR = 0.7
N = int(SR * DUR)

rnd = random.Random(4242)
samples = []
phase = 0.0
noise_lp = 0.0

for i in range(N):
    t = i / SR

    freq = 44.0 + 18.0 * math.exp(-t / 0.10)
    phase += 2.0 * math.pi * freq / SR

    attack = min(1.0, t / 0.003)
    env = math.exp(-t / 0.16)

    # Tiefe Masse + kurzer Koerper.
    v = 0.95 * math.sin(phase) * env
    v += 0.28 * math.sin(2.0 * phase) * math.exp(-t / 0.09)

    # Gedämpftes Rauschen fuer den Aufprall auf Beton.
    noise = rnd.uniform(-1.0, 1.0)
    noise_lp += 0.07 * (noise - noise_lp)
    v += 0.6 * noise_lp * math.exp(-t / 0.06)

    v = math.tanh(v * 1.5) * attack
    samples.append(v)

FADE = int(SR * 0.08)
for i in range(FADE):
    samples[N - FADE + i] *= 1.0 - (i / FADE)

peak = max(abs(s) for s in samples)
scale = 0.82 / peak
data = b"".join(
    struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples
)

with wave.open(OUT, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data)

print(f"OK: {OUT} ({N / SR:.2f}s, peak {peak:.3f})")
