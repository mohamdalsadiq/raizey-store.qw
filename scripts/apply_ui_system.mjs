#!/usr/bin/env node
/**
 * RAIZEY STORE — apply the unified UI system to every page.
 *
 * Idempotent pass that, for each *.html:
 *   1. migrates the legacy brand hexes to the Paper & Ember palette,
 *   2. normalises the font stack (Tajawal + JetBrains Mono — Arabic-first),
 *   3. removes leftover Font Awesome links,
 *   4. injects the theme bootstrap, assets/css/raizey.css and assets/js/raizey-ui.js,
 *   5. adds <meta name="theme-color">, a skip link and (storefront only) the mobile bottom nav.
 *
 * Run:  node scripts/apply_ui_system.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { ROOT } from "./lib_icons.mjs";

const FONT_URL = "https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700;800;900&family=JetBrains+Mono:wght@500;700&display=swap";
const SPRITE = "assets/icons/lucide-sprite.svg";

// Brand palette migration — long-form hexes only, so nothing else is touched.
const HEX = [
  [/#ff6a1a/gi, "#FF6500"],
  [/#ff6f1f/gi, "#FF6500"],
  [/#e85d00/gi, "#C24E00"],
  [/#f5f1ea/gi, "#F8EBDD"],
  [/#ede6d9/gi, "#E8D6C6"],
  [/#1a1d29/gi, "#17100C"],
  [/#e8e1d6/gi, "#E8D6C6"],
  [/#7a7468/gi, "#70645C"],
  [/#5c574d/gi, "#4A3B32"],
  [/#c98a1f/gi, "#A85B00"],
  [/#a16207/gi, "#A85B00"],
  [/#e5484d/gi, "#B3261E"],
  [/#ef4444/gi, "#B3261E"],
  [/#a52e33/gi, "#B3261E"],
  [/#16a34a/gi, "#16794F"],
  [/#15803d/gi, "#16794F"],
  [/#22c55e/gi, "#16794F"],
  [/#20222d/gi, "#211A16"],
  // off-brand cool tones are removed: the identity is paper + orange only
  [/#3b82f6/gi, "#FF6500"],
  [/#2563eb/gi, "#FF6500"],
  [/#6366f1/gi, "#FF6500"],
  [/#8b5cf6/gi, "#A94000"],
  [/#7c3aed/gi, "#A94000"]
];

const RGB = [
  [/rgba\(\s*59\s*,\s*130\s*,\s*246/g, "rgba(255,101,0"],
  [/rgba\(\s*37\s*,\s*99\s*,\s*235/g, "rgba(255,101,0"],
  [/rgba\(\s*99\s*,\s*102\s*,\s*241/g, "rgba(255,101,0"],
  [/rgba\(\s*239\s*,\s*68\s*,\s*68/g, "rgba(179,38,30"],
  [/rgba\(\s*229\s*,\s*72\s*,\s*77/g, "rgba(179,38,30"],
  [/rgba\(\s*21\s*,\s*128\s*,\s*61/g, "rgba(22,121,79"],
  [/rgba\(\s*22\s*,\s*197\s*,\s*94/g, "rgba(22,121,79"],
  [/rgba\(\s*234\s*,\s*179\s*,\s*8/g, "rgba(168,91,0"],
  [/rgba\(\s*26\s*,\s*29\s*,\s*41/g, "rgba(23,16,12"]
];
const BOTTOM_NAV_PAGES = new Set([
  "index.html", "search.html", "cart.html", "wallet.html", "my-orders.html", "account.html", "category.html", "product.html"
]);

const NAV_ITEMS = [
  { href: "index.html", icon: "house", label: "الرئيسية" },
  { href: "cart.html", icon: "shopping-cart", label: "السلة" },
  { href: "my-orders.html", icon: "receipt-text", label: "طلباتي" },
  { href: "wallet.html", icon: "wallet", label: "المحفظة" },
  { href: "account.html", icon: "user", label: "حسابي" }
];

const THEME_BOOT =
  '<script>/* RAZIEY theme bootstrap: applies the saved theme before first paint */' +
  "try{var t=localStorage.getItem('raizey-theme');if(t==='dark'||t==='light')document.documentElement.setAttribute('data-theme',t);}catch(e){}</script>";

function bottomNav(activeFile) {
  const items = NAV_ITEMS.map((item) => {
    const active = item.href === activeFile;
    return `  <a href="${item.href}"${active ? ' class="is-active" aria-current="page"' : ""}>` +
      `<svg class="rz-i" aria-hidden="true"><use href="${SPRITE}#i-${item.icon}"></use></svg><span>${item.label}</span></a>`;
  }).join("\n");
  return `<nav class="rz-bottom-nav" aria-label="التنقل السريع">\n${items}\n</nav>`;
}

let changed = 0;
const report = [];

