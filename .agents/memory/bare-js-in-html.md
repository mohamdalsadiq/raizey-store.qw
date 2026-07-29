---
name: Bare JS in imported HTML (missing script tags)
description: Imported HTML from Vercel had raw JavaScript in <head> without wrapping <script> tags — a silent bug that rendered as text in browsers.
---

# Bare JS bug in imported HTML

## Rule
When porting imported HTML, grep for bare JavaScript in `<head>` (code between `<link>` and `<style>` tags with no `<script>` wrapper). Wrap with `<script>...</script>` before serving.

**Why:** The original RAIZEY STORE `index.html` had `async function checkMaintenanceMode()` appearing directly between a `<link>` tag and a `<style>` tag with no `<script>` wrapper. Browsers rendered it as visible text. Vite's HTML processing made it worse by treating `${message}` as a template expression.

**How to apply:**
```python
import re
fixed = re.sub(
    r'(\n)\n(  async function checkMaintenanceMode\(\).*?checkMaintenanceMode\(\);\n  )\n(<style>)',
    r'\1<script>\n\2</script>\n\3',
    content, flags=re.DOTALL
)
```
Run this fix on all HTML files before serving. Also check that scripts calling CDN-loaded globals (like `supabaseClient`) are placed AFTER the CDN `<script>` tags in the `<body>`.
