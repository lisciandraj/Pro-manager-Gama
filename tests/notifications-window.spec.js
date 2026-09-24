const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8')+fs.readFileSync(path.join(__dirname,'mock-dashboard.js'),'utf8');
// El servidor de alertas en el doble: filtra por categoría como el de verdad y
// deja registrada cada petición; las validaciones se deciden sobre __DB.
const bridge=`;(()=>{window.__opsCalls=[];const oldDb=GamaCloud.db;GamaCloud.db=async()=>{const c=await oldDb();const old=c.rpc;c.rpc=async(fn,args)=>{
 if(fn==='gama_approval_action'){const row=window.__DB.erp_approvals.find(r=>r.id===args.p_data.id);row.status=args.p_data.decision;row.decision_reason=args.p_data.reason;return {data:row}}
 if(fn!=='gama_operations_action')return old(fn,args);window.__opsCalls.push(args);
 const d=JSON.parse(JSON.stringify(window.__ops));const k=args.p_data.kind;if(k&&k!=='all')d.alerts=d.alerts.filter(a=>a.kind===k);d.total=d.alerts.length;return {data:d}};return c}})();`;
async function boot(page,role='admin',language='fr'){
 await page.addInitScript(({role,language})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));localStorage.setItem('gama_language_v1',language);
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[],erp_notification_preferences:[],
   erp_approvals:[{id:'ap1',module:'quotes',reason:'Remise de 25 % pour Andes',status:'pending',requested_at:'2026-09-20T10:00:00Z'}]};
  const fin=role==='admin';
  window.__ops={from:'2026-09-01',to:'2026-09-24',generated_at:'2026-09-24T09:00:00Z',finance:fin,warehouse:true,active_count:3,total:3,metrics:{},
   counts:{shortage:2,late_delivery:1,due_soon_invoice:fin?1:0,overdue_invoice:fin?2:0},
   action_center:{shortage:2,late_delivery:1,quote:fin?0:null,low_stock:0,receipt:0,overdue_invoice:fin?4850:null},
   alerts:[{alert_key:'shortage:o1',kind:'shortage',target:'order',target_id:'o1',reference:'PV-001',customer:'Andes',title:'Pedido bloqueado por stock',detail:'4 unidades sin reservar',fingerprint:'f1',handling:'open',priority:3},
    {alert_key:'shortage:o2',kind:'shortage',target:'order',target_id:'o2',reference:'PV-007',customer:'Quito',title:'Pedido bloqueado por stock',detail:'12 unidades sin reservar',fingerprint:'f2',handling:'snoozed',snoozed_until:'2026-09-25T09:00:00Z',priority:3},
    {alert_key:'late:d1',kind:'late_delivery',target:'delivery',target_id:'d1',reference:'ENT-044',customer:'Andes',title:'Entrega atrasada',detail:'Prevista el 2026-09-22',fingerprint:'f3',handling:'open',priority:2}]};
 },{role,language});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+bridge}));
 await page.goto('/index.html');await expect(page.locator('#arcNotify')).toBeVisible();
}
const win=page=>page.locator('#arcNotifyDialog');
const last=page=>page.evaluate(()=>window.__opsCalls.filter(c=>c.p_data.track).at(-1).p_data);

