#!/usr/bin/env python3
"""
MEEM STORE — brand asset builder (offline, deterministic).

Turns the brand geometry below into the shipped logo set:

    assets/img/meem-mark.svg              emblem only, transparent
    assets/img/meem-logo.svg              stacked lockup (emblem + MEEM + STORE + tagline)
    assets/img/meem-logo-horizontal.svg   navbar lockup (emblem + wordmark, side by side)
    assets/img/meem-mark.png / .webp      transparent emblem raster (512)
    assets/img/meem-logo.png / .webp      transparent stacked lockup raster (900)
    assets/img/favicon.svg                simplified mark (bold, reads at 16px)
    assets/img/favicon.ico                16 / 32 / 48
    assets/img/favicon-32.png             32
    assets/img/meem-icon-180.png          apple-touch-icon
    assets/img/meem-icon-192.png          android / PWA
    assets/img/meem-icon-512.png          PWA / store listing
    assets/img/meem-og.png                1200x630 social card

Palette = the Phase 1 tokens in assets/css/meem.css (royal blue / gold / silver /
electric blue, dark-first). All lettering is converted from font outlines to
vector paths, so the shipped SVGs have zero font dependencies and render
identically everywhere (browser, social scrapers, rasterizers).

Wordmark font: Orbitron (SIL Open Font License 1.1, Florian Karsten) — used at
build time only; outlines are baked into the assets. The TTF is fetched once
into .cache/brand-build/ (gitignored) and can be overridden with --font.

Usage:
    python3 scripts/build_brand_assets.py                     # write SVGs (+ rasters if node deps present)
    python3 scripts/build_brand_assets.py --svg-only          # SVGs only, no rasterizer needed
    python3 scripts/build_brand_assets.py --preview DIR       # also write preview PNGs for review
"""
from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "img"
CACHE = ROOT / ".cache" / "brand-build"

FONT_URLS = [
    "https://raw.githubusercontent.com/google/fonts/main/ofl/orbitron/Orbitron%5Bwght%5D.ttf",
    "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/orbitron/Orbitron%5Bwght%5D.ttf",
]

# ── palette (mirrors assets/css/meem.css) ────────────────────────────────────
C = {
    "royal": "#092A91",
    "royal_hi": "#0A2FA8",
    "bg": "#061A5C",
    "gold": "#FFD400",
    "gold_lo": "#E6A200",
    "gold_hi": "#FFF3B0",
    "silver": "#FFFFFF",
    "steel_hi": "#F4F8FF",
    "steel": "#C3D2EC",
    "steel_mid": "#93A8CE",
    "steel_lo": "#5A6E96",
    "electric": "#087BFF",
    "navy": "#0A1128",
    "navy_hi": "#17264A",
}

# ── emblem geometry (design grid 1000 x 1000) ────────────────────────────────
RING = dict(cx=500, cy=556, rx=470, ry=198, rot=-19, w=28, front_from=236, front_to=304)
M_LETTER = dict(  # the "M": chiselled stems, V descending to the baseline (gap left open)
    left_bottom=150, left_top=170, shoulder_y=468, tip_x=300, tip_y=318,
    inner_bottom=482, bottom=842,
)
CROWN = dict(band_l=396, band_r=604, band_top=330, band_bottom=420,
             spike_apex_y=170, side_apex_y=236, side_apex_dx=-70, hole_y=266, hole_r=28)
PAD = dict(x0=322, x1=678, top=626, bottom=802)

def f(v: float, nd: int = 2) -> str:
    """Compact number formatting for SVG output."""
    s = f"{v:.{nd}f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def bbox_of_points(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


# ════════════════════════════════════════════════════════════════════════════
# Font outlines → SVG paths
# ════════════════════════════════════════════════════════════════════════════
def ensure_font(explicit: Path | None) -> Path:
    if explicit:
        return explicit
    CACHE.mkdir(parents=True, exist_ok=True)
    for p in CACHE.glob("Orbitron*.ttf"):
        return p
    import urllib.request

    last = None
    for url in FONT_URLS:
        try:
            with urllib.request.urlopen(url, timeout=30) as r:  # noqa: S310 (build-time, fixed hosts)
                data = r.read()
            if len(data) > 20_000:
                p = CACHE / "Orbitron[wght].ttf"
                p.write_bytes(data)
                print(f"  font   fetched {url.rsplit('/', 1)[-1]} → {p.relative_to(ROOT)}")
                return p
        except Exception as exc:  # pragma: no cover - network dependent
            last = exc
    raise SystemExit(f"cannot obtain Orbitron TTF ({last}); pass --font /path/to/Orbitron.ttf")


