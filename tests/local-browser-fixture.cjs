const fs=require('node:fs');
const path=require('node:path');

// Resource hints can open sockets without passing through request routing.
// Keep the production entry intact and serve a local-only copy to these tests.
function localEntry(){
 return fs.readFileSync(path.join(__dirname,'../index.html'),'utf8')
  .replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi,'')
  .replace(/connect-src\s+[^;]+/,"connect-src 'self'");
}
async function isolateLocalPage(page){
 await page.context().route('**/*',r=>{
  const url=new URL(r.request().url());
  if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname))return r.abort();
  if(url.pathname==='/index.html')return r.fulfill({contentType:'text/html',body:localEntry()});
  return r.continue();
 });
 await page.context().routeWebSocket('**/*',ws=>ws.close());
}
module.exports={isolateLocalPage,localEntry};