test('la campana abre una ventana con todas las alertas, cada categoría con su recuento y los demás apartados',async({page})=>{
 await boot(page);await page.locator('#arcNotify').click();
 await expect(win(page)).toBeVisible();await expect(win(page).locator('h2')).toHaveText('Notifications');
 await expect(win(page).locator('[role=tab] .arcSideLabel')).toHaveText(['Toutes les alertes','Commandes bloquées','Livraisons en retard','Devis sans réponse','Produits sous le minimum','Réceptions en retard','Paiements bientôt à échéance','Factures échues','Projets','Validations','Préférences']);
 // Se abre en todas las alertas activas, con el foco en su apartado.
 await expect(page.locator('#notifyTab-all')).toHaveAttribute('aria-selected','true');await expect(page.locator('#notifyTab-all')).toBeFocused();
 expect(await last(page)).toMatchObject({kind:'all',state:'active',offset:0});
 await expect(page.locator('#goAlerts article')).toHaveCount(3);
 // Recuentos: rojo si urge, naranja si hay que mirarlo, nada si está a cero.
 await expect(page.locator('#notifyTab-all .arcSideBadge')).toHaveText('3');
 await expect(page.locator('#notifyTab-shortage .arcSideBadge')).toHaveText('2');await expect(page.locator('#notifyTab-shortage .arcSideBadge')).toHaveAttribute('data-tone','danger');
 await expect(page.locator('#notifyTab-due_soon_invoice .arcSideBadge')).toHaveAttribute('data-tone','warning');
 await expect(page.locator('#notifyTab-overdue_invoice .arcSideBadge')).toHaveText('2');
 await expect(page.locator('#notifyTab-quote .arcSideBadge')).toHaveCount(0);
 // Su nombre accesible lleva la cifra.
 await expect(page.getByRole('tab',{name:'Commandes bloquées 2'})).toBeVisible();
 // Ni página de notificaciones ni tarjeta: sólo la ventana.
 await expect(page.locator('section#notifications')).toHaveCount(0);
});

test('una categoría enseña todas sus alertas, también las pospuestas; «Toutes» vuelve a las activas',async({page})=>{
 await boot(page);await page.locator('#arcNotify').click();await expect(page.locator('#goAlerts article')).toHaveCount(3);
 await page.locator('#notifyTab-shortage').click();
 expect(await last(page)).toMatchObject({kind:'shortage',state:'all',offset:0});
 await expect(page.locator('#goAlerts article')).toHaveCount(2);await expect(page.locator('#goMain h3').first()).toHaveText('Commandes bloquées');
 await expect(page.locator('#goMain .goLead')).toContainText('2');await expect(page.locator('#goMain .goLead')).toContainText('commandes bloquées par manque de stock');
 // El tipo ya lo da el apartado; el seguimiento se puede afinar.
 await expect(page.locator('#goKind')).toHaveCount(0);await expect(page.locator('#goState')).toHaveValue('all');
 await page.locator('#notifyTab-overdue_invoice').click();await expect(page.locator('#goMain .goLead')).toContainText(/4.?850/);
 await page.locator('#notifyTab-all').click();expect(await last(page)).toMatchObject({kind:'all',state:'active',offset:0});await expect(page.locator('#goKind')).toHaveCount(1);
 // Las alertas pospuestas lo dicen, en el idioma elegido.
 await page.locator('#notifyTab-shortage').click();await expect(page.locator('#goAlerts')).toContainText('Reportée jusqu’au');await expect(page.locator('#goMain')).toContainText(/2 alertes · Mis à jour/);
});

test('teclado: flechas y Fin recorren el menú; Escape cierra y devuelve el foco a la campana',async({page})=>{
 await boot(page);await page.locator('#arcNotify').click();await expect(page.locator('#notifyTab-all')).toBeFocused();
 await page.keyboard.press('ArrowDown');await expect(page.locator('#notifyTab-shortage')).toBeFocused();await expect(page.locator('#notifyTab-shortage')).toHaveAttribute('aria-selected','true');
 await expect.poll(()=>last(page).then(d=>d.kind)).toBe('shortage');
 await page.keyboard.press('End');await expect(page.locator('#notifyTab-preferences')).toBeFocused();await expect(page.locator('#notifyPane-preferences')).toBeVisible();
 await page.keyboard.press('Escape');await expect(win(page)).toHaveCount(0);await expect(page.locator('#arcNotify')).toBeFocused();
});

