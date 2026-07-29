---
name: Static HTML sites in Vite artifact
description: How to correctly host a multi-page static HTML site inside a react-vite artifact without Vite breaking inline scripts.
---

# Static HTML in Vite — put files in public/

## Rule
Place all HTML pages and their assets in `artifacts/<slug>/public/` so Vite serves them as raw static files without transformation. The root `index.html` (Vite entry) should do a JS redirect to `/index.html`.

**Why:** Vite processes HTML files at the project root — it transforms `<script>` tags, inlines modules, and can mangle template literals (`${...}`). For a vanilla JS static site this breaks inline scripts and CDN-loaded libraries.

**How to apply:**
- Copy all `.html` pages → `artifacts/<slug>/public/`
- Copy all `assets/` → `artifacts/<slug>/public/assets/`
- Root `artifacts/<slug>/index.html` = thin redirect: `window.location.replace(... + '/index.html')`
- `vite.config.ts`: `publicDir: path.resolve(import.meta.dirname, 'public')` (default, no change needed)
- No `rollupOptions.input` MPA config needed for dev; add it only if production build matters
