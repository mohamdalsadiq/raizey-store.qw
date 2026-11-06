import fs from 'node:fs';
import path from 'node:path';
import {brotliCompressSync} from 'node:zlib';
import assert from 'node:assert/strict';
const root=path.resolve(new URL('../dist',import.meta.url).pathname);
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const files=new Set([...html.matchAll(/(?:src|href)="(\/?assets\/[^"?#]+)(?:[^\"]*)"/g)].map(m=>m[1].replace(/^\//,'')));
for (const file of fs.readdirSync(path.join(root,'assets/fonts')).filter(f=>f.endsWith('.woff2')&&!/\.[a-f0-9]{12}\./.test(f))) files.add('assets/fonts/'+file);
let total=brotliCompressSync(html).length;
for (const file of files) {const bytes=fs.readFileSync(path.join(root,file));total+=/\.(js|css|svg)$/.test(file)?brotliCompressSync(bytes).length:bytes.length;}
assert.ok(total<=1_000_000,`Local first-page asset budget exceeded: ${total}`);
console.log(`Local HTML-linked assets + fonts: ${total} bytes using offline Brotli for text; budget 1,000,000. Excludes remote API/artwork and is not a measured production transfer.`);
