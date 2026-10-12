#!/usr/bin/env node
/**
 * MEEM STORE — banner carousel check (real headless browser).
 *
 * Proves on the running site that:
 *   · get_banners_public() rows are rendered (or the default slide shows)
 *   · every <img> actually decoded (naturalWidth > 0) and has alt + width/height
 *   · the desktop box is 8:3 and the mobile box is 3:4, image fully visible
 *   · dots/arrows show on desktop, are hidden on mobile
 *   · no console error, no failed request, no horizontal overflow
 *   · prefers-reduced-motion stops the autoplay
 *
 * Usage: node scripts/banners_check.mjs   (BASE_URL, SHOTS_DIR env optional)
 */
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve(new URL("..", import.meta.url).pathname);
const BASE = process.env.BASE_URL || "http://127.0.0.1:3000";
const SHOTS = process.env.SHOTS_DIR || path.join(ROOT, "ui-shots", "banners");
fs.mkdirSync(SHOTS, { recursive: true });

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error("✖ playwright is not installed: npm i playwright && npx playwright install chromium");
  process.exit(2);
}

const VIEWPORTS = [
  { name: "desktop-1440", width: 1440, height: 900, mobile: false },
  { name: "mobile-390", width: 390, height: 844, mobile: true },
];

const problems = [];
const facts = [];

const LAUNCH = { args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu", "--disable-background-networking"] };
const browser = await chromium.launch(LAUNCH);

async function open(vp, reduced = false) {
  const ctx = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: 1,
    reducedMotion: reduced ? "reduce" : "no-preference",
    locale: "ar",
  });
  const page = await ctx.newPage();
  const consoleErrors = [];
  const failed = [];
  page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
  page.on("pageerror", (e) => consoleErrors.push("pageerror: " + e.message));
  page.on("requestfailed", (r) => failed.push(r.url() + " :: " + (r.failure()?.errorText || "")));
  page.on("response", (r) => { if (r.status() >= 400) failed.push(r.url() + " :: HTTP " + r.status()); });
  await page.goto(`${BASE}/index.html`, { waitUntil: "load" });
  await page.waitForFunction('document.getElementById("mmHeroSwiper") && document.getElementById("mmHeroSwiper").dataset.ready === "1"', null, { timeout: 20000 });
  await page.waitForTimeout(900);
  return { ctx, page, consoleErrors, failed };
}

