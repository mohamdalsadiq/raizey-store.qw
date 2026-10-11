#!/usr/bin/env python3
"""
MEEM STORE — wire the brand asset set (assets/img/meem-*, favicon-*) into the pages.

Idempotent: running it twice changes nothing. It

  1. gives every page the icon set (SVG + 32px PNG + ICO + apple-touch-icon),
  2. adds the social-card meta (og:/twitter:) to the storefront + auth pages,
  3. swaps the Phase 1 text placeholders for the real logo lockups
     (site header, auth cards, receipt page).

Run after scripts/build_brand_assets.py. Uses the live production origin for the
absolute og:image URL — update SITE_ORIGIN when the project is renamed.
"""
from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE_ORIGIN = "https://raizey-store-qw.vercel.app"

ICON_BLOCK = """<link rel="icon" type="image/svg+xml" href="assets/img/favicon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="assets/img/favicon-32.png">
<link rel="icon" sizes="any" href="assets/img/favicon.ico">
<link rel="apple-touch-icon" sizes="180x180" href="assets/img/meem-icon-180.png">"""

OG_PAGES = ["index.html", "product.html", "category.html", "search.html",
            "cart.html", "login.html", "register.html"]
HEADER_PAGES = ["index.html", "search.html"]
AUTH_PAGES = ["login.html", "register.html", "forgot-password.html",
              "reset-password.html", "verify.html", "privacy.html"]

# lockup geometry: meem-logo-horizontal.svg is 942.95 x 400
HDR_H = 40
HDR_W = round(942.95 / 400 * HDR_H)
AUTH_H = 54
AUTH_W = round(942.95 / 400 * AUTH_H)

AUTH_OLD = """    <div class="auth-logo">
      <!-- MEEM mark (Phase 1a): <span class="brand-mark"><img src="assets/img/meem-mark.png" alt="شعار MEEM STORE"></span> -->
      <span class="brand-text">MEEM <em>STORE</em></span>
    </div>"""
def lockup_imgs(indent: str, size: str, alt_visible: bool = True) -> str:
    """Dark + light lockup pair: CSS shows the one that matches the active theme."""
    alt = ' alt="MEEM STORE"' if alt_visible else ' alt=""'
    dark = (indent + '<img class="brand-lockup brand-lockup--dark" '
            'src="assets/img/meem-logo-horizontal.svg"' + alt + size + '>')
    light = (indent + '<img class="brand-lockup brand-lockup--light" '
             'src="assets/img/meem-logo-horizontal-light.svg" alt="MEEM STORE" aria-hidden="true"' + size + '>')
    return dark + chr(10) + light


AUTH_NEW = f"""    <div class="auth-logo">
{lockup_imgs("      ", f' width="{AUTH_W}" height="{AUTH_H}"')}
    </div>"""

HEADER_OLD = """    <div class="logo" style="display: flex; align-items: center; gap: 8px;">
<!-- MEEM mark: enable once assets/img/meem-mark.png exists (Phase 1a) -->
      <!-- <img class="hex-logo" src="assets/img/meem-mark.png" width="36" height="36" alt="شعار MEEM STORE"> -->
      <span dir="ltr" style="unicode-bidi: isolate; font-weight: 900; color: var(--text-light);">MEEM <span style="color: var(--mm-accent-text);">STORE</span></span>
    </div>"""
HEADER_NEW = f"""    <a class="logo" href="index.html" aria-label="MEEM STORE">
{lockup_imgs("      ", f' width="{HDR_W}" height="{HDR_H}"')}
    </a>"""

RECEIPT_CSS = """.receipt-brand {
    display: flex;
    justify-content: center;
    margin: 2px 0 18px;
  }
  .receipt-brand img { width: 158px; height: auto; }
"""

TOGGLE_RULES = """/* light theme uses the re-inked lockup (navy wordmark, deeper gold) */
.brand-lockup--light { display: none; }
[data-theme="light"] .brand-lockup--dark { display: none; }
[data-theme="light"] .brand-lockup--light { display: block; }"""

CSS_RULES = {
    "assets/css/meem.css": """/* Brand lockups (assets/img/meem-*) — see scripts/build_brand_assets.py */
.logo .brand-lockup { display: block; width: auto; height: 40px; }
.logo:hover .brand-lockup--dark { filter: brightness(1.06); }
""" + TOGGLE_RULES + "\n",
    "assets/css/auth.css": """.auth-logo .brand-lockup { display: block; width: 200px; height: auto; margin: 0 auto; }
""" + TOGGLE_RULES + "\n",
    "receipt.html": None,  # inline styles handled below
}
CSS_LOOKUP = {k: v for k, v in CSS_RULES.items() if v}


def add_icons(text: str) -> tuple[str, bool]:
    if "assets/img/favicon.svg" in text:
        return text, False
    if '<link rel="icon" type="image/svg+xml" href="favicon.svg">' in text:
        return text.replace('<link rel="icon" type="image/svg+xml" href="favicon.svg">', ICON_BLOCK), True
    m = re.search(r"</title>\n", text)
    if not m:
        return text, False
    return text[: m.end()] + ICON_BLOCK + "\n" + text[m.end():], True


