// CORS resolver checks for the MEEM Edge Functions (shared module).
// Runs on plain Node (type-stripping) — no browser, no Deno.
import {
  buildCorsHeaders,
  DEFAULT_PREVIEW_ORIGIN_REGEX,
  configuredOrigins,
  isPreviewOrigin,
  resolveAllowedOrigin,
} from "../supabase/functions/_shared/cors.ts";

const PROD = "https://raizey-store-qw.vercel.app";
const PROD_TEXT = "https://meem.example.com";
let pass = 0;
let fail = 0;

function ok(name, cond, extra = "") {
  if (cond) { pass += 1; } else { fail += 1; console.error(`FAIL: ${name}${extra ? " — " + extra : ""}`); }
}

function resolve(requestOrigin, configured = "", previewRegex = DEFAULT_PREVIEW_ORIGIN_REGEX, productionOrigin = PROD) {
  return resolveAllowedOrigin({ requestOrigin, configured, previewRegex, productionOrigin });
}

// 1) production origin is echoed back
ok("production echoed", resolve(PROD) === PROD, resolve(PROD));
// 2) project preview (single subdomain label) allowed
ok("preview subdomain allowed", resolve("https://raizey-store-qw-git-meem-team.vercel.app") === "https://raizey-store-qw-git-meem-team.vercel.app");
// 3) explicit configured origin allowed, and MEEM_PUBLIC_ORIGIN list wins
ok("configured custom origin allowed", resolve(PROD_TEXT, PROD_TEXT) === PROD_TEXT);
ok("configured list", configuredOrigins("a, b ,c").join("|") === "a|b|c");
// 4) look-alikes rejected -> fall back to production
for (const bad of [
  "https://evil.example.com",
  "https://raizey-store-qw.vercel.app.evil.com",
  "https://evil.raizey-store-qw.vercel.app",
  "http://raizey-store-qw.vercel.app",
  "https://raizey-store-qw-x.vercel.app/evil",
  "https://raizey-store-qw-x.vercel.app:8443",
  "https://notraizey-store-qw-x.vercel.app",
  "null",
  "",
]) {
  ok(`reject ${bad || "<empty>"}`, resolve(bad) === PROD, resolve(bad));
}
// 5) "*" configured must NOT open the door
ok('"*" ignored', resolve("https://anything.example.com", "*") === PROD);
ok('"*" list empty', configuredOrigins("*").length === 0);
// 6) malformed preview regex fails closed
ok("bad regex fails closed", resolve("https://raizey-store-qw-x.vercel.app", "", "([") === PROD);
ok("isPreviewOrigin bad regex", isPreviewOrigin(PROD, "([") === false);
// 7) empty request origin -> production
ok("no origin -> production", resolve("") === PROD);
// 8) custom production origin used as fallback
ok("custom production fallback", resolve("https://evil.test", "", "", PROD_TEXT) === PROD_TEXT);
// 9) headers contract
const h = buildCorsHeaders("https://x.test");
ok("header origin", h["Access-Control-Allow-Origin"] === "https://x.test");
ok("header vary", h["Vary"] === "Origin");
ok("header methods", h["Access-Control-Allow-Methods"] === "POST, OPTIONS");
ok("header no wildcard", !Object.values(h).includes("*"));
// 10) production origin itself matches the precise preview pattern (single optional label)
ok("prod matches default pattern", isPreviewOrigin(PROD, DEFAULT_PREVIEW_ORIGIN_REGEX) === true);

console.log(`cors_check: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
