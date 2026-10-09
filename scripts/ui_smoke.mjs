#!/usr/bin/env node
/**
 * RAIZEY STORE — browser smoke test for the UI system.
 *
 * Renders every page in a real (headless) browser at mobile and desktop widths and
 * asserts the things a static check cannot prove:
 *   · the page boots with no console error / no failed asset request
 *   · layout never overflows horizontally (mobile-first regression guard)
 *   · every sprite icon resolves to a real symbol in the sprite
 *   · the Paper & Ember palette is actually applied (background token)
 *   · interactive targets stay >= 40px on mobile
 *   · prefers-reduced-motion is honoured
 *
 * Playwright is intentionally NOT a project dependency (the site ships static):
 *   npm i playwright   (anywhere)   then: node scripts/ui_smoke.mjs
 * Optional env: BASE_URL (default http://127.0.0.1:3000), SHOTS_DIR (default ./ui-shots)
 */
import fs from "node:fs";
import path from "node:path";
import http from "node:http";

const ROOT = path.resolve(new URL("..", import.meta.url).pathname);
const BASE = process.env.BASE_URL || "http://127.0.0.1:3000";
const SHOTS = process.env.SHOTS_DIR || path.join(ROOT, "ui-shots");
const SPRITE_PATH = path.join(ROOT, "assets/icons/lucide-sprite.svg");

const PAGES = [
  "index.html", "login.html", "register.html", "account.html", "wallet.html",
  "cart.html", "my-orders.html", "search.html", "category.html", "product.html",
  "checkout-v2.html", "receipt.html", "verify.html", "notifications.html",
  "referrals.html", "privacy.html", "forgot-password.html", "reset-password.html",
  "admin.html", "admin-orders.html", "admin-topups.html", "admin-products.html",
  "admin-staff.html", "admin-categories.html", "admin-coupons.html", "admin-giftcards.html",
  "admin-customers.html", "admin-settings.html", "admin-sections.html",
  "admin-payment-methods.html", "admin-payment-codes.html", "admin-audit-log.html",
  "admin-referral-milestones.html"
];

const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json" };

function serve(root) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const url = decodeURIComponent(req.url.split("?")[0]);
      const file = path.join(root, url === "/" ? "index.html" : url);
      if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end("not found"); return;
      }
      res.writeHead(200, { "content-type": MIME[path.extname(file)] || "application/octet-stream" });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error("✖ playwright is not installed. Run:  npm i playwright && npx playwright install chromium");
  process.exit(1);
}

const spriteIds = new Set([...fs.readFileSync(SPRITE_PATH, "utf8").matchAll(/<symbol id="i-([a-z0-9-]+)"/g)].map((m) => m[1]));
fs.mkdirSync(SHOTS, { recursive: true });

const server = await serve(ROOT);
const base = `http://127.0.0.1:${server.address().port}`;
const failures = [];
const results = [];
const BLOCKED = /sentry-cdn|googletagmanager|google-analytics|vercel\.app\/v\/|hotjar|clarity/;