test('validaciones y preferencias se trabajan dentro de la ventana',async({page})=>{
 await boot(page);await page.locator('#arcNotify').click();
 await page.locator('#notifyTab-approvals').click();
 const approvals=page.locator('#goApprovals');await expect(approvals.locator('h3')).toHaveText('Validations');
 await expect(approvals).toContainText('Remise de 25 % pour Andes');await expect(approvals).toContainText('En attente');
 await approvals.getByRole('button',{name:'Examiner'}).click();
 const decision=page.locator('dialog.arcDialog');await decision.locator('[name=decision]').selectOption('approved');await decision.locator('[name=reason]').fill('Client stratégique');await decision.locator('[type=submit]').click();
 // Decidida, la lista se vuelve a pintar en su sitio: la ventana sigue abierta.
 await expect(approvals).toContainText('Approuvée');await expect(win(page)).toBeVisible();
 await page.locator('#notifyTab-preferences').click();
 const prefs=page.locator('#goPreferences form');await expect(prefs.locator('h3').first()).toHaveText('Préférences de notification');
 await prefs.locator('[name=mine]').check();await prefs.locator('[name=class]').selectOption('action');await prefs.locator('[name=kind][value="low_stock"]').uncheck();
 await prefs.getByRole('button',{name:'Enregistrer les préférences'}).click();await expect(prefs.locator('[role=status]')).toHaveText('Préférences enregistrées.');
 const saved=await page.evaluate(()=>window.__DB.erp_notification_preferences[0]);expect(saved.only_mine).toBe(true);expect(saved.hidden_kinds).toEqual(['low_stock']);
 await expect.poll(()=>last(page).then(d=>d.notification_class)).toBe('action');
});

test('abrir un dossier u otra pantalla cierra la ventana; el correo se escribe por encima de ella',async({page})=>{
 await boot(page);await page.locator('#arcNotify').click();await expect(page.locator('#goAlerts article')).toHaveCount(3);
 // El redactor de correo (recordatorios) se abre encima y Escape sólo lo cierra a él.
 await page.evaluate(()=>GamaQuotePdf.composeDialog({email:'andes@example.invalid',subject:'Recordatorio',body:'Hola'}));
 await expect(page.locator('#gamaMailBack')).toBeVisible();await page.locator('#gamaMailSubject').fill('Recordatorio de pago');await expect(page.locator('#gamaMailSubject')).toHaveValue('Recordatorio de pago');
 await page.keyboard.press('Escape');await expect(page.locator('#gamaMailBack')).toHaveCount(0);await expect(win(page)).toBeVisible();
 // Un dossier abre su pantalla: la ventana se cierra para que se vea.
 await page.evaluate(()=>{GamaSales.openOrder=async id=>{window.__opened=id;ArcRouter.show('products')}});
 await page.locator('[data-go-open]').first().click();await expect(win(page)).toHaveCount(0);
 expect(await page.evaluate(()=>window.__opened)).toBe('o1');await expect(page.locator('#products')).toBeVisible();
});

test('el almacén no ve las categorías de dinero y en el teléfono todo cabe',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'magasinier');await page.locator('#arcNotify').click();
 await expect(win(page).locator('[role=tab] .arcSideLabel')).toHaveText(['Toutes les alertes','Commandes bloquées','Livraisons en retard','Produits sous le minimum','Réceptions en retard','Projets','Validations','Préférences']);
 expect(await win(page).boundingBox()).toMatchObject({x:0,y:0,width:390,height:844});
 const all=await page.locator('#notifyTab-all').boundingBox(),next=await page.locator('#notifyTab-shortage').boundingBox();expect(Math.abs(all.y-next.y)).toBeLessThan(1);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 expect(await page.locator('.arcSidePanes').evaluate(e=>e.scrollWidth<=e.clientWidth)).toBe(true);
 // Los botones de una alerta pasan a la línea siguiente en vez de aplastarse.
 const widths=await page.locator('#goAlerts article').first().locator('.goActions button').evaluateAll(b=>b.map(x=>x.getBoundingClientRect().width));
 expect(Math.min(...widths)).toBeGreaterThan(90);
 await page.screenshot({path:test.info().outputPath('notifications-window-mobile.png')});
});

test('cerrar la sesión cierra la ventana; renovar el token no',async({page})=>{
 await boot(page);await page.locator('#arcNotify').click();await expect(win(page)).toBeVisible();
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'TOKEN_REFRESHED'}})));await expect(win(page)).toBeVisible();
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(win(page)).toHaveCount(0);
});