class Outliner:
    """Converts text into SVG path data (font outlines baked in, no runtime font)."""

    def __init__(self, font_path: Path, weight: int = 900):
        from fontTools.ttLib import TTFont
        from fontTools.varLib.instancer import instantiateVariableFont

        self.font = TTFont(str(font_path))
        if "fvar" in self.font:
            axes = {a.axisTag for a in self.font["fvar"].axes}
            inst = {k: v for k, v in (("wght", weight),) if k in axes}
            instantiateVariableFont(self.font, inst, inplace=True)
        self.upem = self.font["head"].unitsPerEm
        self.cmap = self.font.getBestCmap()
        self.glyphs = self.font.getGlyphSet()
        self.hmtx = self.font["hmtx"]

    def _glyph_d(self, name: str, scale: float, dx: float, dy: float) -> str:
        from fontTools.pens.svgPathPen import SVGPathPen
        from fontTools.pens.transformPen import TransformPen
        from fontTools.misc.transform import Transform

        pen = SVGPathPen(self.glyphs, ntos=f)
        tp = TransformPen(pen, Transform(scale, 0, 0, -scale, dx, dy))
        self.glyphs[name].draw(tp)
        return pen.getCommands()

    def _glyph_bounds(self, name: str, scale: float, dx: float, dy: float):
        from fontTools.pens.boundsPen import BoundsPen
        from fontTools.pens.transformPen import TransformPen
        from fontTools.misc.transform import Transform

        bp = BoundsPen(self.glyphs)
        tp = TransformPen(bp, Transform(scale, 0, 0, -scale, dx, dy))
        self.glyphs[name].draw(tp)
        return bp.bounds

    def text(self, text: str, size: float, tracking_em: float = 0.0, scale_x: float = 1.0,
             origin=(0.0, 0.0)):
        """Returns (path_d, ink_bbox). `origin` is the baseline start point."""
        scale = size / self.upem
        advance = tracking_em * size
        x, y = origin
        parts, xs, ys = [], [], []
        for ch in text:
            name = self.cmap.get(ord(ch))
            if name is None:
                x += advance
                continue
            d = self._glyph_d(name, scale, x, y)
            if d:
                parts.append(d)
            b = self._glyph_bounds(name, scale, x, y)
            if b:
                xs += [b[0], b[2]]
                ys += [b[1], b[3]]
            x += self.hmtx[name][0] * scale + advance
        bbox = (min(xs), min(ys), max(xs), max(ys)) if xs else (origin[0], origin[1], origin[0], origin[1])
        return " ".join(parts), bbox


# ════════════════════════════════════════════════════════════════════════════
# Emblem
# ════════════════════════════════════════════════════════════════════════════
def ring_arc_points(deg_a: float, deg_b: float, steps: int = 48):
    """Sample the (rotated) orbit ring between two angles, screen coordinates."""
    pts = []
    rot = math.radians(RING["rot"])
    for i in range(steps + 1):
        t = math.radians(deg_a + (deg_b - deg_a) * i / steps)
        x = RING["rx"] * math.cos(t)
        y = RING["ry"] * math.sin(t)
        pts.append((RING["cx"] + x * math.cos(rot) - y * math.sin(rot),
                    RING["cy"] + x * math.sin(rot) + y * math.cos(rot)))
    return pts


def polyline_path(pts, closed: bool = False) -> str:
    d = "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts)
    return d + ("Z" if closed else "")


def m_path() -> str:
    """The MEEM "M": chiselled stems with a V that descends to an open baseline gap."""
    m = M_LETTER
    pts = [
        (m["left_bottom"], m["bottom"]), (m["left_top"], m["shoulder_y"]),
        (m["tip_x"], m["tip_y"]), (m["inner_bottom"], m["bottom"]),
        (1000 - m["inner_bottom"], m["bottom"]),
        (1000 - m["tip_x"], m["tip_y"]), (1000 - m["left_top"], m["shoulder_y"]),
        (1000 - m["left_bottom"], m["bottom"]),
    ]
    return polyline_path(pts, closed=True)


