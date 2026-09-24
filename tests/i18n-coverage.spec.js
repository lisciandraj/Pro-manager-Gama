const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const ROOT=path.join(__dirname,'..');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8')+fs.readFileSync(path.join(__dirname,'mock-dashboard.js'),'utf8');
// Con la interfaz en francés o en inglés no queda nada en español: pestañas, estados,
// botones, mensajes, alertas compuestas por el servidor. Los datos del negocio
// (nombres de productos, clientes, referencias) se muestran tal cual.
const catalogRows=()=>fs.readFileSync(path.join(ROOT,'locales/catalog.tsv'),'utf8').split('\n').filter(l=>l.includes('\t')&&!l.startsWith('#')).map(l=>l.split('\t'));
const generated=name=>{const line=fs.readFileSync(path.join(ROOT,'gama-i18n-catalog.js'),'utf8').split('\n').find(l=>l.startsWith('window.'+name+'='));return JSON.parse(line.slice(line.indexOf('=')+1).replace(/;\s*$/,''))};
const builtCatalog=()=>generated('GamaI18nCatalog');
const sources=()=>['index.html',...fs.readdirSync(ROOT).filter(f=>/^gama-.*\.js$/.test(f)&&!f.startsWith('gama-i18n'))];

test('le catalogue est complet et cohérent dans les trois langues',()=>{
 const rows=catalogRows(),problems=[],seen=new Set();
 const holes=s=>(s.match(/\{\d+\}/g)||[]).sort().join();
 for(const r of rows){
  const [es,fr,en]=r;
  if(r.length!==3||!es?.trim()||!fr?.trim()||!en?.trim())problems.push('incomplète: '+r.join(' | '));
  if(seen.has(es))problems.push('en double: '+es);seen.add(es);
  if(holes(es)!==holes(fr)||holes(es)!==holes(en))problems.push('paramètres différents: '+es);
  for(const [lang,v] of [['fr',fr],['en',en]])if(/[ñ¿¡áíóúÑÁÍÓÚ]/.test(v||''))problems.push(lang+' en espagnol: '+v);
 }
 expect(problems).toEqual([]);
 // El catálogo generado (gama-i18n-catalog.js) está al día con locales/catalog.tsv.
 const built=builtCatalog(),stale=rows.filter(r=>JSON.stringify(built[crypto.createHash('sha256').update(r[0]).digest('hex').slice(0,12)])!==JSON.stringify(r)).map(r=>r[0]);
 expect(stale).toEqual([]);
});

test('chaque texte marqué correspond à sa ligne du catalogue',()=>{
 const catalog=builtCatalog(),bad=[];
 const unesc=s=>s.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&nbsp;/g,' ');
 const norm=s=>unesc(s).split(/\s+/).filter(Boolean).join(' ');
 for(const f of sources()){
  const s=fs.readFileSync(path.join(ROOT,f),'utf8');
  for(const m of s.matchAll(/ data-gi=([a-f0-9]{12})>([^<>]*)(?=<)/g)){const row=catalog[m[1]];if(!row||row[0]!==norm(m[2]))bad.push(f+': '+m[1]+' «'+norm(m[2]).slice(0,50)+'»')}
  for(const tag of s.match(/<[a-z][\w-]*\b[^<>]*>/g)||[])for(const m of tag.matchAll(/data-gi-(placeholder|title|aria-label)=([a-f0-9]{12})\b/g)){
   const v=tag.match(new RegExp('(?:^|\\s)'+m[1]+'=("|\')(.*?)\\1')),row=catalog[m[2]];if(!v||!row||row[0]!==norm(v[2]))bad.push(f+': '+m[1]+' '+m[2]);
  }
 }
 expect(bad).toEqual([]);
});

