#!/usr/bin/env node
/**
 * MEEM STORE — automated WCAG 2.1 colour-contrast audit.
 *
 * Walks every visible text node in the rendered page, resolves the effective
 * background (nearest ancestor with a non-transparent colour) and reports pairs
 * below the threshold: 4.5:1 for body text, 3:1 for large/bold text.
 * Elements painted with gradients/images are skipped (their effective colour is
 * not computable from CSS) — those are reviewed visually instead.
 *
 * Usage: node scripts/ui_contrast.mjs [file1.html file2.html ...]
 * Requires playwright (dev-only): npm i playwright && npx playwright install chromium
 */
import fs from "node:fs";
import path from "node:path";
import http from "node:http";

const ROOT = path.resolve(new URL("..", import.meta.url).pathname);
const FILES = process.argv.slice(2).length ? process.argv.slice(2) : fs.readdirSync(ROOT).filter((f) => f.endsWith(".html"));
const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml", ".png": "image/png" };

const { chromium } = await import("playwright");

const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  const file = path.join(ROOT, url === "/" ? "index.html" : url);
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": MIME[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"] });

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, locale: "ar-SD" });
await ctx.route(/sentry-cdn|googletagmanager|google-analytics/, (r) => r.abort());
const page = await ctx.newPage();

let violations = [];
for (const file of FILES) {
  await page.goto(`${base}/${file}`, { waitUntil: "load", timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(600);
  if (/login\.html$/.test(page.url()) && !file.startsWith("login")) continue; // auth-guarded page
  const found = await page.evaluate(() => {
    // getComputedStyle serialises modern colour syntax (oklab/oklch, produced by
    // color-mix() and relative colours) instead of rgb(). The plain number parser
    // used to read those as if they were rgb triplets in 0..255 and report a
    // bogus 1.44:1 on text that is plainly readable — see docs/FINAL_REPORT.md,
    // round 2026-10-14 (c). Convert properly instead.
    const oklabToRgb = (L, A, B, alpha) => {
      const l_ = L + 0.3963377774 * A + 0.2158037573 * B;
      const m_ = L - 0.1055613458 * A - 0.0638541728 * B;
      const s_ = L - 0.0894841775 * A - 1.2914855480 * B;
      const l = l_ ** 3, m = m_ ** 3, s = s_ ** 3;
      const lin = [
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
      ];
      const srgb = (v) => Math.round(Math.min(1, Math.max(0, v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055)) * 255);
      return [...lin.map(srgb), alpha];
    };
    const parse = (c) => {
      if (typeof c !== "string") return [];
      const modern = c.startsWith("oklab(") || c.startsWith("oklch(");
      if (modern) {
        const n = (c.match(/-?[\d.]+(?:e-?\d+)?/g) || []).map(Number);
        const alpha = c.includes("/") ? (n[3] === undefined ? 1 : n[3]) : 1;
        if (c.startsWith("oklch(")) {
          const h = ((n[2] || 0) * Math.PI) / 180;
          return oklabToRgb(n[0] || 0, (n[1] || 0) * Math.cos(h), (n[1] || 0) * Math.sin(h), alpha);
        }
        return oklabToRgb(n[0] || 0, n[1] || 0, n[2] || 0, alpha);
      }
      return (c.match(/[\d.]+/g) || []).map(Number);
    };
    const lum = ([r, g, b]) => {
      const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
    const alpha = (c) => (c.match(/rgba?\(([^)]+)\)/) ? (parse(c).length === 4 ? parse(c)[3] : 1) : 1);

    function effectiveBg(el) {
      let node = el;
      while (node && node !== document.documentElement) {
        const cs = getComputedStyle(node);
        if (cs.backgroundImage && cs.backgroundImage !== "none") return null; // gradient/photo → not computable
        const bg = cs.backgroundColor;
        if (bg && bg !== "transparent" && alpha(bg) > 0.55) return parse(bg).slice(0, 3);
        node = node.parentElement;
      }
      return parse(getComputedStyle(document.body).backgroundColor).slice(0, 3);
    }

    const out = [];
    document.querySelectorAll("body *").forEach((el) => {
      const text = Array.from(el.childNodes).filter((n) => n.nodeType === 3 && n.textContent.trim().length > 1);
      if (!text.length) return;
      const cs = getComputedStyle(el);
      if (cs.visibility === "hidden" || cs.display === "none" || Number(cs.opacity) < 0.5) return;
      if (el.closest(".mm-reveal:not(.is-visible)")) return;
      const rect = el.getBoundingClientRect();
      if (rect.width < 4 || rect.height < 4) return;
      const bg = effectiveBg(el);
      if (!bg) return;
      const fgRaw = parse(cs.color);
      const fgAlpha = fgRaw.length === 4 ? fgRaw[3] : 1;
      // semi-transparent text: composite it over the background before measuring
      const fg = fgAlpha < 1
        ? fgRaw.slice(0, 3).map((v, i) => v * fgAlpha + bg[i] * (1 - fgAlpha))
        : fgRaw.slice(0, 3);
      const size = parseFloat(cs.fontSize);
      const weight = Number(cs.fontWeight) || 400;
      const large = size >= 24 || (size >= 18.66 && weight >= 700);
      const need = large ? 3 : 4.5;
      const value = ratio(fg, bg);
      if (value < need) {
        out.push({
          text: el.textContent.trim().slice(0, 32),
          cls: (el.className || el.tagName).toString().slice(0, 40),
          ratio: Math.round(value * 100) / 100, need, size, weight
        });
      }
    });
    return out;
  });
  if (found.length) violations.push({ file, found });
}

await browser.close();
server.close();

if (violations.length) {
  console.log(`✖ contrast violations on ${violations.length} page(s):`);
  violations.forEach(({ file, found }) => {
    console.log(`  ${file}`);
    found.slice(0, 6).forEach((v) => console.log(`    ${v.ratio}:1 (need ${v.need}) · ${v.size}px/${v.weight} · ${v.cls} · "${v.text}"`));
    if (found.length > 6) console.log(`    … +${found.length - 6} more`);
  });
  process.exit(1);
}
console.log(`✔ contrast audit passed on ${FILES.length} page(s)`);