def crown_path(hole: bool = True) -> str:
    c = CROWN
    mid = 500
    pts = [
        (c["band_l"], c["band_bottom"]), (c["band_l"], c["band_top"]),
        (mid + c["side_apex_dx"], c["side_apex_y"]),
        (mid - 64, c["band_top"] + 4),
        (mid, c["spike_apex_y"]),
        (mid + 64, c["band_top"] + 4),
        (mid - c["side_apex_dx"], c["side_apex_y"]),
        (c["band_r"], c["band_top"]), (c["band_r"], c["band_bottom"]),
    ]
    outer = polyline_path(pts, closed=True)
    if not hole:
        return outer
    # diamond cut-out inside the middle spike (even-odd hole)
    hx, hy, r = mid, c["hole_y"], c["hole_r"]
    cut = (f"M{f(hx)},{f(hy - r)} L{f(hx + r)},{f(hy)} L{f(hx)},{f(hy + r)} "
           f"L{f(hx - r)},{f(hy)} Z")
    return outer + " " + cut


def pad_path() -> str:
    p = PAD
    x0, x1, top = p["x0"], p["x1"], p["top"]
    return (f"M{f(x0)},{f(top + 70)} C{f(x0)},{f(top + 26)} {f(x0 + 42)},{f(top)} {f(x0 + 86)},{f(top)} "
            f"L{f(x1 - 86)},{f(top)} C{f(x1 - 42)},{f(top)} {f(x1)},{f(top + 26)} {f(x1)},{f(top + 70)} "
            f"C{f(x1)},{f(top + 116)} {f(x1 - 14)},{f(top + 152)} {f(x1 - 40)},{f(top + 158)} "
            f"C{f(x1 - 66)},{f(top + 164)} {f(x1 - 86)},{f(top + 138)} {f(x1 - 112)},{f(top + 124)} "
            f"C{f(x1 - 138)},{f(top + 110)} {f(x0 + 138)},{f(top + 110)} {f(x0 + 112)},{f(top + 124)} "
            f"C{f(x0 + 86)},{f(top + 138)} {f(x0 + 66)},{f(top + 164)} {f(x0 + 40)},{f(top + 158)} "
            f"C{f(x0 + 14)},{f(top + 152)} {f(x0)},{f(top + 116)} {f(x0)},{f(top + 70)} Z")


def emblem_defs(uid: str = "mm") -> str:
    r = RING
    return f"""  <defs>
    <linearGradient id="{uid}-steel" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="{C['steel_hi']}"/><stop offset="0.42" stop-color="{C['steel']}"/>
      <stop offset="0.72" stop-color="{C['steel_mid']}"/><stop offset="1" stop-color="{C['steel_lo']}"/>
    </linearGradient>
    <linearGradient id="{uid}-steel2" x1="0.9" y1="0" x2="0.1" y2="1">
      <stop offset="0" stop-color="{C['steel_hi']}"/><stop offset="0.5" stop-color="{C['steel_mid']}"/>
      <stop offset="1" stop-color="{C['steel_lo']}"/>
    </linearGradient>
    <linearGradient id="{uid}-gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{C['gold_hi']}"/><stop offset="0.5" stop-color="{C['gold']}"/>
      <stop offset="1" stop-color="{C['gold_lo']}"/>
    </linearGradient>
    <linearGradient id="{uid}-ring" x1="0" y1="0.2" x2="1" y2="0.8">
      <stop offset="0" stop-color="{C['steel_hi']}"/><stop offset="0.35" stop-color="{C['electric']}"/>
      <stop offset="0.68" stop-color="{C['gold']}"/><stop offset="1" stop-color="{C['gold_lo']}"/>
    </linearGradient>
    <linearGradient id="{uid}-word" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{C['silver']}"/><stop offset="0.55" stop-color="#E7EEFC"/>
      <stop offset="1" stop-color="#A9BCDD"/>
    </linearGradient>
    <linearGradient id="{uid}-pad" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="{C['navy_hi']}"/><stop offset="1" stop-color="{C['navy']}"/>
    </linearGradient>
    <radialGradient id="{uid}-blueglow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{C['electric']}" stop-opacity="0.55"/>
      <stop offset="1" stop-color="{C['electric']}" stop-opacity="0"/>
    </radialGradient>
    <filter id="{uid}-glow" x="-45%" y="-45%" width="190%" height="190%">
      <feGaussianBlur stdDeviation="13"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="{uid}-glow-soft" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="6"/><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>"""