async function boot(page,role,lang){
 await page.addInitScript(([role,lang])=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Test Langues'}));localStorage.setItem('gama_language_v1',lang);localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={
   products:[{id:'p1',name:'Ciment gris 50 kg',reference:'CIM-50',barcode:'786001',category:'Construction',stock:3,min_stock:5,sale_price:8.5,purchase_price:6.1,active:true,tax_rate:15,unit:'u'},{id:'p2',name:'Ancien produit',reference:'OLD-1',active:false}],
   customers:[{id:'c1',name:'Client Nord',email:'nord@example.invalid',active:true},{id:'c2',name:'Client Sud',active:false}],suppliers:[{id:'s1',name:'Fournisseur Est',active:true}],
   invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[],stock_movements:[],
   profiles:[{id:'u1',full_name:'Test Langues',role:'administrador',active:true,email:'test@example.invalid'}],
   hr_employees:[{id:'e1',full_name:'Camille Martin',job_title:'Logistique',active:true,profile_id:'u1',hire_date:'2024-03-01'}],hr_absences:[],hr_employee_private:[],hr_absence_private:[],
   warehouses:[{id:'w1',code:'GYE',name:'Entrepôt central',active:true}],fleet_drivers:[],
   fleet_vehicles:[['v1','in_service'],['v2','repair'],['v3','out_of_service']].map(([id,status])=>({id,plate:'GB-'+id,brand:'Hino',model:'300',kind:'truck',status,active:true})),
   crm_contacts:[],customer_requests:[],customer_request_lines:[],erp_approvals:[]};
  // Cada estado, etapa y tipo al menos una vez: son los textos que más se escapan.
  const D=window.__DB,day=n=>new Date(Date.now()+n*86400000).toISOString().slice(0,10),ts=n=>new Date(Date.now()+n*86400000).toISOString();
  Object.assign(D,{
   crm_pipeline_stages:['Nuevo','Calificación','Primer contacto','Análisis de la necesidad','Propuesta','Negociación','Ganado','Perdido'].map((name,i)=>({id:'st'+i,name,sort_order:i+1,default_probability:10*i,is_won:name==='Ganado',is_lost:name==='Perdido',active:true})),
   crm_sources:['Sitio web','Teléfono','Correo','Feria','Publicidad','Recomendación','Redes sociales','Socio','Prospección','Otro'].map((name,i)=>({id:'so'+i,name,sort_order:i+1,active:true})),
   crm_lost_reasons:['Precio','Competencia','Sin presupuesto','Fuera de plazo','Sin respuesta','No era el momento','Otro'].map((name,i)=>({id:'lr'+i,name,sort_order:i+1,active:true})),
   crm_leads:['nuevo','contactado','calificado','no_calificado','convertido','perdido'].map((status,i)=>({id:'l'+i,first_name:'Lead',last_name:'N'+i,company:'Compagnie '+i,status,priority:['baja','media','alta'][i%3],email:'lead'+i+'@example.invalid',active:true,source_id:'so'+i,owner_id:'u1',next_followup_at:ts(i-2),created_at:ts(-i)})),
   crm_opportunities:[0,1,2,3,4,5,6,7].map(i=>({id:'o'+i,reference:'OPP-00'+i,title:'Affaire '+i,stage_id:'st'+i,customer_id:'c1',amount:1000*(i+1),probability:10*i,owner_id:'u1',expected_close_date:day(10+i),active:true,priority:['baja','media','alta'][i%3],source_id:'so'+i,won_at:i===6?ts(-3):null,lost_at:i===7?ts(-2):null,lost_reason_id:i===7?'lr1':null,created_at:ts(-20),updated_at:ts(-1)})),
   crm_activities:['pendiente','en_curso','hecha','cancelada'].flatMap((status,i)=>['llamada','correo','reunion','visita'].map((kind,j)=>({id:'a'+i+j,subject:'Suivi '+i+j,kind,status,due_at:ts(i-1),owner_id:'u1',lead_id:'l'+j,priority:['baja','media','alta'][j%3],created_at:ts(-5)}))),
   hr_absences:['pendiente','aprobada','rechazada','cancelada'].map((status,i)=>({id:'ab'+i,employee_id:'e1',kind:['vacaciones','enfermedad','permiso','formacion'][i],status,start_date:day(i*2),end_date:day(i*2+2),days:3,created_at:ts(-3)})),
   tms_deliveries:['Pendiente de preparación','Planificada','En carga','Lista para envío','En tránsito','En ruta','Entregada','Excepción','Cancelada'].map((status,i)=>({id:'d'+i,customer:'Client '+i,address:'Adresse '+i,delivery_date:day(i-4),status,priority:['Normal','Alta','Urgente'][i%3],time_window:'08:00-12:00',weight:10,volume:1,dossier_reference:'PDV-0000'+i})),
   purchase_orders:['draft','sent','partial','received','cancelled'].map((status,i)=>({id:'po'+i,order_number:'PC-000'+i,supplier_id:'s1',status,expected_date:ts(i-2),total:100*(i+1),created_at:ts(-6)})),
  });
 },[role,lang]);
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.ArcModules&&window.ArcRouter&&window.gamaAccessAllowed);await page.waitForTimeout(800);
}

