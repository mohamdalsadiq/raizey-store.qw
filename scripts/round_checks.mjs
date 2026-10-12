#!/usr/bin/env node
/**
 * MEEM STORE — round checks for this change set.
 *  A) every icon-bearing input reserves room for its icons (logical padding)
 *  B) the banner fallback renders with no broken image and no alt text
 *  C) screenshots of the hero (1440/390) and the auth fields (320/360/390/768)
 */
import fs from 'node:fs';
import path from 'node:path';
const ROOT = path.resolve(new URL('..', import.meta.url).pathname);
const BASE = process.env.BASE_URL || 'http://127.0.0.1:3000';
const SHOTS = path.join(ROOT, 'ui-shots', 'round');
fs.mkdirSync(SHOTS, { recursive: true });
const { chromium } = await import('playwright');
const problems = [];
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] });

const AUTH = ['login.html', 'register.html', 'forgot-password.html', 'reset-password.html', 'verify.html'];

for (const w of [320, 360, 390, 768]) {
  const ctx = await browser.newContext({ viewport: { width: w, height: 900 }, locale: 'ar' });
  for (const page of AUTH) {
    const p = await ctx.newPage();
    const errs = [];
    p.on('pageerror', (e) => errs.push(page + ': ' + e.message));
    await p.goto(`${BASE}/${page}`, { waitUntil: 'load' });
    await p.waitForTimeout(250);
    const res = await p.evaluate(() => {
      const out = [];
      document.querySelectorAll('.input-wrap').forEach((wrap) => {
        const input = wrap.querySelector('input, textarea');
        if (!input) return;
        const cs = getComputedStyle(input);
        const rtl = getComputedStyle(input).direction === 'rtl';
        const padStart = parseFloat(rtl ? cs.paddingRight : cs.paddingLeft);
        const padEnd = parseFloat(rtl ? cs.paddingLeft : cs.paddingRight);
        const lead = wrap.querySelector('.lead-icon');
        const trail = wrap.querySelector('.trail');
        const lr = lead ? lead.getBoundingClientRect() : null;
        const ir = input.getBoundingClientRect();
        let gap = null;
        // clearance between the icon's inner edge and where the text may start
        if (lr) gap = rtl ? lr.left - (ir.right - padStart) : (ir.left + padStart) - lr.right;
        out.push({
          id: input.id || input.name || '(anon)',
          dir: cs.direction,
          padStart, padEnd, hasLead: !!lead, hasTrail: !!trail, gap,
          placeholder: input.getAttribute('placeholder') || ''
        });
      });
      return out;
    });
    for (const f of res) {
      if (f.hasLead && f.padStart < 41) problems.push(`${page}@${w} #${f.id}: padding-inline-start ${f.padStart}px < 41`);
      if (f.hasTrail && f.padEnd < 41) problems.push(`${page}@${w} #${f.id}: padding-inline-end ${f.padEnd}px < 41`);
      if (f.hasLead && f.gap !== null && f.gap < 4) problems.push(`${page}@${w} #${f.id}: icon overlaps text (gap ${f.gap.toFixed(1)}px)`);
    }
    if ([320, 360, 390, 768].includes(w) && ['login.html', 'register.html'].includes(page)) {
      const filled = await p.evaluate(() => {
        const e = document.getElementById('email'); if (e) { e.value = 'someone@example.com'; }
        const n = document.getElementById('fullName'); if (n) { n.value = 'محمد عبدالله'; }
        const r = document.getElementById('referralCode'); if (r) { r.value = 'MEEM7K2P9QMZ'; }
        const pw = document.getElementById('password'); if (pw) { pw.value = 'Sup3rSecret'; }
        return true;
      });
      await p.waitForTimeout(150);
      await p.screenshot({ path: path.join(SHOTS, `${page.replace('.html', '')}-${w}.png`), fullPage: false });
    }
    if (errs.length) problems.push(...errs);
    await p.close();
  }
  await ctx.close();
}

