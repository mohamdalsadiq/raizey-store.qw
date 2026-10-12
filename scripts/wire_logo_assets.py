#!/usr/bin/env python3
"""
MEEM STORE — wire the real logo assets (derived from assets/img/meem-logo.png)
into the pages. Idempotent: running it twice changes nothing.

  1. icon set on every page (32 / 192 / ico / apple-touch-180)
  2. header brand: square mark (crown + M + gamepad), rounded tile
  3. auth cards + receipt: the full master logo
  4. strips the previous vector-lockup markup and its theme-toggle CSS

og:/twitter: meta keep pointing at assets/img/meem-og.png (absolute production URL).
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE_ORIGIN = "https://raizey-store-qw.vercel.app"

ICON_OLD = """<link rel="icon" type="image/svg+xml" href="assets/img/favicon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="assets/img/favicon-32.png">
<link rel="icon" sizes="any" href="assets/img/favicon.ico">
<link rel="apple-touch-icon" sizes="180x180" href="assets/img/meem-icon-180.png">"""
ICON_NEW = """<link rel="icon" type="image/png" sizes="32x32" href="assets/img/favicon-32.png">
<link rel="icon" type="image/png" sizes="192x192" href="assets/img/favicon-192.png">
<link rel="icon" sizes="any" href="assets/img/favicon.ico">
<link rel="apple-touch-icon" sizes="180x180" href="assets/img/favicon-180.png">"""

MARK = ('<img class="brand-mark" src="assets/img/meem-mark.png" alt="MEEM STORE" '
        'width="44" height="44">')
FULL = ('<img class="brand-lockup" src="assets/img/meem-logo.png" alt="MEEM STORE" '
        'width="172" height="172">')
FULL_RECEIPT = ('<img class="brand-lockup" src="assets/img/meem-logo.png" alt="MEEM STORE" '
                'width="150" height="150">')

HEADER_RE = re.compile(r'<a class="logo"[^>]*>.*?</a>', re.S)
HEADER_OLD_DIV = re.compile(r'<div class="logo"[^>]*>.*?</div>\s*(?=<div class="header-actions">)', re.S)
AUTH_RE = re.compile(r'<div class="auth-logo">.*?</div>', re.S)
RECEIPT_RE = re.compile(r'<div class="receipt-brand">.*?</div>', re.S)

HEADER_NEW = ('<a class="logo" href="index.html" aria-label="MEEM STORE">\n'
              f'      {MARK}\n'
              '    </a>')
AUTH_NEW = ('<div class="auth-logo">\n'
            f'      {FULL}\n'
            '    </div>')
RECEIPT_NEW = ('<div class="receipt-brand">\n'
               f'    {FULL_RECEIPT}\n'
               '  </div>')

CSS_CLEAN = [
    (ROOT / "assets" / "css" / "meem.css",
     "/* Brand lockups (assets/img/meem-*) — see scripts/build_logo_assets.py */",
     '/* Brand mark (assets/img/meem-mark.png) — derived from meem-logo.png */\n'
     '.logo .brand-mark { display: block; width: 44px; height: 44px; border-radius: 12px;\n'
     '  box-shadow: 0 2px 10px rgba(0, 0, 0, .3); }\n'
     '.logo:hover .brand-mark { filter: brightness(1.07); }'),
    (ROOT / "assets" / "css" / "auth.css",
     ".auth-logo .brand-lockup { display: block; width: 200px; height: auto; margin: 0 auto; }",
     ".auth-logo .brand-lockup { display: block; width: 172px; height: 172px; margin: 0 auto;\n"
     "  border-radius: 24px; box-shadow: 0 12px 30px rgba(4, 18, 63, .28); }"),
]


def strip_toggles(text: str) -> str:
    """Remove the light/dark lockup switching nothing needs any more."""
    return re.sub(r"\n?[^\n]*brand-lockup--(?:dark|light)[^\n]*", "", text)


def wire_page(page: Path) -> bool:
    original = text = page.read_text(encoding="utf-8")
    text = text.replace(ICON_OLD, ICON_NEW)
    if 'class="logo"' in text:
        text = HEADER_RE.sub(HEADER_NEW, text) if HEADER_RE.search(text) else text
        if 'class="brand-mark"' not in text:
            text = HEADER_OLD_DIV.sub(HEADER_NEW, text)
    if 'class="auth-logo"' in text and 'brand-lockup' in text:
        text = AUTH_RE.sub(AUTH_NEW, text)
    if 'class="receipt-brand"' in text:
        text = RECEIPT_RE.sub(RECEIPT_NEW, text)
    text = strip_toggles(text)
    if text != original:
        page.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> int:
    touched = []
    for page in sorted(ROOT.glob("*.html")):
        if wire_page(page):
            touched.append(page.name)
    for css, old_anchor, new_block in CSS_CLEAN:
        before = text = css.read_text(encoding="utf-8")
        text = strip_toggles(text)
        if old_anchor in text:
            text = text.replace(old_anchor, new_block)
        elif "brand-mark }" not in text:
            text = text.rstrip("\n") + "\n\n" + new_block + "\n"
        if text != before:
            css.write_text(text, encoding="utf-8")
            print(f"  css    {css.relative_to(ROOT)}")
    for name in touched:
        print(f"  page   {name}")
    print(f"{len(touched)} page(s) updated" if touched else "already wired — nothing to do")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
