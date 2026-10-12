#!/usr/bin/env python3
"""MEEM STORE asset pipeline.

Derives every web asset from the master artwork in assets/source/.
NO redrawing, NO recolouring, NO filters: only trim / scale / pad / convert.
Masters are the client-supplied PNGs, kept byte-identical.
"""
import os, sys, shutil
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "source")
OUT = os.path.join(ROOT, "assets", "img")

ROYAL = (9, 42, 145)          # #092A91
WEBP_Q = 88

def load(name):
    p = os.path.join(SRC, name)
    if not os.path.exists(p):
        sys.exit("MISSING MASTER: " + p)
    return Image.open(p).convert("RGBA")

def trim(im, pad_ratio=0.0):
    bbox = im.getchannel("A").getbbox()
    if bbox is None:
        return im
    im = im.crop(bbox)
    if pad_ratio:
        w, h = im.size
        p = int(round(max(w, h) * pad_ratio))
        canvas = Image.new("RGBA", (w + 2 * p, h + 2 * p), (0, 0, 0, 0))
        canvas.alpha_composite(im, (p, p))
        im = canvas
    return im

def by_height(im, h):
    w = max(1, int(round(im.size[0] * h / im.size[1])))
    return im.resize((w, h), Image.LANCZOS)

def save(im, stem, h=None):
    if h:
        im = by_height(im, h)
    png = os.path.join(OUT, stem + ".png")
    im.save(png, "PNG", optimize=True)
    im.save(os.path.join(OUT, stem + ".webp"), "WEBP", quality=WEBP_Q, method=6)
    return png

def icon_mark(mark, side_crop=0.12):
    """Trim the ambient ring off the sides so the emblem stays legible at 16-32px.
    Pure crop of the master pixels — nothing is redrawn or recoloured."""
    w = mark.size[0]
    return mark.crop((int(w * side_crop), 0, int(w * (1 - side_crop)), mark.size[1]))

def gradient_backdrop(size, top=(4, 18, 63), bottom=(12, 51, 172)):
    """Flat royal gradient (brand colours) behind the og artwork."""
    w, h = size
    band = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        band.putpixel((0, y), tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(3)))
    return band.resize(size, Image.BILINEAR).convert("RGBA")

def feather(im, px=26):
    from PIL import ImageDraw, ImageFilter
    w, h = im.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rectangle([px, px, w - px - 1, h - px - 1], fill=255)
    return Image.composite(im, Image.new("RGBA", (w, h), (0, 0, 0, 0)), m.filter(ImageFilter.GaussianBlur(px * 0.55)))

def rounded_mask(size, radius_ratio=0.22):
    from PIL import ImageDraw
    s = size * 4
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius_ratio), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def icon(mark, size, pad_ratio=0.10, radius_ratio=0.22):
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = int(round(size * (1 - 2 * pad_ratio)))
    m = mark.copy()
    m.thumbnail((inner, inner), Image.LANCZOS)
    tile = Image.new("RGBA", (size, size), ROYAL + (255,))
    tile.putalpha(rounded_mask(size, radius_ratio))
    base.alpha_composite(tile)
    base.alpha_composite(m, ((size - m.size[0]) // 2, (size - m.size[1]) // 2))
    return base

def main():
    os.makedirs(OUT, exist_ok=True)

    mark = trim(load("mark.png"))
    name = trim(load("meem-only.png"))
    word = trim(load("wordmark.png"))
    lock = trim(load("lockup-stacked.png"))
    full = load("logo-square.png")

    # M emblem (crown + ring + gamepad), transparent
    for h in (48, 96, 192):
        save(mark, "meem-mark-%d" % h, h)
    shutil.copyfile(os.path.join(OUT, "meem-mark-192.png"), os.path.join(OUT, "meem-mark.png"))

    # MEEM wordmark only (short textual mark)
    for h in (40, 80):
        save(name, "meem-name-%d" % h, h)
    shutil.copyfile(os.path.join(OUT, "meem-name-80.png"), os.path.join(OUT, "meem-name.png"))

    # MEEM STORE horizontal wordmark
    for h in (28, 56):
        save(word, "meem-wordmark-%d" % h, h)
    shutil.copyfile(os.path.join(OUT, "meem-wordmark-56.png"), os.path.join(OUT, "meem-wordmark.png"))

    # MEEM STORE stacked lockup
    for h in (200, 400):
        save(lock, "meem-lockup-%d" % h, h)
    shutil.copyfile(os.path.join(OUT, "meem-lockup-400.png"), os.path.join(OUT, "meem-lockup.png"))

    # Full artwork with its own royal-blue background
    save(full, "meem-logo-480", 480)
    save(full, "meem-logo-960", 960)
    shutil.copyfile(os.path.join(OUT, "meem-logo-960.png"), os.path.join(OUT, "meem-logo.png"))
    os.remove(os.path.join(OUT, "meem-logo-960.webp"))
    Image.open(os.path.join(OUT, "meem-logo-960.png")).save(
        os.path.join(OUT, "meem-logo.webp"), "WEBP", quality=WEBP_Q, method=6)

    # Favicons / app icons: M emblem on a royal-blue rounded square
    small = icon_mark(mark)
    for s in (16, 32, 180, 192, 512):
        icon(small, s, pad_ratio=0.06 if s <= 32 else 0.08).save(
            os.path.join(OUT, "favicon-%d.png" % s), "PNG", optimize=True)
    icon(small, 64, pad_ratio=0.06).save(
        os.path.join(OUT, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])

    # Social card 1200x630: blurred copy of the artwork as ambient backdrop,
    # the untouched artwork composited on top with feathered edges.
    og = gradient_backdrop((1200, 630))
    art = feather(by_height(full, 580), 34)
    og.alpha_composite(art, ((1200 - art.size[0]) // 2, (630 - art.size[1]) // 2))
    og.convert("RGB").save(os.path.join(OUT, "meem-og.png"), "PNG", optimize=True)
    og.convert("RGB").save(os.path.join(OUT, "meem-og.webp"), "WEBP", quality=90, method=6)

    print("generated:")
    for f in sorted(os.listdir(OUT)):
        print("  %-28s %8.1f KB" % (f, os.path.getsize(os.path.join(OUT, f)) / 1024))

if __name__ == "__main__":
    main()
