#!/usr/bin/env python3
"""MEEM STORE — banner asset pipeline.

Pure convert/crop/pad of the store owner's own artwork. Nothing is drawn,
recoloured or retouched. Sources are the PNG masters in assets/img/.

Slots and target boxes (both source ratios match the boxes exactly, so the
subject is never cropped):
  desktop  1920 x 720  (8:3)   source 2048 x 768  (8:3)
  mobile   1086 x 1448 (3:4)   source 1086 x 1448 (3:4)   [portrait art]
  retina   desktop @2x = the native 2048 x 768 master

Output: WebP next to each master, quality tuned down until < 300 KB.
Run: python3 scripts/build_banner_assets.py
"""
from __future__ import annotations
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(ROOT, "assets", "img")
LIMIT_BYTES = 300 * 1024

DESKTOP_BOX = (1920, 720)
MOBILE_BOX = (1086, 1448)


def to_webp(src: str, dst: str, box: tuple[int, int]) -> None:
    im = Image.open(src)
    im.load()
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGB")
    # exact-ratio sources: plain resize, no crop
    ratio_src = im.width / im.height
    ratio_box = box[0] / box[1]
    if abs(ratio_src - ratio_box) > 0.005:
        # only differs if the artist ever replaces a source: centre-crop to the
        # target ratio, never stretch, never letterbox.
        if ratio_src > ratio_box:
            new_w = int(round(im.height * ratio_box))
            left = (im.width - new_w) // 2
            im = im.crop((left, 0, left + new_w, im.height))
        else:
            new_h = int(round(im.width / ratio_box))
            top = (im.height - new_h) // 2
            im = im.crop((0, top, im.width, top + new_h))
        print(f"  crop applied to reach {ratio_box:.3f}")
    im = im.resize(box, Image.LANCZOS)

    for q in (82, 78, 74, 70, 66, 62, 58):
        im.save(dst, "WEBP", quality=q, method=6)
        size = os.path.getsize(dst)
        if size < LIMIT_BYTES:
            print(f"  {os.path.basename(dst):28s} {box[0]}x{box[1]} q={q} {size/1024:6.1f} KB")
            return
    print(f"  !! {os.path.basename(dst)} still {os.path.getsize(dst)/1024:.1f} KB at q=58")


def main() -> None:
    plan = [
        ("banner-1-desktop.png", "banner-1-desktop.webp", DESKTOP_BOX),
        ("banner-1-desktop.png", "banner-1-desktop@2x.webp", (2048, 768)),
        ("banner-1-mobile.png", "banner-1-mobile.webp", MOBILE_BOX),
        ("banner-2-desktop.png", "banner-2-desktop.webp", DESKTOP_BOX),
        ("banner-2-desktop.png", "banner-2-desktop@2x.webp", (2048, 768)),
        ("banner-2-mobile.png", "banner-2-mobile.webp", MOBILE_BOX),
        ("banner-3-desktop.png", "banner-3-desktop.webp", DESKTOP_BOX),
        ("banner-3-desktop.png", "banner-3-desktop@2x.webp", (2048, 768)),
        ("banner-3-mobile.png", "banner-3-mobile.webp", MOBILE_BOX),
    ]
    for src, dst, box in plan:
        s = os.path.join(IMG, src)
        if not os.path.exists(s):
            raise SystemExit(f"missing source: {s}")
        print(f"{src} -> {dst}")
        to_webp(s, os.path.join(IMG, dst), box)


if __name__ == "__main__":
    main()
