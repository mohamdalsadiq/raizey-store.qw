from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]

for path in root.glob("*.html"):
    text = path.read_text(encoding="utf-8")
    updated = text.replace(
        'content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"',
        'content="width=device-width, initial-scale=1.0, viewport-fit=cover"',
    )
    if updated != text:
        path.write_text(updated, encoding="utf-8")

# Replace only known transition: all declarations; keep the existing visual timing.
css_path = root / "assets/css/style.css"
css = css_path.read_text(encoding="utf-8")
css = css.replace("transition: all 0.3s ease;", "transition: transform 0.3s ease, border-color 0.3s ease, box-shadow 0.3s ease, background-color 0.3s ease;")
css = css.replace("transition: all 0.2s ease;", "transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease, background-color 0.2s ease, color 0.2s ease;")
css_path.write_text(css, encoding="utf-8")

index_path = root / "index.html"
index = index_path.read_text(encoding="utf-8")
index = index.replace("transition: all 0.25s ease-in-out !important;", "transition: transform 0.25s ease-in-out, border-color 0.25s ease-in-out, box-shadow 0.25s ease-in-out, background-color 0.25s ease-in-out !important;")
index = index.replace("transition: all 0.2s !important;", "transition: transform 0.2s, opacity 0.2s, color 0.2s, background-color 0.2s !important;")
index_path.write_text(index, encoding="utf-8")
