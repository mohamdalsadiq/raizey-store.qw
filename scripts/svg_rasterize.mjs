#!/usr/bin/env node
/**
 * MEEM STORE — SVG → PNG rasterizer (build-time helper for brand assets).
 *
 * Used by scripts/build_brand_assets.py; not part of the shipped site.
 * Renders with resvg (Rust), which needs no browser and no system fonts:
 * every logo glyph is already converted to vector paths by the Python builder.
 *
 * Install the one build-time dependency (kept out of package.json on purpose —
 * the site ships static and must stay dependency-free):
 *     npm i --no-save @resvg/resvg-js
 *
 * Usage:
 *     node scripts/svg_rasterize.mjs <in.svg> <out.png> <width> [--height N] [--bg '#061A5C']
 */
import fs from "node:fs";
import { Resvg } from "@resvg/resvg-js";

const [input, output, widthArg, ...rest] = process.argv.slice(2);
if (!input || !output || !widthArg) {
  console.error("usage: node scripts/svg_rasterize.mjs <in.svg> <out.png> <width> [--height N] [--bg #RRGGBB]");
  process.exit(2);
}
const getFlag = (name) => {
  const i = rest.indexOf(name);
  return i === -1 ? null : rest[i + 1];
};
const height = getFlag("--height");
const bg = getFlag("--bg");

const svg = fs.readFileSync(input, "utf8");
const fitTo = height
  ? { mode: "width", value: Number(widthArg) } // width wins; height kept for square/OG boxes
  : { mode: "width", value: Number(widthArg) };

const resvg = new Resvg(svg, {
  fitTo,
  background: bg || undefined,
  font: { loadSystemFonts: false, defaultFontFamily: "sans-serif" },
});
const png = resvg.render().asPng();
fs.writeFileSync(output, png);
console.log(`rasterized ${output} (${resvg.render().width}px)`);
