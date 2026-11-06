import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
const root = path.resolve(new URL('..',import.meta.url).pathname);
const accountConsent=process.env.MEEM_ACCOUNT_CONSENT_PREVIEW==='1';
if(accountConsent && process.env.VERCEL_ENV==='production') throw new Error('Account consent production release is blocked pending documented provider review.');
const out = path.join(root,'dist');
fs.rmSync(out,{recursive:true,force:true}); fs.mkdirSync(out,{recursive:true});
fs.cpSync(path.join(root,'assets'),path.join(out,'assets'),{recursive:true});
const manifest = {};
function walk(dir) { return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]); }
// Keep original URLs for old HTML and database artwork references throughout
// rollout. Immutable caching applies exclusively to the fingerprinted copies.
for (const file of walk(path.join(out,'assets')).sort((a,b)=>Number(a.endsWith('.css'))-Number(b.endsWith('.css')))) {
  if (!/\.(?:js|css|woff2|webp|png|svg)$/.test(file)) continue;
  let bytes = fs.readFileSync(file);
  if (file.endsWith('.css')) {
    const relative = path.relative(out,file);
    bytes = Buffer.from(bytes.toString().replace(/url\((['"]?)([^)'"\s]+)\1\)/g,(all,quote,target)=>{
      const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(relative),target));
      return manifest[resolved] ? `url(${quote}${path.posix.relative(path.posix.dirname(relative),manifest[resolved])}${quote})` : all;
    }));
  }
  const hash = createHash('sha256').update(bytes).digest('hex').slice(0,12);
  const relative = path.relative(out,file);
  const hashed = relative.replace(/(\.[^.]+)$/,'.'+hash+'$1');
  fs.writeFileSync(path.join(out,hashed),bytes); manifest[relative]=hashed;
}
const rewrite = html => html.replace(/((?:src|href)="|\bsrcset=")([^"\n]+)"/g, (all,prefix,value)=> {
  const changed = value.replace(/(?:\/?assets\/[^\s,?#]+)(?:\?[^\s,]*)?/g, asset => {
    const clean = asset.replace(/^\//,'').split('?')[0];
    // The carousel builds these same URLs from public DB rows. Keep them equal
    // to avoid a second download when it replaces the initial picture.
    return manifest[clean] && !clean.startsWith('assets/banners/') ? (asset.startsWith('/')?'/':'')+manifest[clean] : asset;
  });
  return prefix+changed+'"';
});
fs.mkdirSync(path.join(root,'api/templates'),{recursive:true});
const clientSource=fs.readFileSync(path.join(root,'assets/js/supabase-client.js'),'utf8');
fs.writeFileSync(path.join(root,'api/templates/public-config.json'),JSON.stringify({
  url:clientSource.match(/const SUPABASE_URL = .*?\|\| "([^"]+)"/)[1],
  key:clientSource.match(/const SUPABASE_ANON_KEY = .*?\|\| "([^"]+)"/)[1]
}));
for (const name of fs.readdirSync(root).filter(x=>x.endsWith('.html'))) {
  let source=fs.readFileSync(path.join(root,name),'utf8');
  if(accountConsent && !name.startsWith('admin')) {
    source=source.replace(/<script src="assets\/js\/receipt-consent-legacy\.js"><\/script>\s*/g,'');
    source=source.replace(/<label data-receipt-consent\b[^>]*>[\s\S]*?<\/label>/g,'<p class="mm-hint">يُفحص الإيصال آلياً وفق سياسة المعالجة المقبولة لحسابك. <a href="privacy.html">تفاصيل السياسة</a></p>');
    source=source.replace(/(<script src="assets\/js\/mfa-guard\.js"><\/script>)/,'$1\n<script src="assets/js/receipt-consent.js"></script>');
  }
  const html=rewrite(source);
  if (['product.html','category.html'].includes(name)) fs.writeFileSync(path.join(root,'api/templates',name),html);
  else fs.writeFileSync(path.join(out,name),html);
}
fs.copyFileSync(path.join(root,'robots.txt'),path.join(out,'robots.txt'));
fs.writeFileSync(path.join(out,'asset-manifest.json'),JSON.stringify(manifest));
console.log(`Public output built: ${Object.keys(manifest).length} fingerprinted assets; source reports and database files excluded.`);
