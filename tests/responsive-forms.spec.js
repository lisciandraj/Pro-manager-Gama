const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
// Safari (iPhone, iPad, Mac) sigue contando el ancho natural de un campo al medir
// su casilla; Chrome no. Se imita aquí con un ancho que no es un porcentaje: si
// una casilla se ensancha por su campo, se sale de su columna o de la página.
const SAFARI_SIZING='input:not([type=checkbox]):not([type=radio]):not([type=hidden]),select,textarea{width:-webkit-fill-available!important;max-width:-webkit-fill-available!important}';
const LONG='Distribuidora Industrial del Pacífico Sur S.A.S. — Sucursal Guayaquil Norte';
async function boot(page){
 await page.addInitScript(LONG=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Responsive QA'}));localStorage.setItem('gama_language_v1','fr');
  window.__DB={products:[{id:'p1',name:'Cemento Portland tipo IP saco de 50 kg para obra gruesa y cimentaciones',reference:'CEM-50',active:true,sale_price:8,stock:4,min_stock:10}],
   customers:[{id:'c1',name:LONG,active:true,address:'Av. Francisco de Orellana y Justino Cornejo, Edificio World Trade Center, Torre B'}],
   suppliers:[{id:'s1',name:'Holcim Ecuador S.A. — División Cementos, Agregados y Hormigones Premezclados',active:true}],
   invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[],profiles:[],
   hr_employees:[{id:'e1',full_name:'Camila Martinez Villavicencio de la Torre',active:true}],hr_absences:[],hr_employee_private:[],hr_absence_private:[],hr_work_patterns:[],hr_holidays:[],hr_leave_accounts:[],
   tms_deliveries:[],tms_routes:[],tms_proofs:[],tms_events:[],tms_settings:[],fleet_drivers:[],fleet_vehicles:[]};
 },LONG);
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await expect(page.locator('#mainmenu .gamaF2Card').first()).toBeVisible();
 await page.addStyleTag({content:SAFARI_SIZING});
}
// Campos visibles que se salen de su casilla, de su tarjeta o de la pantalla, y campos que se pisan.
function problems(page){
 return page.evaluate(()=>{
  const scope=[...document.querySelectorAll('dialog[open]')].at(-1)||document.querySelector('section.active');
  const out=[];if(document.documentElement.scrollWidth>innerWidth+1)out.push('page '+document.documentElement.scrollWidth+'>'+innerWidth);
  const seen=el=>!el.closest('details:not([open])')&&el.checkVisibility({visibilityProperty:true,opacityProperty:true,contentVisibilityAuto:true})&&el.getBoundingClientRect().width>2;
  const scrolls=(el,stop)=>{for(let e=el.parentElement;e;e=e.parentElement){if(/(auto|scroll|hidden|clip)/.test(getComputedStyle(e).overflowX))return true;if(e===stop)break}return false};
  const inner=el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return {l:r.left+parseFloat(s.paddingLeft)+parseFloat(s.borderLeftWidth),r:r.right-parseFloat(s.paddingRight)-parseFloat(s.borderRightWidth)}};
  const fields=[...scope.querySelectorAll('input:not([type=hidden]):not([type=checkbox]):not([type=radio]),select:not(.gamaFindOculto),textarea,.gamaFind')].filter(seen);
  const name=el=>el.id||el.closest('label')?.textContent.trim().slice(0,30)||el.className;
  for(const el of fields){
   const r=el.getBoundingClientRect(),cell=el.closest('label,.arcField')||el.parentElement,c=inner(cell);
   if(cell!==el&&r.right>c.r+2&&!scrolls(el,cell))out.push('outside its cell: '+name(el));
   const card=el.closest('.arcPanel,.card,.coCard,.hpBox,.tmsCard,form,dialog,section'),k=card.getBoundingClientRect();
   if(r.right>k.right+2&&!scrolls(el,card))out.push('outside its card: '+name(el));
   if(r.right>innerWidth+1&&!scrolls(el,document.body))out.push('outside the screen: '+name(el));
  }
  for(let i=0;i<fields.length;i++)for(let j=i+1;j<fields.length;j++){const a=fields[i].getBoundingClientRect(),b=fields[j].getBoundingClientRect();if(fields[i].contains(fields[j])||fields[j].contains(fields[i]))continue;if(Math.min(a.right,b.right)-Math.max(a.left,b.left)>2&&Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top)>2)out.push('overlap: '+name(fields[i])+' / '+name(fields[j]))}
  return out;
 });
}
const VIEWS={
 'matrice commerciale':page=>page.evaluate(()=>ArcRouter.open('matrix')),
 'livraison › planification':async page=>{await page.evaluate(()=>ArcRouter.open('tms'));await page.locator('#gama-tms-section [role=tab]',{hasText:'Planification'}).click()},
 'fiche entreprise':page=>page.evaluate(()=>GamaSettings.open('company')),
 'RH › règles':async page=>{await page.evaluate(()=>ArcRouter.open('hr'));await page.locator('#hr .hrTabs button',{hasText:'Règles'}).click()},
};
// Téléphone debout et couché, tablette couchée: las pantallas del informe.
for(const [view,open] of Object.entries(VIEWS))test(`${view}: ningún campo se sale ni se pisa, también con las medidas de Safari`,async({page})=>{
 await boot(page);await open(page);await page.waitForTimeout(800);
 for(const [width,height] of [[390,844],[844,390],[932,430],[1024,768]]){
  await page.setViewportSize({width,height});await page.waitForTimeout(150);
  expect(await problems(page),`${view} @ ${width}x${height}`).toEqual([]);
 }
});

