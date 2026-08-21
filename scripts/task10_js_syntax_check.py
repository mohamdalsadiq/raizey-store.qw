from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
failures = []
checked = 0

for html_path in sorted(root.glob("*.html")):
    text = html_path.read_text(encoding="utf-8")
    chunks = []
    marker = 0
    while True:
        start = text.find("<script", marker)
        if start < 0:
            break
        body_start = text.find(">", start)
        body_end = text.find("</script>", body_start)
        if body_start < 0 or body_end < 0:
            break
        tag = text[start:body_start]
        if "src=" not in tag:
            chunks.append(text[body_start + 1:body_end])
        marker = body_end + len("</script>")
    for index, chunk in enumerate(chunks, 1):
        checked += 1
        with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as handle:
            handle.write(chunk)
            temp_path = handle.name
        result = subprocess.run(["node", "--check", temp_path], capture_output=True, text=True)
        Path(temp_path).unlink(missing_ok=True)
        if result.returncode:
            failures.append((html_path.name, index, result.stderr.strip()))

print(f"Checked inline scripts: {checked}")
if failures:
    for file_name, index, message in failures:
        print(f"FAIL {file_name} script[{index}]: {message}")
    raise SystemExit(1)
print("PASS: all inline scripts parse successfully")
