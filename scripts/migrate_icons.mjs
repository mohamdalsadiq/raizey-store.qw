#!/usr/bin/env node
/**
 * RAIZEY STORE — one-shot Font Awesome → Lucide sprite migration.
 *
 * Rewrites `<i class="fas fa-x" ...></i>` into
 *   `<svg class="rz-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-lucide-name"></use></svg>`
 * across every page and JS module, drops the Font Awesome CDN <link>, and keeps
 * layout-affecting attributes (style, id, extra classes) intact.
 *
 * Idempotent: running it twice changes nothing.
 */
import fs from "node:fs";
import path from "node:path";
import { ROOT, readMap, sourceFiles } from "./lib_icons.mjs";

const SPRITE = "assets/icons/lucide-sprite.svg";
const map = readMap();
const SKIP = new Set(["fa-spin", "fa-pulse"]);

function lucideName(token) {
  if (!/^fa-/.test(token)) return null;
  return map.icons[token] ?? map.brands[token] ?? null;
}

function convertTag(tag) {
  const m = tag.match(/^<i\b([^>]*)>$/);
  if (!m) return tag;
  const attrs = m[1];
  const classMatch = attrs.match(/\bclass="([^"]*)"/);
  if (!classMatch) return tag;
  const classes = classMatch[1].split(/\s+/).filter(Boolean);
  const iconTokens = classes.filter((c) => lucideName(c));
  if (!iconTokens.length) return tag;

  const resolved = lucideName(iconTokens[0]);
  const rest = classes.filter((c) => !iconTokens.includes(c) && !SKIP.has(c));
  const spinning = classes.some((c) => SKIP.has(c));
  const outClasses = ["rz-i", ...rest, ...(spinning ? ["rz-spin"] : [])].join(" ");

  const restAttrs = attrs
    .replace(/\bclass="[^"]*"/, "")
    .replace(/\s+/g, " ")
    .trim();

  const parts = [`class="${outClasses}"`, restAttrs, `aria-hidden="true"`].filter(Boolean);
  return `<svg ${parts.join(" ")}><use href="${SPRITE}#i-${resolved}"></use></svg>`;
}

let touched = 0;
let converted = 0;

for (const file of sourceFiles()) {
  const before = fs.readFileSync(file, "utf8");
  let after = before.replace(/<i\b[^>]*>/g, (tag) => {
    const replaced = convertTag(tag.replace(/\s+$/, ""));
    if (replaced !== tag) converted++;
    return replaced;
  });
  // Drop the Font Awesome stylesheet: the sprite above is the only icon source now.
  after = after.replace(/^\s*<!--?[^>]*font-awesome[\s\S]*?-->\s*$/gim, "");
  after = after.replace(/^\s*<link[^>]*font-awesome[^>]*>\s*$/gim, "");
  if (after !== before) {
    fs.writeFileSync(file, after);
    touched++;
  }
}

console.log(`✔ migrated ${converted} icon tags across ${touched} files`);
