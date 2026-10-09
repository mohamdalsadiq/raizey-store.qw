#!/usr/bin/env node
/**
 * RAIZEY STORE — automated WCAG 2.1 colour-contrast audit.
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
    const parse = (c) => (c.match(/[\d.]+/g) || []).map(Number);
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
      if (el.closest(".rz-reveal:not(.is-visible)")) return;
      const rect = el.getBoundingClientRect();
      if (rect.width < 4 || rect.height < 4) return;
      const fg = parse(cs.color).slice(0, 3);
      const bg = effectiveBg(el);
      if (!bg) return;
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