def emblem_body(uid: str = "mm", with_ring_front: bool = True, simple: bool = False) -> str:
    """The MEEM emblem: orbit ring, crown, the "M", controller."""
    r, m = RING, M_LETTER
    rot = f"rotate({r['rot']} {r['cx']} {r['cy']})"
    ring_ellipse = (f'    <ellipse cx="{r["cx"]}" cy="{r["cy"]}" rx="{r["rx"]}" ry="{r["ry"]}" '
                    f'transform="{rot}" fill="none" stroke="url(#{uid}-ring)" stroke-width="{r["w"]}"/>')
    ring_glow = (f'    <ellipse cx="{r["cx"]}" cy="{r["cy"]}" rx="{r["rx"]}" ry="{r["ry"]}" '
                 f'transform="{rot}" fill="none" stroke="{C["electric"]}" stroke-width="54" '
                 f'opacity="0.26" filter="url(#{uid}-glow)"/>')
    front_arc = polyline_path(ring_arc_points(RING["front_from"], RING["front_to"]), closed=False)
    crease_r = (f'M{f(1000 - m["tip_x"] + 26)},{f(m["tip_y"] + 30)} '
                f'L{f(1000 - m["inner_bottom"] + 30)},{f(m["bottom"] - 26)}')
    rim_l = (f'M{f(m["left_bottom"] + 28)},{f(m["bottom"] - 20)} L{f(m["left_top"] + 26)},{f(m["shoulder_y"] + 30)} '
             f'L{f(m["tip_x"] - 20)},{f(m["tip_y"] + 30)}')
    parts = [f'  <g id="{uid}-emblem">']
    if not simple:
        parts.append(ring_glow)
        parts.append(ring_ellipse)
    parts.append(f'    <path d="{crown_path()}" fill="url(#{uid}-gold)" fill-rule="evenodd" '
                 f'filter="url(#{uid}-glow-soft)"/>')
    parts.append(f'    <g filter="url(#{uid}-glow-soft)">')
    parts.append(f'      <path d="{m_path()}" fill="url(#{uid}-steel)"/>')
    parts.append(f'      <path d="{crease_r}" stroke="#FFFFFF" stroke-opacity="0.28" stroke-width="9" fill="none"/>')
    parts.append(f'      <path d="{rim_l}" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="8" fill="none" stroke-linecap="round"/>')
    parts.append("    </g>")
    if with_ring_front and not simple:
        parts.append(f'    <path d="{front_arc}" fill="none" stroke="url(#{uid}-ring)" '
                     f'stroke-width="{r["w"]}" stroke-linecap="round"/>')
    if not simple:
        parts += pad_group(uid)
    parts.append("  </g>")
    return "\n".join(parts)


def pad_group(uid: str) -> list[str]:
    p = PAD
    cx_dpad, cy_dpad = p["x0"] + 96, p["top"] + 68
    cx_btn, cy_btn = p["x1"] - 92, p["top"] + 62
    out = [
        f'    <g id="{uid}-pad" filter="url(#{uid}-glow-soft)">',
        f'      <path d="{pad_path()}" fill="url(#{uid}-pad)" stroke="{C["electric"]}" stroke-width="5"/>',
        # top highlight
        f'      <path d="M{f(p["x0"] + 60)},{f(p["top"] + 14)} C{f(p["x0"] + 120)},{f(p["top"] - 6)} '
        f'{f(p["x1"] - 120)},{f(p["top"] - 6)} {f(p["x1"] - 60)},{f(p["top"] + 14)}" '
        f'stroke="#FFFFFF" stroke-opacity="0.22" stroke-width="6" fill="none" stroke-linecap="round"/>',
        # d-pad
        f'      <g fill="{C["electric"]}">',
        f'        <rect x="{f(cx_dpad - 30)}" y="{f(cy_dpad - 9)}" width="60" height="19" rx="6"/>',
        f'        <rect x="{f(cx_dpad - 9)}" y="{f(cy_dpad - 30)}" width="19" height="60" rx="6"/>',
        "      </g>",
        # action buttons
        f'      <g stroke="none">',
        f'        <circle cx="{f(cx_btn)}" cy="{f(cy_btn)}" r="11" fill="{C["gold"]}"/>',
        f'        <circle cx="{f(cx_btn + 36)}" cy="{f(cy_btn + 20)}" r="11" fill="{C["electric"]}"/>',
        f'        <circle cx="{f(cx_btn - 36)}" cy="{f(cy_btn + 20)}" r="11" fill="{C["gold_lo"]}"/>',
        f'        <circle cx="{f(cx_btn)}" cy="{f(cy_btn + 38)}" r="11" fill="#3FC1FF"/>',
        "      </g>",
        "    </g>",
    ]
    return out


