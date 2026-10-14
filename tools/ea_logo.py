"""Draws the Everything Auras logo (design option F, chosen 2026-10-13) at 1600 px. Writes the 64 px in-game icon
to EverythingAuras/Media/EA/logo.tga and, with --png, the 400 px CurseForge image next to this script."""
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT = os.path.join(ROOT, "EverythingAuras", "Media", "Fonts", "FiraSansCondensed-Heavy.ttf")
S = 1600
C = S / 2


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def ramp(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return lerp(c0, c1, (t - t0) / (t1 - t0) if t1 > t0 else 0)
    return stops[-1][1]


def circle_mask(r, cx=C, cy=C):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return m


def vertical(stops):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line((0, y, S, y), fill=ramp(stops, y / (S - 1)))
    return img


def radial(stops, cx=C, cy=C, r=C):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    steps = 400
    for i in range(steps, 0, -1):
        t = i / steps
        rr = r * t
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=ramp(stops, t))
    return img


def paste(base, layer, mask):
    base.paste(layer, (0, 0), mask)


def glow_ring(radius, width, color, alpha, blur):
    layer = Image.new("RGBA", (S, S), color + (0,))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse((C - radius, C - radius, C + radius, C + radius), outline=alpha, width=width)
    m = m.filter(ImageFilter.GaussianBlur(blur))
    layer.putalpha(m)
    return layer


def sparkle(img, x, y, r, alpha=230):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = []
    for i in range(8):
        a = i * math.pi / 4
        rr = r if i % 2 == 0 else r * 0.22
        pts.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    d.polygon(pts, fill=(255, 255, 255, alpha))
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(2)))


SILVER = [(0, hexrgb("f4f7fb")), (0.35, hexrgb("b9c1cc")), (0.55, hexrgb("7d8692")), (0.8, hexrgb("cfd6df")), (1, hexrgb("5c6470"))]
GOLD = [(0, hexrgb("fff3c4")), (0.35, hexrgb("e7bf55")), (0.55, hexrgb("a8781c")), (0.8, hexrgb("f0cf73")), (1, hexrgb("6e4b0c"))]
VIOLET = [(0, hexrgb("b791ff")), (0.45, hexrgb("8152d6")), (1, hexrgb("1f0c42"))]
NIGHT = [(0, hexrgb("3b2f5c")), (0.5, hexrgb("1d1830")), (1, hexrgb("0b0a12"))]

AURA_SOFT = [(470, 26, 150, 18), (560, 14, 90, 12)]




def logotype(text, size, shear=0.24, cut=False):
    font = ImageFont.truetype(FONT, size)
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    box = d.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text((C - w / 2 - box[0], C - h / 2 - box[1]), text, font=font, fill=255)
    # slant: the top leans right
    m = m.transform((S, S), Image.AFFINE, (1, shear, -shear * C, 0, 1, 0), resample=Image.BICUBIC)
    if cut:
        band = Image.new("L", (S, S), 0)
        bd = ImageDraw.Draw(band)
        bd.line((C - 520, C + 230, C + 520, C - 150), fill=255, width=26)
        m = ImageChops.subtract(m, band)
    # outline from a blurred and thresholded copy, so its corners stay round
    outline = m.filter(ImageFilter.GaussianBlur(16)).point(lambda v: 255 if v > 18 else 0)
    outline = outline.filter(ImageFilter.GaussianBlur(1.5))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (6, 2, 16, 0))
    shadow.putalpha(outline.filter(ImageFilter.GaussianBlur(22)).point(lambda v: int(v * 0.85)))
    layer = Image.alpha_composite(layer, shadow.transform((S, S), Image.AFFINE, (1, 0, -12, 0, 1, -22)))
    rim = Image.new("RGBA", (S, S), (22, 8, 48, 0))
    rim.putalpha(outline)
    layer = Image.alpha_composite(layer, rim)
    fill = vertical([(0, (255, 255, 255)), (0.48, (255, 255, 255)), (0.62, (226, 214, 255)), (1, (190, 168, 245))]).convert("RGBA")
    fill.putalpha(m)
    layer = Image.alpha_composite(layer, fill)
    return layer


def badge2(ring_stops, disc_stops, aura, cut=False):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    R, ring = 760, 92
    paste(img, Image.new("RGB", (S, S), (14, 12, 20)), circle_mask(R + 14))
    paste(img, vertical(ring_stops), circle_mask(R))
    groove = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(groove).ellipse((C - R + 40, C - R + 40, C + R - 40, C + R - 40), outline=(0, 0, 0, 90), width=6)
    img = Image.alpha_composite(img, groove)
    r = R - ring
    paste(img, Image.new("RGB", (S, S), (20, 10, 38)), circle_mask(r + 10))
    paste(img, radial(disc_stops, C, C - 120, r + 160), circle_mask(r))
    for rad, w, a, b in aura:
        img = Image.alpha_composite(img, glow_ring(rad, w, (205, 185, 255), a, b))
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).ellipse((C - r * 0.85, C - r * 1.02, C + r * 0.85, C - r * 0.05), fill=40)
    gloss = ImageChops.multiply(gloss.filter(ImageFilter.GaussianBlur(40)), circle_mask(r))
    g = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    g.putalpha(gloss)
    img = Image.alpha_composite(img, g)
    img = Image.alpha_composite(img, logotype("EA", 760, cut=cut))
    line = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(line).ellipse((C - r - 6, C - r - 6, C + r + 6, C + r + 6), outline=(255, 255, 255, 110), width=5)
    return Image.alpha_composite(img, line)


AURA_SOFT = [(470, 26, 150, 18), (560, 14, 90, 12)]

def write_tga(path, img):
    """Bottom-left origin and 8 alpha bits, as the library's own textures are written."""
    import struct
    w, h = img.size
    px = img.load()
    body = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[x, y]
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8) + bytes(body))


if __name__ == "__main__":
    logo = badge2(GOLD, VIOLET, AURA_SOFT)
    out = os.path.join(ROOT, "EverythingAuras", "Media", "EA", "logo.tga")
    write_tga(out, logo.resize((64, 64), Image.LANCZOS))
    print("wrote", out)
    if "--png" in sys.argv:
        logo.resize((400, 400), Image.LANCZOS).save(os.path.join(HERE, "logo-400.png"))
