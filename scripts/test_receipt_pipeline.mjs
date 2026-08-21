import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../assets/js/receipt-pipeline.js', import.meta.url), 'utf8');
const context = {
  Blob,
  FileReader: class FileReaderStub {},
  Image: class ImageStub {},
  URL,
  AbortController,
  setTimeout,
  clearTimeout,
  console,
  fetch,
};
context.globalThis = context;
context.window = context;
vm.runInNewContext(source, context, { filename: 'receipt-pipeline.js' });
const pipeline = context.RaizeyReceiptPipeline;
if (!pipeline) throw new Error('pipeline_not_loaded');

const cases = [
  ['jpg accepted', new Blob([new Uint8Array(32)], { type: 'image/jpeg' }), true],
  ['png accepted', new Blob([new Uint8Array(32)], { type: 'image/png' }), true],
  ['webp accepted', new Blob([new Uint8Array(32)], { type: 'image/webp' }), true],
  ['heic rejected', new Blob([new Uint8Array(32)], { type: 'image/heic' }), false],
  ['oversized rejected', new Blob([new Uint8Array(5 * 1024 * 1024 + 1)], { type: 'image/png' }), false],
];

for (const [label, file, expected] of cases) {
  let actual = true;
  try { pipeline.validateImageFile(file); } catch (_) { actual = false; }
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, got ${actual}`);
  console.log(`PASS ${label}`);
}
