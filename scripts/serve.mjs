// Local, public-assets-only server with the same security headers as Vercel.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {handleCatalog} from '../api/catalog.mjs';
const root=path.resolve(new URL('..',import.meta.url).pathname);
const publicRoot=process.argv.includes('--built')?path.join(root,'dist'):root;
const port=Number(process.argv.find(x=>x.startsWith('--port='))?.split('=')[1]||3000);
// Deterministic, explicitly local catalog fixtures for browser tests only.
const fixturePath=process.argv.find(x=>x.startsWith('--catalog-fixture='))?.slice('--catalog-fixture='.length);
const fixture=fixturePath?JSON.parse(fs.readFileSync(fixturePath,'utf8')):null;
const fixtureRead=fixture?async(table,params)=>{
  let rows=fixture[table]||[];
  for(const key of ['id','category_id']) if(params[key]?.startsWith('eq.')) rows=rows.filter(r=>r[key]===params[key].slice(3));
  return rows.slice(Number(params.offset||0),Number(params.offset||0)+Number(params.limit||1000));
}:undefined;
const config=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));
const headers=Object.fromEntries(config.headers[0].headers.map(h=>[h.key,h.value]));
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.jpg':'image/jpeg','.woff2':'font/woff2','.json':'application/json','.txt':'text/plain; charset=utf-8','.xml':'application/xml; charset=utf-8'};
http.createServer(async(req,res)=>{
  try {
    if(!['GET','HEAD'].includes(req.method)) { res.writeHead(405,headers).end(); return; }
    const pathname=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname);
    const redirect=config.redirects?.find(r=>r.source===pathname);
    if(redirect){res.writeHead(redirect.permanent?308:307,{...headers,Location:redirect.destination+new URL(req.url,'http://127.0.0.1').search}).end();return;}
    if(['/product.html','/category.html','/sitemap.xml','/api/catalog'].includes(pathname)) {
      const url=new URL(req.url,'http://127.0.0.1');
      if(pathname!=='/api/catalog') url.searchParams.set('kind',pathname==='/sitemap.xml'?'sitemap':pathname.slice(1,-5));
      const result=await handleCatalog(new Request(url,{method:req.method}),fixtureRead);
      res.writeHead(result.status,{...headers,...Object.fromEntries(result.headers)});
      res.end(await result.text()); return;
    }
    const name=pathname==='/'?'index.html':pathname.slice(1);
    const file=path.resolve(publicRoot,name);
    const publicFile=/^[^/]+\.html$/.test(name)||name==='robots.txt'||name.startsWith('assets/');
    if(!publicFile||!file.startsWith(publicRoot+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404,headers).end();return;}
    const cache=/\.[a-f0-9]{12}\.[a-z0-9]+$/.test(name)?'public, max-age=31536000, immutable':name.startsWith('assets/')?'public, max-age=3600, must-revalidate':'no-cache, must-revalidate';
    res.writeHead(200,{...headers,'Cache-Control':cache,'Content-Type':mime[path.extname(file)]||'application/octet-stream'});
    if(req.method==='HEAD')res.end();else fs.createReadStream(file).pipe(res);
  } catch {res.writeHead(400,headers).end();}
}).listen(port,'127.0.0.1',()=>console.log(`MEEM STORE http://127.0.0.1:${port}`));