for (const vp of VIEWPORTS) {
  const { ctx, page, consoleErrors, failed } = await open(vp);

  const info = await page.evaluate(() => {
    const hero = document.getElementById("mmHeroSwiper");
    const box = hero.getBoundingClientRect();
    const slides = [...hero.querySelectorAll(".mm-slide")];
    const imgs = [...hero.querySelectorAll("img")].map((i) => ({
      src: i.currentSrc || i.src,
      alt: i.getAttribute("alt"),
      w: i.getAttribute("width"),
      h: i.getAttribute("height"),
      natural: i.naturalWidth,
      visible: i.getBoundingClientRect().width > 0,
    }));
    const visibleSlide = slides.find((s) => {
      const r = s.getBoundingClientRect();
      return Math.abs(r.left - box.left) < box.width / 2;
    }) || slides[0];
    const vr = visibleSlide ? visibleSlide.getBoundingClientRect() : null;
    const dots = document.getElementById("mmHeroDots");
    const arrows = [...hero.querySelectorAll(".mm-hero-arrow")];
    const cta = visibleSlide ? visibleSlide.querySelector(".mm-slide-cta") : null;
    const links = [...hero.querySelectorAll("a[href]")].map((a) => a.getAttribute("href"));
    return {
      slides: slides.length,
      skeleton: hero.querySelectorAll(".mm-slide-skeleton").length,
      boxW: Math.round(box.width),
      boxH: Math.round(box.height),
      slideRatio: vr ? +(vr.width / vr.height).toFixed(3) : null,
      imgRatio: imgs.map((i) => i.natural),
      imgs,
      dotsHidden: dots ? dots.hasAttribute("hidden") : true,
      dotsVisible: dots ? getComputedStyle(dots).display !== "none" && !dots.hasAttribute("hidden") : false,
      arrowDisplay: arrows.map((a) => getComputedStyle(a).display),
      ctaH: cta ? Math.round(cta.getBoundingClientRect().height) : null,
      ctaBg: cta ? getComputedStyle(cta).backgroundColor : null,
      links,
      docOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      autoplay: !!(hero.swiper ? hero.swiper.autoplay && hero.swiper.autoplay.running : false),
      allowTouchMove: !!(hero.swiper && hero.swiper.allowTouchMove),
      rtl: !!(hero.swiper && hero.swiper.rtlTranslate !== undefined),
    };
  });

  const expectRatio = vp.mobile ? 0.75 : 8 / 3;
  if (Math.abs(info.slideRatio - expectRatio) > 0.02) {
    problems.push(`${vp.name}: slide ratio ${info.slideRatio} != ${expectRatio.toFixed(3)}`);
  }
  if (info.slides < 1) problems.push(`${vp.name}: no slide rendered`);
  for (const im of info.imgs) {
    if (im.natural === 0) problems.push(`${vp.name}: image did not decode ${im.src}`);
    if (!im.alt) problems.push(`${vp.name}: missing alt on ${im.src}`);
    if (!im.w || !im.h) problems.push(`${vp.name}: missing width/height on ${im.src}`);
  }
  if (vp.mobile) {
    if (info.dotsVisible) problems.push(`${vp.name}: dots should be hidden on mobile`);
    if (info.arrowDisplay.some((d) => d !== "none")) problems.push(`${vp.name}: arrows should be hidden on mobile`);
  } else {
    if (!info.dotsVisible) problems.push(`${vp.name}: dots should be visible on desktop`);
  }
  if (info.ctaH !== null && info.ctaH < 44) problems.push(`${vp.name}: CTA height ${info.ctaH} < 44`);
  if (!info.allowTouchMove) problems.push(`${vp.name}: touch dragging is disabled`);
  if (info.docOverflow > 0) problems.push(`${vp.name}: horizontal overflow ${info.docOverflow}px`);
  for (const c of consoleErrors) problems.push(`${vp.name}: console error: ${c}`);
  for (const f of failed) problems.push(`${vp.name}: failed request: ${f}`);

  // arrows are hover/focus revealed on desktop; prove that here
  if (!vp.mobile) {
    await page.hover("#mmHeroSwiper");
    await page.waitForTimeout(200);
    const shown = await page.evaluate(() =>
      [...document.querySelectorAll(".mm-hero-arrow")].map((a) => getComputedStyle(a).display));
    info.arrowDisplayOnHover = shown;
    if (shown.some((d) => d === "none")) problems.push(`${vp.name}: arrows do not appear on hover`);
    await page.screenshot({ path: path.join(SHOTS, `${vp.name}-hover.png`), fullPage: false });
    await page.mouse.move(0, 0);
  }

  await page.screenshot({ path: path.join(SHOTS, `${vp.name}.png`), fullPage: false });
  const hero = await page.$("#mmHeroSwiper");
  if (hero) await hero.screenshot({ path: path.join(SHOTS, `${vp.name}-hero.png`) });

  // advance one slide the way a user would (dot click) and capture again
  if (info.dotsVisible) {
    const dot = await page.$(".mm-hero-dots .swiper-pagination-bullet:nth-child(2)");
    if (dot) await dot.click();
  } else {
    // mobile: no dots, advance through the slider API like a swipe would
    await page.evaluate(() => document.getElementById("mmHeroSwiper").swiper.slideNext());
  }
  await page.waitForTimeout(900);
  const h2 = await page.$("#mmHeroSwiper");
  if (h2) await h2.screenshot({ path: path.join(SHOTS, `${vp.name}-hero-slide2.png`) });
  const active = await page.evaluate(() => {
    const sw = document.getElementById("mmHeroSwiper").swiper;
    return sw ? sw.realIndex : -1;
  });
  if (active === 0) problems.push(`${vp.name}: advancing a slide did not change the active index`);

  facts.push({ viewport: vp.name, ...info, consoleErrors: consoleErrors.length, failedRequests: failed.length });
  await ctx.close();
}

// reduced motion: autoplay must not run
{
  const vp = VIEWPORTS[0];
  const { ctx, page } = await open(vp, true);
  const running = await page.evaluate(() => {
    const hero = document.getElementById("mmHeroSwiper");
    return !!(hero.swiper && hero.swiper.autoplay && hero.swiper.autoplay.running);
  });
  if (running) problems.push("reduced-motion: autoplay is running");
  await ctx.close();
  facts.push({ viewport: "reduced-motion", autoplay: running });
}

await browser.close();

fs.writeFileSync(path.join(SHOTS, "report.json"), JSON.stringify({ facts, problems }, null, 2));
console.log(JSON.stringify({ facts, problems }, null, 2));
if (problems.length) {
  console.error(`\n✖ banner check failed with ${problems.length} problem(s)`);
  process.exit(1);
}
console.log("\n✔ banner check passed");
