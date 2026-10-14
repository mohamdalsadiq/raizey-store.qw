#!/usr/bin/env node
/**
 * MEEM STORE — offers page check (real headless browser).
 *
 * Verifies offers.html end to end without writing any data:
 *   · the page boots with no console error and no failed request
 *   · it shows either live discounted products or the proper empty state
 *   · the discount badge, the gold new price and the struck-through old price
 *     render correctly (checked by rendering a mock product through the page's
 *     own card builder, so no production row is touched)
 *   · no horizontal overflow at 390 or 1440
 *
 * Usage: node scripts/offers_check.mjs
 */
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve(new URL("..", import.meta.url).pathname);
const BASE = process.env.BASE_URL || "http://127.0.0.1:3000";
const SHOTS = process.env.SHOTS_DIR || path.join(ROOT, "ui-shots", "offers");
fs.mkdirSync(SHOTS, { recursive: true });

const { chromium } = await import("playwright");
const LAUNCH = { args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu", "--disable-background-networking"] };
const browser = await chromium.launch(LAUNCH);

const problems = [];
const facts = [];

for (const vp of [{ name: "desktop-1440", w: 1440, h: 900 }, { name: "mobile-390", w: 390, h: 844 }]) {
  const ctx = await browser.newContext({ viewport: { width: vp.w, height: vp.h }, locale: "ar" });
  const page = await ctx.newPage();
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
  page.on("requestfailed", (r) => errors.push("requestfailed: " + r.url()));

  await page.goto(`${BASE}/offers.html`, { waitUntil: "load" });
  // Wait for init() to settle. Neither flag alone works:
  //   · the success path only sets stateBox.hidden = true, it never clears the
  //     loading copy — a hidden node keeps its text, so "text says جارِ تحميل"
  //     stays true for the rest of the page's life;
  //   · #content starts hidden in the markup, so testing it proves nothing.
  // Settled therefore means: the state box was hidden (products rendered) or it
  // no longer carries the loading copy (empty/error copy replaced it).
  let settled = true;
  try {
    await page.waitForFunction(() => {
      const box = document.getElementById("stateBox");
      if (!box) return false;
      const stillLoading = /جارِ تحميل/.test(box.textContent || "");
      return box.hidden === true || !stillLoading;
    }, null, { timeout: 20000 });
  } catch (e) {
    settled = false;
  }
  if (!settled) {
    // Never fail with a bare timeout: the actionable signal is *why* the page
    // is still on the loading copy (blocked CDN, failed request, JS error).
    const detail = errors.length ? errors.slice(0, 3).join(" | ") : "no console error and no failed request";
    problems.push(`${vp.name}: offers.html never left the loading state — ${detail}`);
    facts.push({ viewport: vp.name, settled: false, errors });
    await ctx.close();
    continue;
  }
  await page.waitForTimeout(600);
  // Thumbnails are loading="lazy": until the browser starts fetching one,
  // currentSrc is "" and naturalWidth is 0. Force every thumbnail to decode
  // first, otherwise the naturalWidth assertion is a race, not a check.
  await page.evaluate(() => Promise.all(
    Array.from(document.querySelectorAll("#offersGrid img")).map((i) => i.decode().catch(() => {}))));

  const live = await page.evaluate(() => {
    const grid = document.getElementById("offersGrid");
    const state = document.getElementById("stateBox");
    return {
      cards: grid ? grid.querySelectorAll(".offer-card").length : 0,
      emptyShown: !!state && !state.hidden,
      stateText: state ? state.textContent.trim().slice(0, 80) : "",
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
    };
  });
  if (live.overflow > 0) problems.push(`${vp.name}: horizontal overflow ${live.overflow}px`);
  if (!live.cards && !live.emptyShown) problems.push(`${vp.name}: neither cards nor an empty state rendered`);
  if (live.cards) {
    const bad = await page.evaluate(() => {
      const out = [];
      document.querySelectorAll("#offersGrid .offer-card").forEach((c) => {
        const img = c.querySelector("img");
        if (img && !img.getAttribute("alt")) out.push("missing alt");
        if (img && img.getAttribute("src") && img.naturalWidth === 0) out.push("image not decoded: " + (img.currentSrc || img.src));
        if (!c.getAttribute("aria-label")) out.push("missing aria-label");
      });
      return out;
    });
    bad.forEach((b) => problems.push(`${vp.name}: ${b}`));
  }
  for (const e of errors) problems.push(`${vp.name}: ${e}`);

  // render a mock discounted product through the page's own builder (no data written)
  const mock = await page.evaluate(() => {
    const card = window.buildCard({ id: '00000000-0000-0000-0000-000000000000', name: 'منتج تجريبي للعرض', price_usd: 0.95, compare_at_price_usd: 1.25, image_url: '' });
    const grid = document.getElementById('offersGrid');
    document.getElementById('content').hidden = false;
    grid.insertBefore(card, grid.firstChild);
    const badge = card.querySelector('.offer-badge');
    const old = card.querySelector('.offer-old');
    const fresh = card.querySelector('.offer-new');
    return {
      badge: badge ? badge.textContent : null,
      oldText: old ? old.textContent : null,
      oldDecoration: old ? getComputedStyle(old).textDecorationLine : null,
      newColor: fresh ? getComputedStyle(fresh).color : null,
      href: card.getAttribute('href')
    };
  });
  const expectPct = Math.round((1 - 0.95 / 1.25) * 100);
  if (mock.badge !== `خصم ${expectPct}%`) problems.push(`${vp.name}: badge "${mock.badge}" != "خصم ${expectPct}%"`);
  if (!mock.oldDecoration || mock.oldDecoration.indexOf("line-through") === -1) problems.push(`${vp.name}: old price is not struck through`);
  if (mock.newColor !== "rgb(255, 212, 0)") problems.push(`${vp.name}: new price is not gold (${mock.newColor})`);
  if (!/product\.html\?id=/.test(mock.href || "")) problems.push(`${vp.name}: card does not link to product.html?id=`);

  await page.screenshot({ path: path.join(SHOTS, `${vp.name}.png`), fullPage: false });
  facts.push({ viewport: vp.name, ...live, mock, consoleErrors: errors.length });
  await ctx.close();
}

await browser.close();
fs.writeFileSync(path.join(SHOTS, "report.json"), JSON.stringify({ facts, problems }, null, 2));
console.log(JSON.stringify({ facts, problems }, null, 2));
if (problems.length) { console.error(`\n✖ offers check failed (${problems.length})`); process.exit(1); }
console.log("\n✔ offers check passed");
