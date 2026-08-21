from pathlib import Path
from bs4 import BeautifulSoup

root = Path(__file__).resolve().parents[1]
findings = []

for path in sorted(root.glob("*.html")):
    soup = BeautifulSoup(path.read_text(encoding="utf-8"), "html.parser")
    viewport = soup.find("meta", attrs={"name": "viewport"})
    if not viewport or "user-scalable=no" in viewport.get("content", "") or "maximum-scale" in viewport.get("content", ""):
        findings.append((path.name, "viewport", "zoom disabled or viewport missing"))
    for index, img in enumerate(soup.find_all("img"), 1):
        if not img.get("alt"):
            findings.append((path.name, f"img[{index}]", "missing alt"))
        if not img.get("width") or not img.get("height"):
            findings.append((path.name, f"img[{index}]", "missing explicit width/height"))
    for index, button in enumerate(soup.find_all("button"), 1):
        text = " ".join(button.get_text(" ", strip=True).split())
        if not text and not button.get("aria-label") and not button.get("title"):
            findings.append((path.name, f"button[{index}]", "icon-only button lacks aria-label/title"))
    for index, control in enumerate(soup.find_all(["input", "select", "textarea"]), 1):
        if control.get("type") == "hidden":
            continue
        control_id = control.get("id")
        labelled = control.get("aria-label") or control.get("aria-labelledby")
        if control_id and soup.find("label", attrs={"for": control_id}):
            labelled = True
        if not labelled:
            findings.append((path.name, f"control[{index}]", "form control lacks label or aria-label"))
    for index, style in enumerate(soup.find_all("style"), 1):
        if "transition: all" in style.get_text():
            findings.append((path.name, f"style[{index}]", "transition: all"))

print("# Task 10 static audit")
print()
if not findings:
    print("PASS: no static findings")
else:
    for file_name, location, message in findings:
        print(f"{file_name}:{location} - {message}")
print()
print(f"Findings: {len(findings)}")
