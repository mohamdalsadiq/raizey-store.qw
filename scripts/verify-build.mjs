import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
const root = path.resolve(new URL('..', import.meta.url).pathname);
const failures = [];
let checked = 0;
function walk(dir) { return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]); }
for (const file of walk(path.join(root,'assets/js')).filter(p=>p.endsWith('.js'))) {
  const result=spawnSync(process.execPath,['--check',file],{encoding:'utf8'});
  if(result.status) failures.push(result.stderr); checked++;
}
if (!process.argv.includes('--syntax-only')) {
  const config=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));
  const csp=config.headers.flatMap(g=>g.headers).find(h=>h.key==='Content-Security-Policy').value;
  if(!/(?:^|;)\s*script-src 'self'\s*;/.test(csp)) failures.push('Script CSP must permit only local files');
  for(const name of fs.readdirSync(root).filter(p=>p.endsWith('.html'))) {
    const html=fs.readFileSync(path.join(root,name),'utf8');
    for(const m of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
      if(m[2].trim()) failures.push(name+': inline JavaScript');
      const src=m[1].match(/\bsrc="([^"]+)"/i)?.[1];
      if(!src || /^https?:/.test(src) || !fs.existsSync(path.join(root,src.split(/[?#]/)[0]))) failures.push(name+': invalid script '+src);
    }
    if(/\bon(?:click|submit|change|error|load|focus|input)\s*=/i.test(html)) failures.push(name+': inline event handler');
    for(const m of html.matchAll(/<(?:link|img)\b[^>]*(?:href|src)="(assets\/[^"?#]+)"/gi))
      if(!fs.existsSync(path.join(root,m[1]))) failures.push(name+': missing asset '+m[1]);
  }
  const manifest=JSON.parse(fs.readFileSync(path.join(root,'assets/vendor/manifest.json'),'utf8'));
  for(const [name,hash] of Object.entries(manifest)) if(createHash('sha256').update(fs.readFileSync(path.join(root,'assets/vendor',name))).digest('hex')!==hash) failures.push(name+': vendor digest mismatch');
  const categorySource=JSON.parse(fs.readFileSync(path.join(root,'assets/icons/category-source.json'),'utf8'));
  if(createHash('sha256').update(fs.readFileSync(path.join(root,'assets/icons/category-sprite.svg'))).digest('hex')!==categorySource.sha256) failures.push('Category sprite digest mismatch');
}
if(failures.length) { console.error(failures.join('\n'));process.exit(1); }
console.log(`Static ${process.argv.includes('--syntax-only')?'lint':'build'} passed; ${checked} scripts parse; asset and CSP checks complete.`);