# ════════════════════════════════════════════════════════════════════════════
# Lockups
# ════════════════════════════════════════════════════════════════════════════
def word_paths(ol: Outliner, gaps=None):
    """MEEM / STORE / tagline as centred paths + measured boxes."""
    meem_d, meem_b = ol.text("MEEM", 180, tracking_em=0.105, origin=(0, 0))
    store_d, store_b = ol.text("STORE", 74, tracking_em=0.34, origin=(0, 0))
    tag_d, tag_b = ol.text("PLAY", 40, tracking_em=0.30, origin=(0, 0))
    return dict(meem=(meem_d, meem_b), store=(store_d, store_b), tag=(tag_d, tag_b))


def place_ink(box, ink_top: float, cx: float = 500.0):
    """Translate a measured text box so its ink top sits at `ink_top`, centred on `cx`."""
    x0, y0, x1, y1 = box
    return dict(dx=cx - (x0 + x1) / 2, dy=ink_top - y0, w=x1 - x0, h=y1 - y0,
                top=ink_top, bottom=ink_top + (y1 - y0))


def tagline_group(ol: Outliner, cx: float, ink_top: float) -> tuple[str, float]:
    """PLAY ▾ GAMES ▾ MORE with gold chevron separators. Returns (svg, width)."""
    words = ["PLAY", "GAMES", "MORE"]
    parts = [ol.text(w, 40, tracking_em=0.30, origin=(0, 0)) for w in words]
    chev, gap = 22.0, 30.0
    widths = [b[2] - b[0] for _, b in parts]
    total = sum(widths) + 2 * (chev + 2 * gap)
    h = max(b[3] - b[1] for _, b in parts)
    x = cx - total / 2
    out = [f'  <g fill="#FFFFFF" fill-opacity="0.9">']
    for i, (d, b) in enumerate(parts):
        out.append(f'    <path d="{d}" transform="translate({f(x - b[0])},{f(ink_top - b[1])})"/>')
        x += widths[i]
        if i < len(words) - 1:
            x += gap
            cy = ink_top + h * 0.55
            out.append(f'    <path d="M{f(x)},{f(cy - 11)} L{f(x + chev)},{f(cy - 11)} L{f(x + chev / 2)},{f(cy + 11)} Z" '
                       f'fill="{C["gold"]}" fill-opacity="1"/>')
            x += chev + gap
    out.append("  </g>")
    return "\n".join(out), total


def wordmark_group(ol: Outliner, uid: str, y0: float = 0.0, cx: float = 500.0):
    """MEEM / — STORE — / tagline as one group in its own 1000-wide box.

    Returns (svg, height) so callers can stack it under the emblem at full size
    (the logo) or scale it into a tighter composition (the social card).
    """
    w = word_paths(ol)
    meem = place_ink(w["meem"][1], y0 + 30, cx)
    store = place_ink(w["store"][1], y0 + 30 + meem["h"] + 74, cx)
    tag_svg, _ = tagline_group(ol, cx, y0 + 30 + meem["h"] + 74 + store["h"] + 74)
    dash_len, dash_gap = 104, 40
    dash_y = store["top"] + store["h"] * 0.68
    s_l = store["dx"] + w["store"][1][0]
    s_r = store["dx"] + w["store"][1][2]
    height = (y0 + 30 + meem["h"] + 74 + store["h"] + 74 + store["h"] * 0 + 40) + 34
    body = f"""  <g id="{uid}-wordmark">
    <path d="{w['meem'][0]}" transform="translate({f(meem['dx'])},{f(meem['dy'])})" fill="url(#{uid}-word)" filter="url(#{uid}-glow-soft)"/>
    <path d="{w['store'][0]}" transform="translate({f(store['dx'])},{f(store['dy'])})" fill="url(#{uid}-gold)"/>
    <g stroke="{C['gold']}" stroke-width="9" stroke-linecap="round">
      <line x1="{f(s_l - dash_gap - dash_len)}" y1="{f(dash_y)}" x2="{f(s_l - dash_gap)}" y2="{f(dash_y)}"/>
      <line x1="{f(s_r + dash_gap)}" y1="{f(dash_y)}" x2="{f(s_r + dash_gap + dash_len)}" y2="{f(dash_y)}"/>
    </g>
  </g>
{tag_svg}"""
    return body, height


