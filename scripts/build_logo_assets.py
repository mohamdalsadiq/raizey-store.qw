#!/usr/bin/env python3
"""MEEM STORE — logo asset builder (Phase 1a).

Source of truth:  assets/img/meem-logo.png   (the official logo, saved byte-for-byte)
Outputs (all derived, never redrawn):
  assets/img/meem-logo.webp        compressed large version (hero / footer / receipt)
  assets/img/meem-mark.png         square crop of the emblem (M + crown + gamepad) -> header/auth
  assets/img/meem-mark.webp        same, compressed
  assets/img/meem-mark-32.png      favicon 32
  assets/img/meem-mark-180.png     apple-touch-icon
  assets/img/meem-mark-192.png     android
  assets/img/meem-mark-512.png     PWA / og fallback
  assets/img/favicon.ico           multi-size ico
  assets/img/meem-og.png           1200x630 social card (logo centered on brand blue)

Usage:
  python3 scripts/build_logo_assets.py
  python3 scripts/build_logo_assets.py --mark-box 0.18,0.02,0.82,0.64   # x0,y0,x1,y1 as fractions

Requires: Pillow (already available in this workspace).
"""
import argparse, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(ROOT, "assets", "img")
SRC = os.path.join(IMG, "meem-logo.png")

# Brand colours (see assets/css/meem.css) — used only for the og background.
ROYAL = (9, 42, 145)
NAVY = (6, 26, 92)

def load():
    if not os.path.exists(SRC):
        sys.exit(f"missing source logo: {SRC}\nSave the official logo there first (do not redraw it).")
    return Image.open(SRC).convert("RGBA")

def crop_fraction(im, box):
    w, h = im.size
    x0, y0, x1, y1 = box
    return im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))

def square(im):
    w, h = im.size
    side = min(w, h)
    return im.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2))

def save_webp(im, path, quality=88):
    im.save(path, "WEBP", quality=quality, method=6)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mark-box", default="0.18,0.02,0.82,0.64",
                    help="emblem crop as x0,y0,x1,y1 fractions of the source image")
    ap.add_argument("--quality", type=int, default=88)
    args = ap.parse_args()

    src = load()
    print("source:", src.size)

    # 1. full logo — webp
    large = src.copy()
    if large.width > 1400:
        ratio = 1400 / large.width
        large = large.resize((1400, int(large.height * ratio)), Image.LANCZOS)
    save_webp(large, os.path.join(IMG, "meem-logo.webp"), args.quality)
    print("wrote meem-logo.webp", large.size)

    # 2. emblem square crop
    box = tuple(float(v) for v in args.mark_box.split(","))
    mark = square(crop_fraction(src, box))
    mark_png = mark.resize((512, 512), Image.LANCZOS)
    mark_png.save(os.path.join(IMG, "meem-mark.png"))
    save_webp(mark_png, os.path.join(IMG, "meem-mark.webp"), args.quality)
    print("wrote meem-mark.png/.webp", mark_png.size)

    # 3. favicons
    for size in (32, 180, 192, 512):
        mark.resize((size, size), Image.LANCZOS).save(os.path.join(IMG, f"meem-mark-{size}.png"))
    ico = mark.resize((256, 256), Image.LANCZOS)
    ico.save(os.path.join(IMG, "favicon.ico"),
             sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote favicons (32/180/192/512 + favicon.ico)")

    # 4. og image 1200x630 on brand blue
    og = Image.new("RGBA", (1200, 630), NAVY)
    # subtle royal band so the navy background matches the logo plate
    band = Image.new("RGBA", (1200, 630), ROYAL)
    og.alpha_composite(band.crop((0, 0, 1200, 100)))
    logo = src.copy()
    logo.thumbnail((520, 520), Image.LANCZOS)
    og.alpha_composite(logo, ((1200 - logo.width) // 2, (630 - logo.height) // 2))
    og.convert("RGB").save(os.path.join(IMG, "meem-og.png"), optimize=True)
    print("wrote meem-og.png 1200x630")

if __name__ == "__main__":
    main()
