#!/usr/bin/env node
/**
 * MEEM STORE — unit tests for assets/js/category-icons.js
 *   · normalization (hamza / taa-marbuta / tashkeel / tatweel)
 *   · every documented keyword maps to its stable category key
 *   · unknown names fall back to layout-grid (never undefined)
 *   · every rule key + preset exists in the sprite
 *   · resolve() honours custom / preset / auto, and degrades to auto
 */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const ROOT = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(import.meta.url);
const CI = require(path.join(ROOT, "assets/js/category-icons.js"));

let pass = 0, fail = 0;
const failures = [];
function eq(actual, expected, label) {
  if (actual === expected) { pass++; return; }
  fail++; failures.push(`${label}: got ${JSON.stringify(actual)} expected ${JSON.stringify(expected)}`);
}

// ── 1. normalization ────────────────────────────────────────────────────────
eq(CI.normalize("ألعاب"), "العاب", "normalize alef");
eq(CI.normalize("إشتراكات"), "اشتراكات", "normalize hamza-under");
eq(CI.normalize("بطاقة"), "بطاقه", "normalize taa-marbuta");
eq(CI.normalize("جيمزُ"), "جيمز", "normalize damma");
eq(CI.normalize("فـيـفـا"), "فيفا", "normalize tatweel");
eq(CI.normalize("Free-Fire!"), "free fire", "normalize latin punctuation");

// ── 2. documented keyword → icon ────────────────────────────────────────────
const TABLE = [
  ["ألعاب", "gamepad-2"], ["games", "gamepad-2"],
  ["ببجي", "crosshair"], ["pubg", "crosshair"],
  ["فري فاير", "flame"], ["free fire", "flame"],
  ["كول أوف ديوتي", "swords"], ["call of duty", "swords"],
  ["فورتنايت", "rocket"], ["fortnite", "rocket"],
  ["بطاقات", "gift"], ["كروت", "gift"], ["gift", "gift"],
  ["جوجل بلاي", "circle-play"], ["google play", "circle-play"],
  ["ايتونز", "smartphone"], ["apple", "smartphone"],
  ["اشتراكات", "clapperboard"], ["نتفلكس", "clapperboard"],
  ["ستيم", "monitor"], ["steam", "monitor"],
  ["بلايستيشن", "gamepad-2"], ["xbox", "gamepad-2"],
  ["ديسكورد", "message-circle"], ["discord", "message-circle"],
  ["موسيقى", "music"], ["سبوتيفاي", "music"],
  ["جواهر", "gem"], ["جيمز", "gem"], ["uc", "gem"], ["diamonds", "gem"],
  ["محفظة", "wallet"],
  ["AI", "brain"], ["ادوات الذكاء الاصطناعي", "brain"], ["اشتراكات ChatGPT", "brain"],
  ["توثيقات", "badge-check"], ["توثيق حسابات", "badge-check"],
  ["بطاقات فيزا", "credit-card"], ["Visa", "credit-card"], ["credit card", "credit-card"],
  ["بطاقة هوية", "id-card"],
  ["تطبيقات", "app-window"], ["apps", "app-window"],
  ["خدمات", "sparkles"],
  ["شحن رصيد", "wallet"],
  ["عملات ذهبية", "gem"],
  ["", "layout-grid"], ["قسم عشوائي غير معروف", "layout-grid"]
];
for (const [name, expected] of TABLE) eq(CI.suggest(name), expected, `suggest(${JSON.stringify(name)})`);

// ── 3. preset / rule integrity vs the sprite ────────────────────────────────
const sprite = fs.readFileSync(path.join(ROOT, "assets/icons/category-sprite.svg"), "utf8");
const spriteIds = new Set([...sprite.matchAll(/<symbol id="i-([a-z0-9-]+)"/g)].map((m) => m[1]));

const srcText = fs.readFileSync(path.join(ROOT, "assets/js/category-icons.js"), "utf8");
const ruleKeys = [...srcText.matchAll(/,\s*'([a-z0-9-]+)'\]/g)].map((m) => m[1]);
const missingRule = [...new Set(ruleKeys)].filter((k) => !spriteIds.has(k));
eq(missingRule.length, 0, "rule keys exist in sprite: " + missingRule.join(","));
const missingPreset = CI.PRESETS.filter((k) => !spriteIds.has(k));
eq(missingPreset.length, 0, "presets exist in sprite: " + missingPreset.join(","));
eq(CI.PRESETS.length >= 60 && CI.PRESETS.length <= 90, true, `preset count 60..80-ish (${CI.PRESETS.length})`);

// ── 4. resolve() priority ───────────────────────────────────────────────────
eq(CI.resolve({ icon_mode: "preset", icon_key: "rocket", name: "ألعاب" }).key, "rocket", "resolve preset wins");
eq(CI.resolve({ icon_mode: "preset", icon_key: "not-a-real-key", name: "ألعاب" }).key, "gamepad-2", "resolve bad preset → auto");
eq(CI.resolve({ icon_mode: "custom", icon_image_url: "https://x/y.webp", name: "ألعاب" }).mode, "custom", "resolve custom mode");
eq(CI.resolve({ name: "ببجي" }).key, "crosshair", "resolve auto");
eq(CI.resolve({}).key, "layout-grid", "resolve empty → fallback");

// ── 5. isValidKey rejects junk ──────────────────────────────────────────────
eq(CI.isValidKey("gamepad-2"), true, "valid key");
eq(CI.isValidKey("not-real"), false, "unknown key rejected");
eq(CI.isValidKey("<script>"), false, "markup rejected");
eq(CI.matches('brain', 'AI'), true, 'search AI');
eq(CI.matches('mail', 'AI'), false, 'AI search does not match unrelated mail');
eq(CI.matches('credit-card', 'فيزا'), true, 'search Visa Arabic');
eq(CI.matches('badge-check', 'توثيق'), true, 'search verification Arabic');
eq(CI.matches('layout-grid', 'zzzz-unknown'), false, 'unknown search has no false grid match');

console.log(`category-icons: ${pass} passed, ${fail} failed`);
if (fail) { failures.forEach((f) => console.error("  ✖ " + f)); process.exit(1); }
console.log("✔ category-icons check passed");