def stacked_svg(ol: Outliner) -> str:
    """Vertical lockup: emblem over MEEM over — STORE — over the tagline."""
    uid = "st"
    wm, wm_h = wordmark_group(ol, uid)
    top = 1024
    H = top + wm_h
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 {f(H)}" role="img" aria-label="MEEM STORE — PLAY GAMES MORE">
{emblem_defs(uid)}
{emblem_body(uid)}
  <g transform="translate(0,{f(top)})">
{wm}
  </g>
</svg>
"""


def horizontal_svg(ol: Outliner) -> str:
    """Navbar lockup: emblem beside the wordmark block, sized for a header bar."""
    uid = "hz"
    mark, gap = 358, 34
    scale = mark / 1000
    meem_d, meem_b = ol.text("MEEM", 156, tracking_em=0.105, origin=(0, 0))
    store_d, store_b = ol.text("STORE", 58, tracking_em=0.34, origin=(0, 0))
    mw, mh = meem_b[2] - meem_b[0], meem_b[3] - meem_b[1]
    sw, sh = store_b[2] - store_b[0], store_b[3] - store_b[1]
    dash_len, dash_gap = 64, 22
    H = 400
    block_h = mh + 48 + sh
    top = (H - block_h) / 2
    text_left = mark + gap
    text_w = max(mw, sw + 2 * (dash_gap + dash_len))
    meem_dx = text_left + (text_w - mw) / 2 - meem_b[0]
    meem_dy = top - meem_b[1]
    store_dx = text_left + (text_w - sw) / 2 - store_b[0]
    store_dy = top + mh + 48 - store_b[1]
    dash_y = top + mh + 48 + sh * 0.66
    W = mark + gap + text_w + 8
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {f(W)} {H}" role="img" aria-label="MEEM STORE">
{emblem_defs(uid)}
  <g transform="translate(4,{f((H - mark) / 2)}) scale({f(scale)})">
{compact_mark(uid, scale=1.0, cy=500.0, sweep=(190, 292), stroke=54, hole=True)}
  </g>
  <g>
    <path d="{meem_d}" transform="translate({f(meem_dx)},{f(meem_dy)})" fill="url(#{uid}-word)" filter="url(#{uid}-glow-soft)"/>
    <path d="{store_d}" transform="translate({f(store_dx)},{f(store_dy)})" fill="url(#{uid}-gold)"/>
    <g stroke="{C['gold']}" stroke-width="7" stroke-linecap="round">
      <line x1="{f(store_dx + store_b[0] - dash_gap - dash_len)}" y1="{f(dash_y)}" x2="{f(store_dx + store_b[0] - dash_gap)}" y2="{f(dash_y)}"/>
      <line x1="{f(store_dx + store_b[2] + dash_gap)}" y1="{f(dash_y)}" x2="{f(store_dx + store_b[2] + dash_gap + dash_len)}" y2="{f(dash_y)}"/>
    </g>
  </g>
</svg>
"""


def compact_mark(uid: str, scale: float = 1.06, cy: float = 516.0, sweep: tuple = (196, 286),
                stroke: float = 52, hole: bool = False, flat: bool = False) -> str:
    """Crown + M + a single gold orbit sweep: the mark that survives small sizes."""
    fill_m = "#EAF0FB" if flat else f"url(#{uid}-steel)"
    stroke_m = f' stroke="#0B1B3A" stroke-width="14"' if flat else ""
    sweep_svg = (f'    <path d="{polyline_path(ring_arc_points(sweep[0], sweep[1], 32))}" fill="none" '
                 f'stroke="{C["gold"]}" stroke-width="{f(stroke)}" stroke-linecap="round"/>\n') if stroke else ""
    return f"""  <g transform="translate(500,{f(cy)}) scale({f(scale)}) translate(-500,-{f(cy)})">
    <path d="{crown_path(hole=hole)}" fill="{C['gold']}"/>
    <path d="{m_path()}" fill="{fill_m}"{stroke_m}/>
{sweep_svg}  </g>"""


# "on light" lockup: the same geometry re-inked for pale headers (light theme)
LIGHT_INK = {
    "#F4F8FF": "#B4C4E0", "#C3D2EC": "#8FA6CE", "#93A8CE": "#6E84AC", "#5A6E96": "#42557A",
    "#FFFFFF": "#092A91", "#E7EEFC": "#0A2FA8", "#A9BCDD": "#06205F",
    "#FFF3B0": "#F2B705", "#FFD400": "#C98A0A", "#E6A200": "#9C6B00",
}


