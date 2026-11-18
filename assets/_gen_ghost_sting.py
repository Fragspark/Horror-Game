"""Erzeugt den dumpfen Bass-/Schock-Sound fuer das Lagerraum-Ereignis.

Der Sound ist ein kurzer, tiefer Einschlag: ein abwaerts gleitender Subbass
mit schnellem Attack, etwas zweiter Harmonischer fuer Koerper und einem
gefilterten Rausch-Transienten, der dem Ganzen den "Druck" gibt.
"""
import math
import random
import struct
import wave

ROOT = "C:/Users/Tamino/Documents/horror-game"
OUT = f"{ROOT}/assets/audio/ghost_sting.wav"

SR = 44100
DUR = 2.0
N = int(SR * DUR)

rnd = random.Random(1337)
samples = []
phase = 0.0
noise_lp = 0.0

for i in range(N):
    t = i / SR

    # Tiefe Frequenz gleitet schnell von 66 Hz auf ~32 Hz ab.
    freq = 32.0 + 34.0 * math.exp(-t / 0.28)
    phase += 2.0 * math.pi * freq / SR

    attack = min(1.0, t / 0.004)
    body_env = math.exp(-t / 0.55)

    # Grundton + Oktave: satt und dumpf.
    v = 0.95 * math.sin(phase) * body_env
    v += 0.20 * math.sin(2.0 * phase) * math.exp(-t / 0.30)

    # Kurzer, tiefpassgefilterter Rausch-Transient (kein heller Knall).
    noise = rnd.uniform(-1.0, 1.0)
    noise_lp += 0.055 * (noise - noise_lp)
    v += 0.55 * noise_lp * math.exp(-t / 0.13)

    # Weiche Saettigung gibt dem Bass Gewicht, ohne hart zu clippen.
    v = math.tanh(v * 1.35) * attack
    samples.append(v)

# Ausklingen sauber auf Null ziehen.
FADE = int(SR * 0.05)
for i in range(FADE):
    samples[N - FADE + i] *= 1.0 - (i / FADE)

peak = max(abs(s) for s in samples)
scale = 0.88 / peak
data = b"".join(
    struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples
)

with wave.open(OUT, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data)

print(f"OK: {OUT} ({N / SR:.2f}s, peak {peak:.3f})")
