from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PAGES = [ROOT / 'index.html', ROOT / 'category.html', ROOT / 'product.html']
failed = []

with tempfile.TemporaryDirectory(prefix='raizey-storefront-js-') as tmp:
    tmp_path = Path(tmp)
    for page in PAGES:
        blocks = re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', page.read_text(encoding='utf-8'), re.S)
        for index, block in enumerate(blocks, 1):
            script = tmp_path / f'{page.stem}-{index}.js'
            script.write_text(block, encoding='utf-8')
            result = subprocess.run(['node', '--check', str(script)], capture_output=True, text=True)
            if result.returncode:
                failed.append((page.name, index, result.stderr.strip()))

if failed:
    for page, index, error in failed:
        print(f'[FAIL] {page} script {index}: {error}')
    raise SystemExit(1)
print('[PASS] storefront inline JavaScript syntax valid')
