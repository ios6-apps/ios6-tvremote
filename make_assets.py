"""Generates the app icon and launch images (flat PNGs; iOS 6 adds the icon gloss and rounding itself)."""
import math, random
from PIL import Image, ImageDraw, ImageFilter

def wood(w, h, seed=7):
    random.seed(seed)
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=(int(104 - 16 * t), int(60 - 10 * t), int(32 - 6 * t)))
    for _ in range(int(w * 1.3)):
        x0 = random.random() * w; amp = 1 + random.random() * 5; f = 0.004 + random.random() * 0.012; ph = random.random() * 6.28
        dark = random.random() < 0.62
        col = (30, 14, 6) if dark else (176, 112, 62)
        a = (0.06 + random.random() * 0.2) if dark else (0.04 + random.random() * 0.12)
        pts = [(x0 + amp * math.sin(y * f + ph), y) for y in range(0, h, 6)]
        ov = Image.new("RGBA", (w, h), (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
        od.line(pts, fill=col + (int(a * 255),), width=1 + (random.random() < 0.3))
        im.paste(ov, (0, 0), ov)
    return im

def plate(im, box, radius):
    w, h = im.size
    x0, y0, x1, y1 = box
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle([x0, y0 + 4, x1, y1 + 4], radius, fill=(0, 0, 0, 200))
    im.paste(sh.filter(ImageFilter.GaussianBlur(5)), (0, 0), sh.filter(ImageFilter.GaussianBlur(5)))
    layer = Image.new("RGB", im.size, (0, 0, 0)); ld = ImageDraw.Draw(layer)
    for y in range(int(y0), int(y1)):
        t = (y - y0) / max(1, y1 - y0); v = int(52 - 38 * t)
        ld.line([(x0, y), (x1, y)], fill=(v, v, v + 2))
    mask = Image.new("L", im.size, 0); ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    im.paste(layer, (0, 0), mask)
    ImageDraw.Draw(im).rounded_rectangle(box, radius, outline=(90, 90, 94), width=1)

def icon(n):
    im = wood(n, n)
    s = n / 100.0
    plate(im, (30 * s, 8 * s, 70 * s, 94 * s), 10 * s)
    d = ImageDraw.Draw(im)
    d.ellipse([39 * s, 14 * s, 61 * s, 36 * s], fill=(214, 40, 28), outline=(90, 10, 6))
    d.ellipse([36 * s, 44 * s, 64 * s, 72 * s], fill=(170, 172, 178), outline=(30, 30, 30))
    d.ellipse([40 * s, 48 * s, 60 * s, 68 * s], fill=(24, 24, 26))
    d.ellipse([46 * s, 54 * s, 54 * s, 62 * s], fill=(70, 70, 74))
    for x in (40, 50, 60):
        d.ellipse([(x - 3) * s, 80 * s, (x + 3) * s, 86 * s], fill=(80, 80, 86))
    return im

def launch(w, h, scale):
    im = wood(w, h)
    plate(im, (8 * scale, 8 * scale, w - 8 * scale, h - 60 * scale), 26 * scale)
    return im

icon(57).save("res/Icon.png")
icon(114).save("res/Icon@2x.png")
launch(320, 480, 1).save("res/Default.png")
launch(640, 960, 2).save("res/Default@2x.png")
launch(640, 1136, 2).save("res/Default-568h@2x.png")

# Rounded 512 px copy for the README and GitHub (on the device iOS adds its own rounding and gloss to Icon.png)
import os
from PIL import ImageDraw as _ImageDraw
os.makedirs("docs", exist_ok=True)
_i = icon(512).convert("RGBA")
_m = Image.new("L", _i.size, 0)
_ImageDraw.Draw(_m).rounded_rectangle([0, 0, 511, 511], radius=115, fill=255)
_i.putalpha(_m)
_i.save("docs/icon.png")
