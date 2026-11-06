import assert from 'node:assert/strict';
import {handleCatalog,renderCatalog,readPublic,ORIGIN} from '../api/catalog.mjs';
import handler from '../api/catalog.mjs';
const id='5ed73edb-86df-4acf-afb0-fd01fb3a827e';
const row={id,name:'منتج <آمن>',description:'وصف & تفاصيل',image_url:'javascript:alert(1)'};
const read = async table => table==='products'?[row]:[{id,name:'قسم'}];
const req = (q,method='GET')=>new Request(ORIGIN+'/api/catalog?'+q,{method,headers:{Cookie:'private=test',Authorization:'Bearer visitor-must-never-be-forwarded'}});
const result=await handleCatalog(req('kind=product&id='+id),read);
assert.equal(result.status,200);
const html=await result.text();
assert.match(html,/<h1>منتج &lt;آمن&gt;<\/h1>/);
assert.match(html,/rel="canonical" href="https:\/\/raizey-store-qw.vercel.app\/product.html\?id=/);
assert.ok(!html.includes('javascript:alert'));
for (const match of html.matchAll(/<script type="application\/ld\+json">(.*?)<\/script>/g)) JSON.parse(match[1]);
assert.equal((await handleCatalog(req('kind=product&id=bad'),read)).status,404);
assert.equal((await handleCatalog(req('kind=product&id='+id),async()=>[])).status,404);
assert.equal((await handleCatalog(req('kind=product&id='+id),async()=>{throw Error('offline')})).status,503);
assert.equal((await handleCatalog(req('kind=product&id='+id,'POST'),read)).status,405);
assert.equal(await (await handleCatalog(req('kind=product&id='+id,'HEAD'),read)).text(),'');
const sitemap=await (await handleCatalog(req('kind=sitemap'),read)).text();
assert.match(sitemap,/<urlset xmlns=/); assert.ok(!sitemap.includes('wallet')); assert.ok(!sitemap.includes('lastmod'));
await readPublic('products',{select:'id'},async (url,options)=>{
  assert.equal(new URL(url).hostname,'rglbfizqolrenwfsndyv.supabase.co');
  assert.equal(options.credentials,'omit'); assert.ok(!options.headers.Cookie);
  assert.ok(!JSON.stringify(options).includes('visitor-must-never-be-forwarded'));
  return Response.json([]);
});
assert.ok(!renderCatalog('product',{...row,name:'</script><img onerror=alert(1)>'}).includes('</script><img onerror'));
const originalFetch=globalThis.fetch;
try {
  globalThis.fetch=async()=>Response.json([row]);
  assert.equal((await handler.fetch(req('kind=sitemap'),{waitUntil:()=>{}})).status,200,'platform context must not replace the public reader');
} finally {globalThis.fetch=originalFetch;}
console.log('Catalog SEO: raw HTML, XSS, canonical, JSON-LD, 404/503, HEAD, sitemap and anonymous cache isolation passed.');