// Con la encoche a un lado (teléfono couché), la navegación, la barra y el
// contenido se apartan de ella; en los demás equipos el margen es cero.
test('en paysage, la navigation, la barre et le contenu évitent l’encoche',async({page})=>{
 await page.setViewportSize({width:932,height:430});await boot(page);
 const before=await page.evaluate(()=>({side:document.querySelector('.arcSidebar').getBoundingClientRect().width,main:document.querySelector('.arcMain').getBoundingClientRect().left,bar:getComputedStyle(document.querySelector('.arcTopbar')).paddingRight}));
 await page.addStyleTag({content:':root{--arc-safe-l:47px;--arc-safe-r:34px}'});
 const after=await page.evaluate(()=>({side:document.querySelector('.arcSidebar').getBoundingClientRect().width,main:document.querySelector('.arcMain').getBoundingClientRect().left,bar:getComputedStyle(document.querySelector('.arcTopbar')).paddingRight,icon:document.querySelector('.arcNavLink .arcIco').getBoundingClientRect().left,avatar:document.querySelector('#arcProfileButton').getBoundingClientRect().right}));
 expect(after.side-before.side).toBe(47);expect(after.main-before.main).toBe(47);
 expect(parseFloat(after.bar)-parseFloat(before.bar)).toBe(34);
 expect(after.icon).toBeGreaterThanOrEqual(47);expect(after.avatar).toBeLessThanOrEqual(932-34);
 // Las ventanas de Configuración y Notificaciones, a pantalla completa, también.
 await page.locator('#arcSettings').click();
 const win=await page.locator('#arcSettingsDialog').boundingBox();expect(win).toMatchObject({x:0,width:932});
 expect(await page.locator('#cfgTab-language').evaluate(e=>e.getBoundingClientRect().left)).toBeGreaterThanOrEqual(47);
 expect(await page.locator('[data-side-close]').evaluate(e=>e.getBoundingClientRect().right)).toBeLessThanOrEqual(932-34);
});

// iPhone e iPad: la fecha y la hora dejan su aspecto nativo, que impone un ancho mínimo.
test('la hoja de estilos quita a las fechas de iOS su ancho mínimo nativo',async({page})=>{
 await boot(page);
 const rule=await page.evaluate(()=>{for(const sheet of document.styleSheets){let rules;try{rules=sheet.cssRules}catch(_){continue}for(const r of rules)if(r.conditionText&&r.conditionText.includes('-webkit-touch-callout'))return r.cssText}return ''});
 expect(rule).toMatch(/input:is\(\[type="?date"?\]/);expect(rule).toMatch(/appearance: none/);
});