// Mots et lettres propres al español; los valores del negocio de los datos de prueba se excluyen.
const spanishOnScreen=page=>page.evaluate(()=>{
 const LETTERS=/[áíóúñ¿¡ÁÍÓÚÑ]/;
 const WORDS=new Set(('el los las del con para por una unos unas sin esta este estos estas hay más también cuando donde aquí ahora nuevo nueva nuevos nuevas guardar cancelar buscar borrar editar añadir crear cerrar abrir volver enviar descargar imprimir seleccionar elegir fecha fechas estado estados pendiente pendientes aprobado aprobada rechazado rechazada borrador cerrado cerrada abierto abierta entregado entregada enviado enviada pagado pagada vencido vencida cancelado cancelada activo activa activos activas pedido pedidos factura facturas proveedor proveedores cliente clientes almacén ubicación cantidad precio venta ventas compra compras cobro pago pagos entrega entregas presupuesto presupuestos empleado empleados hoy ayer semana hora horas ninguno ninguna todos todas otro otra apellidos correo usuario cargando producto productos referencia notas nota tipo motivo importe saldo cuenta caja cobrar pagar desde hasta sus ver hacer puede tiene inicio resumen detalle lista filtro').split(' '));
 // Estados, tipos, títulos y listas de configuración no cuentan como datos: son lo que se busca.
 const CONFIG=new Set(['crm_pipeline_stages','crm_sources','crm_lost_reasons']),ENUM=new Set(['status','kind','priority','stage','state','title','detail','tone']);
 const data=new Set();(function walk(v,key){if(typeof v==='string'){if(v.length>=3&&!ENUM.has(key))data.add(v)}else if(v&&typeof v==='object')for(const k in v){if(!CONFIG.has(k))walk(v[k],Array.isArray(v)?key:k)}})([window.__DB,window.__PRIO]);
 const isData=t=>{for(const s of data)if(t.includes(s))return true;return false};
 // Además de la lista de palabras: cualquier texto del catálogo que siga en su español de origen.
 // («Nombre» es también la traducción francesa de «Cuántas»: un texto válido en el idioma elegido no cuenta.)
 const col={fr:1,en:2}[GamaI18n.language],rowsCat=Object.values(window.GamaI18nCatalog),valid=new Set(rowsCat.map(r=>r[col]));
 const known=new Set(rowsCat.filter(r=>r[col]!==r[0]&&!valid.has(r[0])).map(r=>r[0]));
 const core=t=>{const m=t.match(/^([^\p{L}\p{N}]*)(.*?)([\s:·*….!?—]*)$/u);return m?m[2]:t};
 const spanish=t=>known.has(t)||known.has(core(t))||LETTERS.test(t)||(t.toLowerCase().match(/\p{L}+/gu)||[]).some(w=>WORDS.has(w));
 const shown=el=>el.checkVisibility({visibilityProperty:true,opacityProperty:true});
 const out=new Set(),push=v=>{const t=String(v||'').replace(/\s+/g,' ').trim();if(t&&spanish(t)&&!isData(t))out.add(t.slice(0,90))};
 const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);let n;
 while((n=w.nextNode())){const el=n.parentElement;if(!el||el.closest('script,style,template,textarea,[translate=no],[data-gi-ignore]')||!shown(el))continue;push(n.nodeValue)}
 for(const el of document.querySelectorAll('[placeholder],[title],[aria-label]'))if(!el.closest('[translate=no]')&&shown(el))for(const a of ['placeholder','title','aria-label'])push(el.getAttribute(a));
 return [...out];
});
const TABS='[role=tab],.hrTabs button,.gdfTab,.tmsTab,.gamaArcTabs button,.ivTabs button,.crmNav button,.gaNav button,.gfNav button,.grNav button,.pmTabs button';

