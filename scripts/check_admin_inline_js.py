from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
failed = []
with tempfile.TemporaryDirectory(prefix='raizey-admin-js-') as tmp:
    tmp_path = Path(tmp)
    for page in sorted(root.glob('admin*.html')):
        blocks = re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', page.read_text(encoding='utf-8', errors='ignore'), re.S)
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
print('[PASS] all admin inline JavaScript blocks are syntactically valid')
