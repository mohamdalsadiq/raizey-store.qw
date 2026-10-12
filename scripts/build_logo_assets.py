#!/usr/bin/env python3
"""
MEEM STORE — derive the shipped logo set from the master artwork.

The master file is `assets/img/meem-logo.png` (1254x1254 PNG, uploaded by the
store owner). It is the single source of truth and is NEVER modified: every
other file below is a byte-for-byte derivative (crop / resize / re-encode) of
that PNG. Nothing is redrawn, recoloured or traced by hand.

    assets/img/meem-logo.png     master artwork (input, unchanged)
    assets/img/meem-logo.webp    same artwork, WebP re-encode
    assets/img/meem-mark.png     square crop: crown + M + gamepad (header mark)
    assets/img/meem-mark.webp    same crop, WebP
    assets/img/favicon-32.png    icons, cropped from the same square mark
    assets/img/favicon-180.png   apple-touch-icon
    assets/img/favicon-192.png   Android / PWA
    assets/img/favicon-512.png   PWA / store listing
    assets/img/favicon.ico       16 + 32 + 48 in one file
    assets/img/meem-og.png       1200x630 social card

Usage:  python3 scripts/build_logo_assets.py [--check]
        --check  verify the outputs exist and match the master's hash, change nothing

Requires Pillow (present in the build image; `pip install pillow` elsewhere).
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
IMG = ROOT / "assets" / "img"
MASTER = IMG / "meem-logo.png"

# Square crop of the emblem, measured on the master with a strong-ink analysis:
# rows 173..739 hold the crown, the M and the gamepad; x 332..928 is centred on
# the M and stops short of the "MEEM" wordmark (which starts at row ~745).
MARK_BOX = (332, 154, 928, 750)
MASTER_SIZE = (1254, 1254)
MASTER_SHA256 = "1a5eb840943f64a2ed23c651c95453b130481d1df50a43a12a89b054d5219b6f"

OG_SIZE = (1200, 630)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def load_master() -> Image.Image:
    if not MASTER.exists():
        sys.exit(f"missing master artwork: {MASTER.relative_to(ROOT)}")
    im = Image.open(MASTER)
    if im.format != "PNG":
        sys.exit(f"master must stay a PNG (found {im.format})")
    if im.size != MASTER_SIZE:
        print(f"! master is {im.size}, expected {MASTER_SIZE} — crop box may need re-measuring")
    return im.convert("RGB")


def build_og(master: Image.Image) -> Image.Image:
    """1200x630 card: the artwork's own edge colours extended sideways (row by row),
    so the seam is invisible and no pixel of the logo is redrawn."""
    import numpy as np

    side = OG_SIZE[1]
    logo = master.resize((side, side), Image.LANCZOS)
    arr = np.asarray(logo).astype(np.float32)
    panel_w = (OG_SIZE[0] - side) // 2
    fade = np.linspace(0.58, 1.0, panel_w, dtype=np.float32)[None, :, None]
    left_edge = arr[:, 0:1, :]          # each row's own boundary colour → seamless at the join
    right_edge = arr[:, -1:, :]
    left = (left_edge * fade).astype(np.uint8)
    right = (right_edge * fade[:, ::-1, :]).astype(np.uint8)
    card = np.concatenate([left, np.asarray(logo), right], axis=1)
    return Image.fromarray(card.astype(np.uint8), "RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description="Derive the MEEM logo asset set from the master artwork.")
    ap.add_argument("--check", action="store_true", help="verify only; write nothing")
    args = ap.parse_args()

    if args.check:
        digest = sha256(MASTER)
        print(f"master  {MASTER.name}  {MASTER.stat().st_size} bytes  sha256={digest[:16]}…")
        print("sha256 matches the pinned value" if digest == MASTER_SHA256
              else "! master hash differs from the pinned value — re-measure the crop box")
        for name in ("meem-logo.webp", "meem-mark.png", "meem-mark.webp", "favicon-32.png",
                     "favicon-180.png", "favicon-192.png", "favicon-512.png", "favicon.ico",
                     "meem-og.png"):
            p = IMG / name
            print(f"{'ok ' if p.exists() else 'MISSING'} {name}"
                  + (f"  {p.stat().st_size} bytes" if p.exists() else ""))
        return 0

    master = load_master()
    print(f"master  {MASTER.relative_to(ROOT)}  {master.size}  sha256={sha256(MASTER)[:16]}…")

    mark = master.crop(MARK_BOX)
    mark.save(IMG / "meem-mark.png", "PNG", optimize=True)
    mark.save(IMG / "meem-mark.webp", "WEBP", quality=92, method=6)
    master.save(IMG / "meem-logo.webp", "WEBP", quality=92, method=6)

    for size, name in ((32, "favicon-32.png"), (180, "favicon-180.png"),
                       (192, "favicon-192.png"), (512, "favicon-512.png")):
        mark.resize((size, size), Image.LANCZOS).save(IMG / name, "PNG", optimize=True)
    frames = [mark.resize((s, s), Image.LANCZOS) for s in (48, 32, 16)]
    frames[0].save(IMG / "favicon.ico", format="ICO",
                   sizes=[(f.width, f.height) for f in frames], append_images=frames[1:])

    build_og(master).save(IMG / "meem-og.png", "PNG", optimize=True)

    for name in ("meem-logo.webp", "meem-mark.png", "meem-mark.webp", "favicon-32.png",
                 "favicon-180.png", "favicon-192.png", "favicon-512.png", "favicon.ico",
                 "meem-og.png"):
        p = IMG / name
        with Image.open(p) as chk:
            print(f"  out   {name:22s} {str(chk.size):12s} {p.stat().st_size:>8} bytes")
    print("done — no pixel of meem-logo.png was altered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