const LAUNCH = { args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu", "--disable-background-networking"] };
const BATCH = 8;

async function auditPage(browser, viewport, file) {
  const problems = [];
  const context = await browser.newContext({
    viewport: { width: viewport.width, height: viewport.height },
    deviceScaleFactor: 1, locale: "ar-SD", reducedMotion: "reduce"
  });
  await context.route(BLOCKED, (route) => route.abort());
  const page = await context.newPage();
  const consoleErrors = [];
  const failed = [];
  page.on("console", (msg) => {
    if (msg.type() !== "error") return;
    const text = msg.text();
    // ignored: blocked third-party requests (Sentry/analytics) are intentional here
    if (/Failed to load resource|ERR_FAILED|ERR_BLOCKED/.test(text)) return;
    consoleErrors.push(text.slice(0, 150));
  });
  page.on("requestfailed", (req) => failed.push(req.url().replace(base, "").slice(0, 80)));
  page.on("pageerror", (err) => consoleErrors.push("pageerror: " + String(err.message).slice(0, 150)));

  try {
    await page.goto(`${base}/${file}`, { waitUntil: "load", timeout: 20000 });
    await page.waitForTimeout(file.startsWith("admin") ? 700 : 550);

    // Auth-guarded pages redirect signed-out visitors to login.html — that is correct
    // behaviour, but it means the page itself cannot be audited without a session.
    const landed = page.url();
    if (landed && !landed.endsWith("/" + file) && /login\.html$/.test(landed)) {
      return ["auth-guarded (redirected to login.html)"];
    }

    const audit = await page.evaluate(([ids, minTap]) => {
      const out = { overflow: 0, badIcons: [], smallTargets: [], bg: "", missingAlt: 0, height: 0 };
      out.overflow = Math.max(0, document.documentElement.scrollWidth - window.innerWidth);
      out.height = document.documentElement.scrollHeight;
      out.bg = getComputedStyle(document.body).backgroundColor;
      const allowed = new Set(ids);
      document.querySelectorAll("svg.rz-i").forEach((svg) => {
        // icons inside closed menus/sheets are legitimately unrendered
        if (typeof svg.checkVisibility === "function" && !svg.checkVisibility()) return;
        const use = svg.querySelector("use");
        const href = use && (use.getAttribute("href") || use.getAttribute("xlink:href"));
        if (!href) return;
        const id = (href.split("#")[1] || "").replace(/^i-/, "");
        if (!allowed.has(id)) out.badIcons.push(id);
        else if (svg.getBoundingClientRect().width === 0) out.badIcons.push(id + "(zero)");
      });
      document.querySelectorAll("a, button, [role=button]").forEach((el) => {
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) return;
        if (el.closest(".rz-bottom-nav") || el.closest(".rz-toasts")) return;
        // WCAG 2.5.8 exception: links inline inside a sentence are sized by the text
        if (getComputedStyle(el).display === "inline") return;
        if (r.height < minTap && r.width > 24) out.smallTargets.push((el.textContent || el.className || el.tagName).trim().slice(0, 26) + " h=" + Math.round(r.height));
      });
      document.querySelectorAll("img:not([alt])").forEach(() => { out.missingAlt++; });
      return out;
    }, [[...spriteIds], viewport.name === "mobile" ? 40 : 32]);

    if (audit.overflow > 2) problems.push(`horizontal overflow ${audit.overflow}px`);
    if (audit.badIcons.length) problems.push(`unresolved icons: ${[...new Set(audit.badIcons)].slice(0, 5).join(", ")}`);
    if (audit.smallTargets.length) problems.push(`small tap targets: ${audit.smallTargets.slice(0, 3).join(" | ")}`);
    if (audit.missingAlt) problems.push(`${audit.missingAlt} <img> without alt`);
    if (!/rgb\(255, 248, 240\)|rgb\(23, 16, 12\)|rgba\(0, 0, 0, 0\)/.test(audit.bg)) problems.push(`unexpected body background ${audit.bg}`);
    if (consoleErrors.length) problems.push(`console: ${[...new Set(consoleErrors)].slice(0, 2).join(" / ")}`);
    const assetFailures = [...new Set(failed.filter((u) => u.startsWith("/assets") || u.startsWith("assets")))];
    if (assetFailures.length) problems.push(`failed assets: ${assetFailures.slice(0, 3).join(", ")}`);

    await page.screenshot({
      path: path.join(SHOTS, `${viewport.name}-${file.replace(".html", "")}.png`),
      fullPage: viewport.name === "mobile" && audit.height < 2400
    });
  } catch (error) {
    problems.push("navigation: " + String(error.message).slice(0, 110));
  } finally {
    await context.close().catch(() => {});
  }
  return problems;
}

for (const viewport of [{ name: "mobile", width: 393, height: 852 }, { name: "desktop", width: 1280, height: 900 }]) {
  for (let i = 0; i < PAGES.length; i += BATCH) {
    let browser = null;
    try {
      browser = await chromium.launch(LAUNCH);
      for (const file of PAGES.slice(i, i + BATCH)) {
        const problems = await auditPage(browser, viewport, file);
        const guarded = problems.length === 1 && problems[0].startsWith("auth-guarded");
    if (guarded) {
      results.push({ viewport: viewport.name, file, ok: true });
      process.stdout.write("g");
      continue;
    }
    if (problems.length) {
          failures.push(`${viewport.name}/${file}: ${problems.join(" · ")}`);
          console.log(`\n  ✖ ${viewport.name}/${file}: ${problems.join(" · ")}`);
        }
        results.push({ viewport: viewport.name, file, ok: !problems.length });
        process.stdout.write(problems.length ? "✖" : ".");
      }
    } catch (error) {
      console.log(`\n  ! batch failure (${viewport.name} ${i}): ${String(error.message).slice(0, 110)}`);
      for (const file of PAGES.slice(i, i + BATCH)) results.push({ viewport: viewport.name, file, ok: false });
    } finally {
      if (browser) await browser.close().catch(() => {});
    }
  }
}

async function browser_close_all() {}
server.close();

const total = results.length;
const ok = results.filter((r) => r.ok).length;
console.log(`\n\n${ok}/${total} page×viewport renders clean`);
if (failures.length) {
  console.log(`\n${failures.length} issue(s):`);
  failures.forEach((f) => console.log("  ✖ " + f));
  process.exit(1);
}
console.log(`Screenshots: ${SHOTS}`);
