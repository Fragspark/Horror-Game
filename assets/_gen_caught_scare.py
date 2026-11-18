"""Erzeugt den lauten Schreck-Stinger, wenn der Stalker den Spieler erwischt.

Kurzer, aggressiver Jumpscare: ein schriller, leicht verstimmter Kreisch-Ton
mit schnellem Attack, ein harscher Rausch-Transient und ein tiefer Subbass-
Einschlag darunter. Die Sättigung sorgt fuer Druck, ohne hart zu clippen.
"""
import math
import random
import struct
import wave

ROOT = "C:/Users/Tamino/Documents/horror-game"
OUT = f"{ROOT}/assets/audio/caught_scare.wav"

SR = 44100
DUR = 1.5
N = int(SR * DUR)

rnd = random.Random(9001)
samples = []
phase_a = 0.0
phase_b = 0.0
phase_sub = 0.0
noise_lp = 0.0

for i in range(N):
    t = i / SR
    attack = min(1.0, t / 0.002)

    # Schriller, aufsteigender Kreisch-Ton (zwei leicht verstimmte Saegezaehne).
    freq_a = 620.0 + 520.0 * min(1.0, t / 0.10) + 90.0 * math.sin(2.0 * math.pi * 9.0 * t)
    freq_b = freq_a * 1.047
    phase_a += 2.0 * math.pi * freq_a / SR
    phase_b += 2.0 * math.pi * freq_b / SR
    scream = 0.34 * math.sin(phase_a * 2.0) + 0.24 * math.sin(phase_b * 2.0)
    scream += 0.18 * math.sin(phase_a * 3.0) + 0.12 * math.sin(phase_b * 5.0)
    scream_env = math.exp(-t / 0.45)

    # Harscher Rausch-Transient (Hochpass ueber Differenz zum Tiefpass).
    noise = rnd.uniform(-1.0, 1.0)
    noise_lp += 0.20 * (noise - noise_lp)
    hiss = noise - noise_lp
    hiss_env = math.exp(-t / 0.18)

    # Tiefer Einschlag darunter.
    sub_freq = 48.0 + 20.0 * math.exp(-t / 0.12)
    phase_sub += 2.0 * math.pi * sub_freq / SR
    sub = math.sin(phase_sub) * math.exp(-t / 0.30)

    v = scream * scream_env + 0.65 * hiss * hiss_env + 0.80 * sub
    v = math.tanh(v * 2.1) * attack
    samples.append(v)

# Sauberes Ausklingen.
FADE = int(SR * 0.08)
for i in range(FADE):
    samples[N - FADE + i] *= 1.0 - (i / FADE)

peak = max(abs(s) for s in samples)
scale = 0.97 / peak
data = b"".join(
    struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples
)

with wave.open(OUT, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data)

print(f"OK: {OUT} ({N / SR:.2f}s, peak {peak:.3f})")