def light_variant(svg: str) -> str:
    """Re-ink a lockup for light backgrounds (navy wordmark, deeper gold, darker steel)."""
    for src, dst in LIGHT_INK.items():
        svg = svg.replace(src, dst)
    svg = svg.replace('stroke="#FFFFFF"', 'stroke="#092A91"')
    return svg.replace('aria-label=', 'data-variant="light" aria-label=', 1)


def mark_svg(simple: bool = False) -> str:
    """Emblem only — transparent, square. Used for headers, avatars, watermarks."""
    uid = "mk"
    body = emblem_body(uid, with_ring_front=not simple, simple=simple)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" role="img" aria-label="MEEM STORE">
{emblem_defs(uid)}
{body}
</svg>
"""


def favicon_svg() -> str:
    """Simplified app mark: crown + M + one gold orbit sweep. Stays readable at 16px."""
    uid = "fv"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" role="img" aria-label="MEEM STORE">
{emblem_defs(uid)}
  <rect width="1000" height="1000" rx="196" fill="{C['royal']}"/>
{compact_mark(uid)}
</svg>
"""


def favicon16_svg() -> str:
    """Extra-bold 16px favicon: flat fills, no fine detail — survives downsampling."""
    uid = "f16"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" role="img" aria-label="MEEM STORE">
  <rect width="1000" height="1000" rx="210" fill="{C['royal']}"/>
{compact_mark(uid, scale=1.26, cy=512.0, sweep=(200, 280), stroke=0, flat=True)}
</svg>
"""


def og_svg(ol: Outliner) -> str:
    """1200x630 social card: brand background, corner ribbons, emblem + lockup."""
    uid = "og"
    wm, wm_h = wordmark_group(ol, uid, y0=0)
    ws = 0.52                      # wordmark scale
    ex, ey, es = 46, 108, 0.42     # emblem placement (keeps it clear of the copy)
    tx = 1200 - 1000 * ws - 96
    ty = (630 - wm_h * ws) / 2
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" role="img" aria-label="MEEM STORE — PLAY GAMES MORE">
{emblem_defs(uid)}
  <defs>
    <radialGradient id="{uid}-bg" cx="0.3" cy="0.36" r="0.95">
      <stop offset="0" stop-color="{C['royal_hi']}"/><stop offset="0.55" stop-color="{C['royal']}"/>
      <stop offset="1" stop-color="{C['bg']}"/>
    </radialGradient>
    <linearGradient id="{uid}-ribbon" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{C['electric']}"/><stop offset="1" stop-color="{C['royal_hi']}"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#{uid}-bg)"/>
  <path d="M0,0 L250,0 L0,250 Z" fill="url(#{uid}-ribbon)" opacity="0.5"/>
  <path d="M0,0 L94,0 L0,94 Z" fill="{C['gold']}" opacity="0.92"/>
  <path d="M1200,630 L950,630 L1200,380 Z" fill="url(#{uid}-ribbon)" opacity="0.42"/>
  <path d="M1200,630 L1106,630 L1200,536 Z" fill="{C['gold']}" opacity="0.88"/>
  <line x1="40" y1="622" x2="1160" y2="622" stroke="{C['gold']}" stroke-width="8" opacity="0.7"/>
  <g transform="translate({f(ex)},{f(ey)}) scale({f(es)})">
{emblem_body(uid)}
  </g>
  <g transform="translate({f(tx)},{f(ty)}) scale({f(ws)})">
{wm}
  </g>
</svg>
"""


def icon_svg(pad: float = 0.10) -> str:
    """Full emblem on the brand-blue rounded square (PWA / apple-touch)."""
    uid = "ic"
    inner = 1 - pad * 2
    sc = inner
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" role="img" aria-label="MEEM STORE">
{emblem_defs(uid)}
  <rect width="1000" height="1000" fill="url(#{uid}-iconbg)"/>
  <g transform="translate({f(1000 * pad)},{f(1000 * pad + 74)}) scale({f(sc)})">
{emblem_body(uid)}
  </g>
  <defs>
    <radialGradient id="{uid}-iconbg" cx="0.4" cy="0.35" r="0.9">
      <stop offset="0" stop-color="{C['royal_hi']}"/><stop offset="0.6" stop-color="{C['royal']}"/>
      <stop offset="1" stop-color="{C['bg']}"/>
    </radialGradient>
  </defs>
