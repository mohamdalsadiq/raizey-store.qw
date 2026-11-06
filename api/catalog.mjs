import fs from 'node:fs';
import path from 'node:path';

export const ORIGIN = 'https://raizey-store-qw.vercel.app';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const json = value => JSON.stringify(value).replace(/</g, '\\u003c');
function imageURL(value) {
  if (typeof value !== 'string' || !value.trim()) return '';
  try {
    const u = new URL(value, ORIGIN);
    return u.origin === ORIGIN || (u.origin === 'https://rglbfizqolrenwfsndyv.supabase.co' && u.pathname.startsWith('/storage/v1/object/public/product-images/')) ? u.href : '';
  } catch { return ''; }
}
// This is the already published anon configuration. Never use a service-role key
// or visitor headers for shared-cache HTML. The Data API still enforces RLS.
function publicConfig() {
  const source = fs.readFileSync(path.join(process.cwd(), 'assets/js/supabase-client.js'), 'utf8');
  return {url: source.match(/const SUPABASE_URL = .*?\|\| "([^"]+)"/)[1], key: source.match(/const SUPABASE_ANON_KEY = .*?\|\| "([^"]+)"/)[1]};
}
export async function readPublic(table, params, fetcher = fetch) {
  const {url, key} = publicConfig();
  const endpoint = new URL('/rest/v1/' + table, url);
  endpoint.search = new URLSearchParams(params);
  const result = await fetcher(endpoint, {headers: {apikey: key, Authorization: 'Bearer ' + key}, credentials: 'omit', signal: AbortSignal.timeout(8000)});
  if (!result.ok) throw new Error('catalog_source_unavailable');
  return result.json();
}
function headers(type, status = 200) {
  return {'Content-Type': type, 'Cache-Control': 'public, max-age=0, must-revalidate',
    'Vercel-CDN-Cache-Control': status === 200 ? 'public, s-maxage=60, stale-while-revalidate=60' : 'no-store',
    'X-Content-Type-Options': 'nosniff', ...(status !== 200 ? {'X-Robots-Tag':'noindex'} : {})};
}
async function allPublicIDs(table, read) {
  const rows = [];
  for (let offset = 0; offset < 50000; offset += 1000) {
    const page = await read(table,{select:'id',is_active:'eq.true',order:'id',limit:'1000',offset:String(offset)});
    rows.push(...page);
    if (page.length < 1000) return rows;
  }
  throw new Error('sitemap_page_limit');
}
function errorPage(status, message) {
  return new Response(`<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(message)} — MEEM STORE</title><meta name="robots" content="noindex"><link rel="stylesheet" href="/assets/css/fonts.css"><link rel="stylesheet" href="/assets/css/meem.css"><main class="catalog-public"><h1>${escape(message)}</h1><a href="/">العودة إلى المتجر</a></main></html>`, {status, headers:headers('text/html; charset=utf-8', status)});
}
function template(kind) {
  // Build writes the fingerprinted template into the function bundle.
  const built = path.join(process.cwd(), 'api/templates', kind + '.html');
  return fs.readFileSync(fs.existsSync(built) ? built : path.join(process.cwd(), kind + '.html'), 'utf8');
}
export function renderCatalog(kind, row, children = []) {
  const canonical = `${ORIGIN}/${kind}.html?id=${encodeURIComponent(row.id)}`;
  const title = `${row.name} — MEEM STORE`;
  const description = String(row.description || `تصفح ${row.name} والخدمات الرقمية المتاحة في MEEM STORE.`).slice(0, 300);
  const image = imageURL(row.image_url);
  let html = template(kind).replace(/<title>[\s\S]*?<\/title>/i, `<title>${escape(title)}</title>`)
    .replace(/<meta\b[^>]*(?:name="(?:description|twitter:title|twitter:description|twitter:image|robots)"|property="og:[^"]+")[^>]*>/gi, '')
    .replace(/<link\b[^>]*rel="canonical"[^>]*>/gi, '');
  const structured = kind === 'product' ? {'@type':'Product',name:row.name,description,...(image ? {image:[image]} : {}),url:canonical} : {'@type':'CollectionPage',name:row.name,description,url:canonical};
  // Options and exchange rates can change the actual purchase price. Do not
  // manufacture a fixed Offer/availability from the base USD display value.
  const data = {'@context':'https://schema.org','@graph':[structured,{'@type':'BreadcrumbList',itemListElement:[{'@type':'ListItem',position:1,name:'MEEM STORE',item:ORIGIN+'/'},{'@type':'ListItem',position:2,name:row.name,item:canonical}]}]};
  const meta = `<meta name="description" content="${escape(description)}"><link rel="canonical" href="${canonical}"><meta property="og:type" content="${kind === 'product' ? 'product' : 'website'}"><meta property="og:site_name" content="MEEM STORE"><meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}"><meta property="og:url" content="${canonical}"><meta property="og:image" content="${escape(image || ORIGIN+'/assets/img/meem-og.png')}"><meta name="twitter:title" content="${escape(title)}"><meta name="twitter:description" content="${escape(description)}"><meta name="twitter:image" content="${escape(image || ORIGIN+'/assets/img/meem-og.png')}"><script type="application/ld+json">${json(data)}</script>`;
  const list = children.length ? `<h2>المنتجات المتاحة</h2><ul>${children.map(p=>`<li><a href="/product.html?id=${encodeURIComponent(p.id)}">${escape(p.name)}</a>${p.description ? ' — '+escape(p.description) : ''}</li>`).join('')}</ul>` : '';
  const content = `<section class="catalog-public" id="catalogPublic"><h1>${escape(row.name)}</h1><p>${escape(description)}</p>${image ? `<img src="${escape(image)}" alt="${escape(row.name)}" width="240" height="240" decoding="async">` : ''}${list}<p><a href="/">تصفح المتجر</a></p></section>`;
  return html.replace('</head>',meta+'</head>').replace(/(<main\b[^>]*>)/i, '$1'+content);
}
export async function handleCatalog(request, read = readPublic) {
  if (!['GET','HEAD'].includes(request.method)) return new Response(null,{status:405,headers:{Allow:'GET, HEAD','Cache-Control':'no-store'}});
  const url = new URL(request.url);
  const kind = url.searchParams.get('kind');
  try {
    if (kind === 'sitemap') {
      const [categories, products] = await Promise.all(['categories','products'].map(table=>allPublicIDs(table,read)));
      // No lastmod: the current source has created_at but no reliable updated_at.
      const links = [ORIGIN+'/',...categories.map(x=>`${ORIGIN}/category.html?id=${x.id}`),...products.map(x=>`${ORIGIN}/product.html?id=${x.id}`)];
      const body = `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${links.map(link=>`<url><loc>${escape(link)}</loc></url>`).join('')}</urlset>`;
      return new Response(request.method==='HEAD'?null:body,{headers:headers('application/xml; charset=utf-8')});
    }
    if (!['product','category'].includes(kind)) return errorPage(404,'الصفحة غير موجودة');
    const id = url.searchParams.get('id');
    if (!uuid.test(id || '')) return errorPage(404,'الصفحة غير موجودة');
    const [rows,children] = await Promise.all([
      read(kind === 'product'?'products':'categories',{select:'id,name,description,image_url',id:'eq.'+id,is_active:'eq.true',limit:'1'}),
      kind === 'category'?read('products',{select:'id,name,description',category_id:'eq.'+id,is_active:'eq.true',order:'display_order,id',limit:'1000'}):[]
    ]);
    if (!rows.length) return errorPage(404,'المنتج أو القسم غير متاح');
    const body = renderCatalog(kind, rows[0],children);
    return new Response(request.method==='HEAD'?null:body,{headers:headers('text/html; charset=utf-8')});
  } catch {
    console.error('[MEEM catalog] public source unavailable'); // No sessions or payloads.
    return errorPage(503,'تعذر تحميل الكتالوج؛ حاول مجدداً');
  }
}
export default {fetch:handleCatalog};