for(const [role,lang] of [['admin','fr'],['admin','en'],['client','fr'],['rh','en']])test(`rien en espagnol à l’écran, module par module et onglet par onglet (${role}, ${lang})`,async({page})=>{
 test.setTimeout(240000);
 await boot(page,role,lang);
 const modules=await page.evaluate(()=>window.ArcModules.registry.filter(m=>!m.retired&&!m.tabOf&&window.gamaAccessAllowed?.(m.id)).map(m=>m.id));
 expect(modules.length).toBeGreaterThan(1);
 const found={};
 const open=async(id,tab)=>{
  await page.evaluate(()=>document.querySelectorAll('dialog[open]').forEach(d=>d.close()));
  await page.evaluate(id=>{try{ArcRouter.open(id)}catch(_){}},id);await page.waitForTimeout(600);
  if(tab!=null){await page.evaluate(([sel,i])=>{const b=[...document.querySelectorAll('section.active '+sel.split(',').join(',section.active '))].filter(x=>x.offsetParent)[i];b?.click()},[TABS,tab]);await page.waitForTimeout(500)}
 };
 for(const id of modules){
  await open(id,null);
  const count=await page.evaluate(sel=>[...document.querySelectorAll('section.active '+sel.split(',').join(',section.active '))].filter(x=>x.offsetParent).length,TABS);
  for(const tab of [null,...Array.from({length:Math.min(count,10)},(_,i)=>i)]){
   if(tab!=null)await open(id,tab);
   const hits=await spanishOnScreen(page);
   if(hits.length)found[id+(tab==null?'':' #'+tab)]=hits;
  }
 }
 expect(found).toEqual({});
});

// Detalles que compone el servidor: se traducen las etiquetas, nunca los valores.
test('alertes composées par le serveur : libellés traduits, valeurs intactes',async({page})=>{
 await boot(page,'admin','fr');
 const fr=await page.evaluate(()=>['Vencimiento: 2026-09-01 · saldo: 120.00 USD','Disponible: 3 · mínimo: 10 · entrante: 0 · compra sugerida: 7','Enviado: 2026-09-10 12:00:00+00 · revisión 2',
  'Excepción · prevista: 2026-09-12','3 líneas con diferencia · 7 unidades (valor absoluto)','120.50 USD por vincular · expedido sin factura: 80.00 USD','Creada el 2026-09-10','Faltan 500 km','Vence: 2026-10-01',
  'Responsable: Sin asignar · Última actividad: 2026-09-10','Importe: 45.00 · Ciment gris','Reliquat pendiente','Permiso de conducir por caducar'].map(s=>GamaI18n.t(s)));
 expect(fr).toEqual(['Échéance : 2026-09-01 · solde : 120.00 USD','Disponible : 3 · minimum : 10 · entrant : 0 · achat suggéré : 7','Envoyé : 2026-09-10 12:00:00+00 · révision 2',
  'Exception · prévue : 2026-09-12','3 lignes avec écart · 7 unités (valeur absolue)','120.50 USD à rattacher · expédié sans facture : 80.00 USD','Créée le 2026-09-10','Encore 500 km','Expire le : 2026-10-01',
  'Responsable : Non attribué · Dernière activité : 2026-09-10','Montant : 45.00 · Ciment gris','Reliquat en attente','Permis de conduire bientôt expiré']);
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 const en=await page.evaluate(()=>['Vencimiento: 2026-09-01 · saldo: 120.00 USD','Faltan 500 km','Recibida el 2026-09-11','3 días naturales · 2 días laborables'].map(s=>GamaI18n.t(s)));
 expect(en).toEqual(['Due date: 2026-09-01 · balance: 120.00 USD','500 km left','Received on 2026-09-11','3 calendar days · 2 working days']);
});

// Algunas funciones del servidor responden en inglés: el mensaje se enseña en el idioma elegido, español incluido.
test('messages du serveur en anglais : affichés dans la langue choisie, espagnol compris',async({page})=>{
 await boot(page,'admin','es');
 const server=generated('GamaI18nServer'),rows=new Set(catalogRows().map(r=>r[0]));
 expect(Object.keys(server).length).toBeGreaterThan(20);
 expect(Object.values(server).filter(v=>!rows.has(v))).toEqual([]);
 const say=()=>page.evaluate(()=>['Overlapping approved absence','No se pudo guardar: Overlapping shift','Authentication required'].map(s=>GamaI18n.t(s)));
 expect(await say()).toEqual(['Ya hay una ausencia aprobada en ese periodo.','No se pudo guardar: Este turno se solapa con otro.','Vuelve a iniciar sesión para continuar.']);
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 expect((await say())[0]).toBe('Une absence approuvée couvre déjà cette période.');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 expect((await say())[0]).toBe('An approved absence already covers this period.');
});