// ---- B) banner fallback: abort every artwork so rows 404, then check the DOM
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'ar' });
  const p = await ctx.newPage();
  let aborted = 0;
  await p.route(/banner-\d+-(desktop|mobile)(@2x)?\.webp/, (route) => { aborted++; route.abort(); });
  await p.goto(`${BASE}/index.html`, { waitUntil: 'load' });
  await p.waitForFunction('document.getElementById("mmHeroSwiper") && document.getElementById("mmHeroSwiper").dataset.ready === "1"', null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  const fb = await p.evaluate(() => {
    const slides = [...document.querySelectorAll('#mmHeroWrapper .mm-slide')];
    return {
      count: slides.length,
      allFallback: slides.length > 0 && slides.every((s) => s.classList.contains('mm-slide-fallback')),
      brokenImgs: slides.filter((s) => { const i = s.querySelector('img'); return i && i.complete && i.naturalWidth === 0; }).length,
      titles: slides.map((s) => { const t = s.querySelector('.mm-slide-title'); return t ? t.textContent : null; }),
      gradients: slides.map((s) => getComputedStyle(s).backgroundImage.includes('gradient')),
      markers: slides.map((s) => !!getComputedStyle(s, '::after').backgroundImage)
    };
  });
  if (aborted < 3) problems.push(`fallback: expected aborted artwork requests, got ${aborted}`);
  if (!fb.allFallback) problems.push(`fallback: ${fb.count} slides, not all got .mm-slide-fallback`);
  if (fb.brokenImgs) problems.push(`fallback: ${fb.brokenImgs} broken <img> left in the DOM`);
  if (fb.titles.filter(Boolean).length !== fb.count) problems.push('fallback: a live title was lost');
  if (!fb.gradients.every(Boolean)) problems.push('fallback: a slide is missing the gradient backdrop');
  if (!fb.markers.every(Boolean)) problems.push('fallback: a slide is missing the logo backdrop');
  await p.screenshot({ path: path.join(SHOTS, 'fallback-1440.png') });
  await ctx.close();
}

// ---- C) hero screenshots (all three slides)
for (const vp of [{ n: 'desktop-1440', w: 1440, h: 900, m: false }, { n: 'mobile-390', w: 390, h: 844, m: true }]) {
  const ctx = await browser.newContext({ viewport: { width: vp.w, height: vp.h }, locale: 'ar', isMobile: vp.m, hasTouch: vp.m });
  const p = await ctx.newPage();
  await p.goto(`${BASE}/index.html`, { waitUntil: 'load' });
  await p.waitForFunction('document.getElementById("mmHeroSwiper") && document.getElementById("mmHeroSwiper").dataset.ready === "1"', null, { timeout: 20000 });
  await p.waitForTimeout(900);
  const info = await p.evaluate(() => {
    const box = document.getElementById('mmHeroSwiper').getBoundingClientRect();
    const imgs = [...document.querySelectorAll('#mmHeroWrapper img')].map((i) => i.naturalWidth);
    return { w: Math.round(box.width), h: Math.round(box.height), imgs };
  });
  const ar = (info.w / info.h).toFixed(3);
  if (vp.m) {
    if (Math.abs(ar - 0.75) > 0.02) problems.push(`mobile hero aspect ${ar} != 0.750 (3:4)`);
  } else if (Math.abs(ar - 2.667) > 0.05) problems.push(`desktop hero aspect ${ar} != 2.667 (8:3)`);
  if (info.imgs.some((n) => n === 0)) problems.push(`${vp.n}: an <img> did not decode`);
  await p.screenshot({ path: path.join(SHOTS, `hero-${vp.n}.png`) });
  await ctx.close();
}

await browser.close();
if (problems.length) { console.log('PROBLEMS:'); problems.forEach((x) => console.log('  - ' + x)); process.exit(1); }
console.log('round checks passed');
