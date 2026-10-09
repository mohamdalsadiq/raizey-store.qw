// Shared icon utilities for RAIZEY STORE.
// One icon library only: Lucide (stroke SVG sprite) + Simple Icons for brand marks.
import fs from "node:fs";
import path from "node:path";

export const ROOT = path.resolve(new URL("..", import.meta.url).pathname);
export const MAP_PATH = path.join(ROOT, "assets/icons/fa-to-lucide.json");
export const SPRITE_PATH = path.join(ROOT, "assets/icons/lucide-sprite.svg");
export const LUCIDE_VERSION = "1.53.0";
export const SIMPLE_ICONS_VERSION = "16.34.0";

export function readMap() {
  const raw = JSON.parse(fs.readFileSync(MAP_PATH, "utf8"));
  return { icons: raw.icons, brands: raw.brands };
}

// Files that may contain markup: storefront pages, admin pages and JS modules.
export function sourceFiles() {
  const out = [];
  for (const f of fs.readdirSync(ROOT)) {
    if (f.endsWith(".html")) out.push(path.join(ROOT, f));
  }
  const jsDir = path.join(ROOT, "assets/js");
  for (const f of fs.readdirSync(jsDir)) {
    if (f.endsWith(".js")) out.push(path.join(jsDir, f));
  }
  return out;
}

const TAG_RE = /<i\b([^>]*)\bclass="([^"]*)"([^>]*)>/g;

// Collect every Font Awesome icon token still present in markup or JS strings.
export function collectLegacyIcons(files = sourceFiles()) {
  const found = new Map(); // faName -> [files]
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    for (const m of text.matchAll(TAG_RE)) {
      const classes = m[2].split(/\s+/).filter(Boolean);
      for (const c of classes) {
        if (!/^fa-/.test(c)) continue;
        if (["fa-spin", "fa-fw", "fa-lg", "fa-2x", "fa-3x", "fa-pulse", "fa-border", "fa-flip"].includes(c)) continue;
        const list = found.get(c) || [];
        list.push(path.relative(ROOT, file));
        found.set(c, list);
      }
    }
  }
  return found;
}

// Direct `<use href="...sprite.svg#i-name">` references (icon usage without JS).
export function collectSpriteRefs(files = sourceFiles()) {
  const found = new Set();
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    for (const m of text.matchAll(/lucide-sprite\.svg#i-([a-z0-9-]+)/g)) found.add(m[1]);
  }
  return found;
}

// `data-lucide="name"` markers are supported for progressively-enhanced markup.
export function collectLucideAttrs(files = sourceFiles()) {
  const found = new Set();
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    for (const m of text.matchAll(/data-lucide="([a-z0-9-]+)"/g)) found.add(m[1]);
  }
  return found;
}

export function spriteSymbolIds() {
  if (!fs.existsSync(SPRITE_PATH)) return new Set();
  const text = fs.readFileSync(SPRITE_PATH, "utf8");
  return new Set([...text.matchAll(/<symbol id="i-([a-z0-9-]+)"/g)].map((m) => m[1]));
}

// Icons referenced by name from raizey-ui.js (theme toggle, toast tones, confirm dialog).
// Icons referenced by name (not via markup) — theme toggle / toast tones /
// confirm dialog in raizey-ui.js, plus the admin-staff.html permission rows.
export const SYSTEM_ICONS = [
  "sun", "moon", "circle-help", "check", "x",
  "circle-check", "circle-x", "triangle-alert", "info",
  "clipboard-list", "ticket", "wrench"
];
