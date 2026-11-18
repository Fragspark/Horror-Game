"""Erzeugt die zwei Platzhalter-Assets fuer den Benzinkanister."""
import math, struct, wave
from PIL import Image, ImageDraw

ROOT = "C:/Users/Tamino/Documents/horror-game"

# ---------------------------------------------------------------- Benzinkanister-Icon
S = 128
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

RED   = (168, 42, 32, 255)
DRED  = (120, 24, 20, 255)
HI    = (208, 74, 58, 255)
DARK  = (44, 34, 30, 255)
CAP   = (92, 92, 96, 255)

# Korpus mit abgeschraegter Schulter
d.polygon([(24, 48), (40, 32), (86, 32), (104, 48), (104, 108), (24, 108)], fill=RED)
d.line([(24, 48), (40, 32), (86, 32), (104, 48)], fill=HI, width=3)
# Stutzen oben rechts
d.rectangle([80, 18, 96, 34], fill=CAP)
d.ellipse([77, 12, 99, 24], fill=CAP)
# Griff / Aussparung
d.rounded_rectangle([38, 52, 90, 66], radius=6, fill=DRED)
# Fuesse
d.rectangle([30, 100, 46, 110], fill=DARK)
d.rectangle([82, 100, 98, 110], fill=DARK)
# X-Praegung
d.line([(44, 76), (84, 96)], fill=DRED, width=7)
d.line([(84, 76), (44, 96)], fill=DRED, width=7)
# Kanten abdunkeln
d.line([(24, 48), (24, 108)], fill=DRED, width=3)
d.line([(104, 48), (104, 108)], fill=DRED, width=3)
img.save(f"{ROOT}/assets/icons/Cogito_FuelCan.png")

# ---------------------------------------------------------------- Generator-Brummen (Loop)
SR = 22050
DUR = 4.0
N = int(SR * DUR)
samples = []
rnd = 12345
for i in range(N):
    t = i / SR
    # 50-Hz-Grundbrummen + 100 Hz Oberwelle + 150 Hz
    v  = 0.46 * math.sin(2 * math.pi * 50 * t)
    v += 0.22 * math.sin(2 * math.pi * 100 * t + 0.7)
    v += 0.10 * math.sin(2 * math.pi * 150 * t + 1.9)
    # Zylindertakt: 8 Hz Pulsation (Viertakt-Motor)
    v *= 0.82 + 0.18 * math.sin(2 * math.pi * 8 * t)
    # mechanisches Rattern: periodisches Rauschen
    rnd = (rnd * 1103515245 + 12345) & 0x7FFFFFFF
    noise = (rnd / 0x3FFFFFFF) - 1.0
    gate = 1.0 if (t * 8.0) % 1.0 < 0.12 else 0.22
    v += 0.055 * noise * gate
    samples.append(v)

# Loop-freundlich: Ende in den Anfang ueberblenden (50 ms Crossfade)
XF = int(SR * 0.05)
for i in range(XF):
    a = i / XF
    samples[i] = samples[i] * a + samples[N - XF + i] * (1 - a)
samples = samples[:N - XF]

peak = max(abs(s) for s in samples)
scale = 0.72 / peak
data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)

with wave.open(f"{ROOT}/assets/audio/generator_hum.wav", "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data)
print("OK: icon + hum written")