const cssFiles = fs.readdirSync(path.join(ROOT, "assets/css")).filter((f) => f.endsWith(".css") && f !== "raizey.css").map((f) => "assets/css/" + f);
for (const file of [...fs.readdirSync(ROOT).filter((f) => f.endsWith(".html")).sort(), ...cssFiles]) {
  const full = path.join(ROOT, file);
  let html = fs.readFileSync(full, "utf8");
  const before = html;
  const notes = [];

  // 1. palette migration (inline <style> blocks, JS colour arrays and legacy stylesheets)
  for (const [pattern, replacement] of HEX) {
    pattern.lastIndex = 0;
    if (pattern.test(html)) { html = html.replace(pattern, replacement); notes.push("palette"); }
  }
  for (const [pattern, replacement] of RGB) {
    pattern.lastIndex = 0;
    if (pattern.test(html)) { html = html.replace(pattern, replacement); notes.push("palette-rgb"); }
  }

  // 2. one canonical font request, with gstatic preconnect
  html = html.replace(/^.*fonts\.googleapis\.com\/css2[^>]*>\s*$/gim, "");
  html = html.replace(/^.*<link[^>]*rel="preconnect"[^>]*fonts\.googleapis\.com[^>]*>\s*$/gim, "");
  html = html.replace(/^.*<link[^>]*rel="preconnect"[^>]*fonts\.gstatic\.com[^>]*>\s*$/gim, "");

  // 3. drop any leftover Font Awesome stylesheet
  html = html.replace(/^.*font-awesome[^\n]*\n/gim, "");

  // 4. Head wiring — always rebuilt, so the pass stays idempotent.
  //    Order matters: legacy sheets and inline <style> first, then the system sheet,
  //    then the behaviour layer; the theme bootstrap runs before first paint.
  html = html.replace(/^.*<!-- RAIZEY UI system.*$/gim, "");
  html = html.replace(/^.*<link[^>]*assets\/css\/raizey\.css[^>]*>.*$/gim, "");
  html = html.replace(/^.*<script[^>]*assets\/js\/raizey-ui\.js[^>]*><\/script>.*$/gim, "");
  html = html.replace(/^.*<link[^>]*fonts\.googleapis\.com[^>]*>.*$/gim, "");
  html = html.replace(/^.*<link[^>]*fonts\.gstatic\.com[^>]*>.*$/gim, "");
  html = html.replace(/^.*RAZIEY theme bootstrap[^\n]*$/gim, "");

  const headBlock =
    `${THEME_BOOT}\n` +
    `<link rel="preconnect" href="https://fonts.googleapis.com">\n` +
    `<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n` +
    `<link href="${FONT_URL}" rel="stylesheet">\n`;
  const systemBlock =
    `<!-- RAIZEY UI system (tokens + components + icons + behaviour) -->\n` +
    `<link rel="stylesheet" href="assets/css/raizey.css">\n` +
    `<script src="assets/js/raizey-ui.js"></script>\n`;
  html = html.replace(/<head([^>]*)>/i, (m, attrs) => `${m}\n${headBlock}`);
  html = html.replace(/<\/head>/i, `${systemBlock}</head>`);
  notes.push("head-wiring");

  // 5a. theme-color for mobile browser chrome
  if (!html.includes('name="theme-color"')) {
    html = html.replace(/<head([^>]*)>/i, (m) => `${m}\n<meta name="theme-color" content="#FFF8F0" media="(prefers-color-scheme: light)">\n<meta name="theme-color" content="#17100C" media="(prefers-color-scheme: dark)">`);
    notes.push("theme-color");
  }

  // 5b. skip link + focus target for keyboard users
  if (!html.includes("rz-skip-link")) {
    const target = html.match(/<(main|section|div)\b[^>]*class="[^"]*(?:container|admin-page|page-wrap|orders-page)[^"]*"[^>]*>/i);
    if (target) {
      let tag = target[0];
      if (!/\bid="/.test(tag)) tag = tag.replace(/>$/, ' id="mainContent" tabindex="-1">');
      html = html.replace(target[0], tag);
      html = html.replace(/<body([^>]*)>/i, (m) => `${m}\n<a class="rz-skip-link" href="#mainContent">تخطَّ إلى المحتوى</a>`);
      notes.push("skip-link");
    }
  }

  // 5c. mobile bottom navigation for storefront pages
  if (BOTTOM_NAV_PAGES.has(file)) {
    html = html.replace(/<nav class="rz-bottom-nav"[\s\S]*?<\/nav>\s*/g, "");
    html = html.replace(/<\/body>/i, `${bottomNav(file)}\n</body>`);
    if (!/<body[^>]*class="[^"]*rz-has-bottom-nav/.test(html)) {
      html = html.replace(/<body([^>]*)>/i, (m, attrs) => attrs.includes("class=")
        ? m.replace(/class="([^"]*)"/, (mm, cls) => `class="${cls} rz-has-bottom-nav"`)
        : `<body class="rz-has-bottom-nav"${attrs}>`);
    }
    notes.push("bottom-nav");
  }

  if (html !== before) {
    fs.writeFileSync(full, html);
    changed++;
    report.push(`${file}: ${[...new Set(notes)].join(", ")}`);
  }
}

console.log(`✔ UI system applied to ${changed} pages`);
report.forEach((line) => console.log("   " + line));
