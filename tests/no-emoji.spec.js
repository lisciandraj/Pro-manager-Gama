const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
// Ningún emoji en la interfaz: ni en los botones, ni en los títulos, ni en los
// mensajes. Los dibujos son los de la aplicación (ArcUI.icons): tarjetas del
// inicio, navegación, cabeceras de módulo, ventanas de Configuración y
// Notificaciones, y los huecos de «sin foto».
const EMOJI=/(?:\p{Extended_Pictographic}|\p{Regional_Indicator})(?:️|‍\p{Extended_Pictographic})*/u;
const ROOT=path.join(__dirname,'..');

test('aucun fichier de l’interface ne contient d’emoji',()=>{
 const files=['index.html','locales/catalog.tsv',...fs.readdirSync(ROOT).filter(f=>/^(gama|architect)-.*\.(js|css)$/.test(f))];
 const walk=d=>{for(const f of fs.readdirSync(path.join(ROOT,d))){const p=path.join(d,f);if(fs.statSync(path.join(ROOT,p)).isDirectory())walk(p);else if(/\.(js|css)$/.test(f))files.push(p)}};
 walk('src');
 const found=[];
 for(const f of files){const lines=fs.readFileSync(path.join(ROOT,f),'utf8').split('\n');lines.forEach((l,i)=>{const m=l.match(EMOJI);if(m)found.push(f+':'+(i+1)+' '+m[0]+' '+l.trim().slice(0,60))})}
 expect(found).toEqual([]);
});

async function boot(page,role){
 await page.addInitScript(role=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Sin Emoji'}));localStorage.setItem('gama_language_v1','fr');localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={products:[{id:'p1',name:'Produit sans photo',barcode:'786001',stock:3,min_stock:5,sale_price:8,active:true},{id:'p2',name:'Ancien produit',active:false}],
   customers:[{id:'c1',name:'Client actif',active:true},{id:'c2',name:'Client archivé',active:false}],suppliers:[{id:'s1',name:'Fournisseur',active:true}],
   invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[],profiles:[],crm_leads:[],crm_contacts:[],
   hr_employees:[{id:'e1',full_name:'Camila Martinez',active:true}],hr_absences:[],hr_employee_private:[],hr_absence_private:[]};
 },role);
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.ArcModules&&window.ArcRouter&&window.gamaAccessAllowed);await page.waitForTimeout(800);
}
// Texto visible y atributos que se leen (placeholder, title, aria-label, alt).
const visibleEmoji=page=>page.evaluate(src=>{
 const re=new RegExp(src,'u'),out=[];const seen=el=>el.checkVisibility({visibilityProperty:true,opacityProperty:true});
 const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);let n;
 while((n=w.nextNode())){if(re.test(n.nodeValue)&&n.parentElement&&!n.parentElement.closest('script,style')&&seen(n.parentElement))out.push(n.nodeValue.trim().slice(0,50))}
 for(const el of document.querySelectorAll('[placeholder],[title],[aria-label],[alt]'))for(const a of ['placeholder','title','aria-label','alt']){const v=el.getAttribute(a);if(v&&re.test(v)&&seen(el))out.push(a+': '+v.slice(0,50))}
 return [...new Set(out)];
},EMOJI.source);

for(const role of ['admin','client'])test(`aucun emoji à l’écran, module par module (${role})`,async({page})=>{
 test.setTimeout(120000);
 await boot(page,role);
 const modules=await page.evaluate(()=>window.ArcModules.registry.filter(m=>!m.retired&&!m.tabOf&&window.gamaAccessAllowed?.(m.id)).map(m=>m.id));
 expect(modules.length).toBeGreaterThan(role==='admin'?15:1);
 const found={};
 for(const id of modules){
  await page.evaluate(()=>document.querySelectorAll('dialog[open]').forEach(d=>d.close()));
  await page.evaluate(id=>{try{ArcRouter.open(id)}catch(_){}},id);await page.waitForTimeout(700);
  const hits=await visibleEmoji(page);if(hits.length)found[id]=hits;
 }
 expect(found).toEqual({});
});