</svg>
"""


# ════════════════════════════════════════════════════════════════════════════
# Rasterisation
# ════════════════════════════════════════════════════════════════════════════
def raster(svg_path: Path, png_path: Path, width: int, bg: str | None = None) -> None:
    helper = ROOT / "scripts" / "svg_rasterize.mjs"
    cmd = ["node", str(helper), str(svg_path), str(png_path), str(width)]
    if bg:
        cmd += ["--bg", bg]
    subprocess.run(cmd, check=True, cwd=ROOT, capture_output=True)


def webp_and_ico(png_paths):
    from PIL import Image

    for p in png_paths:
        im = Image.open(p)
        im.save(p.with_suffix(".webp"), "WEBP", quality=92, method=6)
    print("  webp   written")


def write_ico(png_paths, out: Path):
    from PIL import Image

    frames = [Image.open(p).convert("RGBA") for p in png_paths]
    frames[0].save(out, format="ICO", sizes=[(i.width, i.height) for i in frames], append_images=frames[1:])
    print(f"  ico    {out.name} ({', '.join(str(i.width) for i in frames)})")


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the MEEM STORE brand asset set.")
    ap.add_argument("--font", type=Path, default=None, help="Orbitron TTF (fetched into .cache/brand-build when omitted)")
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    ap.add_argument("--svg-only", action="store_true", help="skip PNG/ICO/WebP rasterization")
    ap.add_argument("--preview", type=Path, default=None, help="also rasterize review PNGs into this directory")
    ap.add_argument("--preview-width", type=int, default=900)
    args = ap.parse_args()

    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    font = ensure_font(args.font)
    print(f"MEEM brand builder → {out.relative_to(ROOT)}")
    ol = Outliner(font, weight=900)

    svgs = {
        "meem-mark.svg": mark_svg(),
        "meem-logo.svg": stacked_svg(ol),
        "meem-logo-horizontal.svg": horizontal_svg(ol),
        "favicon.svg": favicon_svg(),
    }
    svgs["meem-logo-horizontal-light.svg"] = light_variant(svgs["meem-logo-horizontal.svg"])
    for name, body in svgs.items():
        (out / name).write_text(body, encoding="utf-8")
        print(f"  svg    {name} ({len(body) // 1024} KB)")
    CACHE.mkdir(parents=True, exist_ok=True)
    build_only = {"_og.svg": og_svg(ol), "_icon.svg": icon_svg(), "_favicon16.svg": favicon16_svg()}
    for name, body in build_only.items():
        (CACHE / name).write_text(body, encoding="utf-8")
        print(f"  src    .cache/brand-build/{name} ({len(body) // 1024} KB)")

    if args.svg_only:
        return 0

    jobs = [
        (out / "meem-logo.svg", out / "meem-logo.png", 900, None),
        (out / "meem-mark.svg", out / "meem-mark.png", 512, None),
        (CACHE / "_favicon16.svg", out / "favicon-16.png", 16, None),
        (out / "favicon.svg", out / "favicon-32.png", 32, None),
        (out / "favicon.svg", out / "favicon-48.png", 48, None),
        (CACHE / "_icon.svg", out / "meem-icon-180.png", 180, None),
        (CACHE / "_icon.svg", out / "meem-icon-192.png", 192, None),
        (CACHE / "_icon.svg", out / "meem-icon-512.png", 512, None),
        (CACHE / "_og.svg", out / "meem-og.png", 1200, None),
    ]
    for src, dst, width, bg in jobs:
        raster(src, dst, width, bg)
        print(f"  png    {dst.name} ({width}px)")
    webp_and_ico([out / "meem-logo.png", out / "meem-mark.png"])
    write_ico([out / "favicon-48.png", out / "favicon-32.png", out / "favicon-16.png"], out / "favicon.ico")

    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        preview_srcs = [out / n for n in ("meem-logo.svg", "meem-logo-horizontal.svg",
                                          "meem-mark.svg", "favicon.svg")] + [CACHE / "_og.svg", CACHE / "_icon.svg"]
        for src in preview_srcs:
            raster(src, args.preview / (src.name.lstrip("_").replace(".svg", ".png")),
                   1200 if src == CACHE / "_og.svg" else args.preview_width)
        print(f"  preview {args.preview}")

    # keep the repo asset dir self-contained: the underscore files are build inputs only
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
