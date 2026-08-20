from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = '<script src="assets/js/admin-nav.js"></script>'

for path in sorted(ROOT.glob('admin*.html')):
    text = path.read_text(encoding='utf-8')
    if SCRIPT in text:
        continue
    marker = '</body>'
    if marker not in text:
        raise SystemExit(f'Missing body marker: {path.name}')
    text = text.replace(marker, f'  {SCRIPT}\n{marker}', 1)
    path.write_text(text, encoding='utf-8')
    print(path.name)