def add_og(text: str, page: str) -> tuple[str, bool]:
    if 'property="og:image"' in text:
        return text, False
    title = re.search(r"<title>(.*?)</title>", text, re.S)
    desc = re.search(r'<meta name="description" content="(.*?)">', text, re.S)
    title_v = html.escape(title.group(1).strip(), quote=True) if title else "MEEM STORE"
    desc_v = html.escape(desc.group(1).strip(), quote=True) if desc else \
        "متجر MEEM STORE لشحن الألعاب والبطاقات الرقمية."
    block = f"""<meta property="og:type" content="website">
<meta property="og:site_name" content="MEEM STORE">
<meta property="og:title" content="{title_v}">
<meta property="og:description" content="{desc_v}">
<meta property="og:image" content="{SITE_ORIGIN}/assets/img/meem-og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="{SITE_ORIGIN}/assets/img/meem-og.png">"""
    anchor = f'{ICON_BLOCK}\n'
    if anchor in text:
        return text.replace(anchor, anchor + block + "\n", 1), True
    return text, False


IMG_RE = re.compile(
    r'<img class="brand-lockup" src="assets/img/meem-logo-horizontal\.svg"(?P<attrs>[^>]*?)>'
)


RECEIPT_OLD = ('<div class="receipt-brand">'
               '<img src="assets/img/meem-logo-horizontal.svg" alt="MEEM STORE"></div>')
LIGHT_ALT_OLD = 'src="assets/img/meem-logo-horizontal-light.svg" alt="" aria-hidden="true"'
LIGHT_ALT_NEW = 'src="assets/img/meem-logo-horizontal-light.svg" alt="MEEM STORE" aria-hidden="true"'
RECEIPT_SIZE = ' width="158" height="67"'
RECEIPT_SIZED = '<div class="receipt-brand">' + chr(10) + lockup_imgs("    ", RECEIPT_SIZE) + chr(10) + '  </div>'
RECEIPT_NEW = RECEIPT_SIZED


def fix_indent(text: str) -> str:
    """Keep the two lockup <img> lines aligned after an in-place upgrade."""
    pattern = chr(10) + '[ ]{8,}<img class="brand-lockup brand-lockup--dark"'
    return re.sub(pattern, chr(10) + '      <img class="brand-lockup brand-lockup--dark"', text)


RECEIPT_BLOCK_RE = re.compile(r'<div class="receipt-brand">.*?</div>', re.S)


def normalize_imgs(text: str) -> str:
    """Non-empty alt on the (aria-hidden) light lockup + explicit receipt dimensions."""
    text = text.replace(LIGHT_ALT_OLD, LIGHT_ALT_NEW)
    return RECEIPT_BLOCK_RE.sub(RECEIPT_SIZED, text, count=1)


def upgrade_pair(text: str) -> str:
    """Replace an already-wired single lockup <img> with the dark/light pair."""
    if "meem-logo-horizontal-light.svg" in text:
        return text
    def repl(m: re.Match) -> str:
        attrs = m.group("attrs").strip()
        size = "".join(f' {a}' for a in re.findall(r'(?:width|height)="[^"]*"', attrs))
        line_start = text.rfind("\n", 0, m.start()) + 1
        indent = text[line_start:m.start()]
        indent = indent if indent.strip() == "" else ""
        return lockup_imgs(indent or "      ", size)
    return IMG_RE.sub(repl, text)


def main() -> int:
    changed = False
    for page in sorted(ROOT.glob("*.html")):
        rel = page.name
        text = original = page.read_text(encoding="utf-8")
        text = normalize_imgs(fix_indent(upgrade_pair(text)))
        if RECEIPT_OLD in text:
            text = text.replace(RECEIPT_OLD, RECEIPT_NEW)
        text, _ = add_icons(text)
        if rel in OG_PAGES:
            text, _ = add_og(text, rel)
        if rel in HEADER_PAGES and HEADER_OLD in text:
            text = text.replace(HEADER_OLD, HEADER_NEW)
        if rel in AUTH_PAGES and AUTH_OLD in text:
            text = text.replace(AUTH_OLD, AUTH_NEW)
        if rel == "receipt.html" and "receipt-brand" not in text:
            text = text.replace('  .receipt-page {', "  " + RECEIPT_CSS.replace("\n    ", "\n    ").rstrip() +
                                "\n\n  .receipt-page {", 1)
            text = text.replace('<div class="receipt-page">\n',
                                '<div class="receipt-page">\n  <div class="receipt-brand">\n'
                                + lockup_imgs("    ", RECEIPT_SIZE) + '\n  </div>\n', 1)
        if text != original:
            page.write_text(text, encoding="utf-8")
            print(f"  page   {rel}")
            changed = True
    for css, rule in CSS_LOOKUP.items():
        p = ROOT / css
        text = p.read_text(encoding="utf-8")
        if ".brand-lockup--light" not in text:
            p.write_text(text.rstrip("\n") + "\n\n" + rule, encoding="utf-8")
            print(f"  css    {css}")
            changed = True
    # receipt page keeps its styles inline
    rp = ROOT / "receipt.html"
    rtext = rp.read_text(encoding="utf-8")
    if ".brand-lockup--light" not in rtext:
        rp.write_text(rtext.replace("  .receipt-brand img { width: 158px; height: auto; }",
                                    "  .receipt-brand img { width: 158px; height: auto; }\n  " + TOGGLE_RULES.replace("\n", "\n  ")),
                      encoding="utf-8")
        print("  css    receipt.html (inline)")
        changed = True
    print("wired" if changed else "already wired — nothing to do")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
