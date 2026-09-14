#!/usr/bin/env python3
"""Gera os ícones do Android a partir de app/assets/icon/icon.png.

- mipmap-*/ic_launcher.png: ícone clássico (o círculo inteiro).
- drawable-*/ic_launcher_background.png + ic_launcher_foreground.png: ícone
  adaptativo (Android 8+): o gradiente do círculo no fundo e as barras brancas
  na frente, para a máscara do launcher (círculo, gota, quadrado) recortar.
- drawable-*/ic_stat_bk.png: ícone da notificação (branco sobre transparente).

Uso: python3 dev/tools/android_icons.py
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "app/assets/icon/icon.png"
RES = ROOT / "app/android/app/src/main/res"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

img = np.asarray(Image.open(SRC).convert("RGBA")).astype(np.float64)
h, w = img.shape[:2]
cx, cy, radius = (w - 1) / 2, (h - 1) / 2, w / 2
yy, xx = np.mgrid[0:h, 0:w]
dist = np.hypot(xx - cx, yy - cy)
rgb, alpha = img[..., :3], img[..., 3]

# Barras: brancas; o fundo é azul/roxo (canal mínimo bem abaixo de 255).
low = rgb.min(axis=2)
bars = np.clip((low - 120) / (250 - 120), 0, 1) * (alpha / 255)

# Perfil radial do gradiente (média das cores sem barra a cada raio).
bg_mask = (bars < 0.02) & (alpha > 250)
rings = np.arange(0, int(radius) + 1)
profile = np.zeros((len(rings), 3))
last = None
for r in rings:
    sel = bg_mask & (np.abs(dist - r) < 1.5)
    if sel.sum() > 3:
        last = rgb[sel].mean(axis=0)
    elif last is None:
        continue
    profile[r] = last
first = next(i for i in rings if profile[i].any())
profile[:first] = profile[first]
edge = profile[int(radius) - 3]
profile[int(radius) - 2:] = edge

# Canvas do adaptativo: 108 dp, com o círculo visível (72 dp) = 512 px da origem.
canvas = int(round(w * 108 / 72))
off = (canvas - w) / 2
cyy, cxx = np.mgrid[0:canvas, 0:canvas]
cd = np.hypot(cxx - (canvas - 1) / 2, cyy - (canvas - 1) / 2)
idx = np.clip(cd, 0, len(profile) - 1)
lo = np.floor(idx).astype(int)
hi = np.minimum(lo + 1, len(profile) - 1)
t = (idx - lo)[..., None]
background = profile[lo] * (1 - t) + profile[hi] * t
bg_img = Image.fromarray(np.dstack([background, np.full(cd.shape, 255.0)]).astype(np.uint8), "RGBA")

fg = np.zeros((canvas, canvas, 4))
o = int(round(off))
fg[o:o + h, o:o + w, :3] = 255
fg[o:o + h, o:o + w, 3] = bars * 255
fg_img = Image.fromarray(fg.astype(np.uint8), "RGBA")

# Notificação: barras recortadas, cabendo em 20 de 24 dp.
ys, xs = np.nonzero(bars > 0.02)
crop = bars[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
ch, cw = crop.shape
side = max(ch, cw)
pad = side * 24 / 20
stat = np.zeros((int(pad), int(pad), 4))
sy, sx = int((pad - ch) / 2), int((pad - cw) / 2)
stat[sy:sy + ch, sx:sx + cw, :3] = 255
stat[sy:sy + ch, sx:sx + cw, 3] = crop * 255
stat_img = Image.fromarray(stat.astype(np.uint8), "RGBA")

src_img = Image.open(SRC).convert("RGBA")
for name, scale in DENSITIES.items():
    mip = RES / f"mipmap-{name}"
    draw = RES / f"drawable-{name}"
    mip.mkdir(parents=True, exist_ok=True)
    draw.mkdir(parents=True, exist_ok=True)
    src_img.resize((round(48 * scale),) * 2, Image.LANCZOS).save(mip / "ic_launcher.png", optimize=True)
    size = round(108 * scale)
    bg_img.resize((size, size), Image.LANCZOS).save(draw / "ic_launcher_background.png", optimize=True)
    fg_img.resize((size, size), Image.LANCZOS).save(draw / "ic_launcher_foreground.png", optimize=True)
    stat_img.resize((round(24 * scale),) * 2, Image.LANCZOS).save(draw / "ic_stat_bk.png", optimize=True)

anydpi = RES / "mipmap-anydpi-v26"
anydpi.mkdir(exist_ok=True)
(anydpi / "ic_launcher.xml").write_text(
    """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
)
print("ícones gerados em", RES, "- borda do gradiente:", edge.round())
