import {dbRpc} from './api.mjs';
export const escapeBootstrap=data=>JSON.stringify(data).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
export function metadata(data){const c=data?.settings||{};return {title:c.seo_title||c.brand_name||'Distribuidora GAMA',description:c.seo_description||'',color:/^#[0-9a-f]{6}$/i.test(c.primary_color||'')?c.primary_color:'#176072'}}
export async function onRequest(context){
 const url=new URL(context.request.url);if(context.request.method!=='GET'||!['/','/index.html'].includes(url.pathname))return context.next();
 const response=await context.next();if(!response.headers.get('Content-Type')?.includes('text/html'))return response;
 try{const data=await dbRpc('bootstrap',{},context.env);const m=metadata(data);return new HTMLRewriter()
  .on('title',{element:e=>e.setInnerContent(m.title)})
  .on('meta[name="description"],meta[property="og:description"]',{element:e=>e.setAttribute('content',m.description)})
  .on('meta[property="og:title"]',{element:e=>e.setAttribute('content',m.title)})
  .on('meta[name="theme-color"]',{element:e=>e.setAttribute('content',m.color)})
  .on('#initial-data',{element:e=>e.setInnerContent(escapeBootstrap(data),{html:true})})
  .on('#heroTitle',{element:e=>e.setInnerContent(data.settings?.hero_title||'Volvemos en un momento.')})
  .on('#heroAccent',{element:e=>e.setInnerContent(data.settings?.hero_accent||'')})
  .transform(new Response(response.body,{status:response.status,headers:new Headers({...Object.fromEntries(response.headers),'Cache-Control':'no-store'})}));
 }catch(_){return response}
}
