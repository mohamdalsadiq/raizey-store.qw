// Local, public-assets-only server with the same security headers as Vercel.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(new URL('..',import.meta.url).pathname);
const config=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));
const headers=Object.fromEntries(config.headers[0].headers.map(h=>[h.key,h.value]));
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.jpg':'image/jpeg','.woff2':'font/woff2','.json':'application/json'};
http.createServer((req,res)=>{
  try {
    if(!['GET','HEAD'].includes(req.method)) { res.writeHead(405,headers).end(); return; }
    const pathname=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname);
    const redirect=config.redirects?.find(r=>r.source===pathname);
    if(redirect){res.writeHead(307,{...headers,Location:redirect.destination}).end();return;}
    const name=pathname==='/'?'index.html':pathname.slice(1);
    const file=path.resolve(root,name);
    const publicFile=/^[^/]+\.html$/.test(name)||name.startsWith('assets/');
    if(!publicFile||!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404,headers).end();return;}
    res.writeHead(200,{...headers,'Content-Type':mime[path.extname(file)]||'application/octet-stream'});
    if(req.method==='HEAD')res.end();else fs.createReadStream(file).pipe(res);
  } catch {res.writeHead(400,headers).end();}
}).listen(3000,'127.0.0.1',()=>console.log('MEEM STORE http://127.0.0.1:3000'));
