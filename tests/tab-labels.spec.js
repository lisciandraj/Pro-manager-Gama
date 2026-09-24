const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
// Las pestañas llevan sólo su nombre (y, en Notificaciones, su recuento): los
// iconos quedan para las tarjetas del inicio y la navegación, que son los módulos.
async function boot(page,role='admin',db={}){
 await page.addInitScript(({role,db})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Tabs QA'}));localStorage.setItem('gama_language_v1','fr');
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[],profiles:[],
   hr_employees:[{id:'e1',full_name:'Camila Martinez',active:true}],hr_absences:[],hr_employee_private:[],hr_absence_private:[],...db};
 },{role,db});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await expect(page.locator('#mainmenu .gamaF2Card').first()).toBeVisible();
}
const PICTOGRAPH=/\p{Extended_Pictographic}|[✓✔]/u;
const decorated=locator=>locator.evaluateAll((tabs,src)=>{const re=new RegExp(src,'u');return tabs.filter(t=>re.test(t.textContent)||t.querySelector('svg,img')).map(t=>t.textContent.trim())},PICTOGRAPH.source);

test('les onglets RH n’ont plus d’icône, côté RH',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('hr'));
 const tabs=page.locator('#hr .hrTabs button');
 await expect(tabs).toHaveText(['Employés','Absences','Planification','Règles de congés','Documents et historique','Paie et coûts','Organigramme']);
 expect(await decorated(tabs)).toEqual([]);
});

test('les onglets RH n’ont plus d’icône, côté salarié',async({page})=>{
 await boot(page,'commercial');await page.evaluate(()=>ArcRouter.open('hr'));
 const tabs=page.locator('#hr .hrTabs button');
 await expect(tabs.first()).toHaveText('Ma fiche');
 expect(await decorated(tabs)).toEqual([]);
});

test('les rubriques des fenêtres Configuration et Notifications sont en texte seul',async({page})=>{
 await boot(page);
 await page.locator('#arcSettings').click();
 const settings=page.locator('#arcSettingsDialog [role=tab]');await expect(settings.first()).toHaveText('Langue');
 expect(await decorated(settings)).toEqual([]);
 await page.keyboard.press('Escape');
 await page.evaluate(()=>GamaOperations.open('notifications'));
 const notify=page.locator('#arcNotifyDialog [role=tab]');await expect(notify.first()).toContainText('Toutes les alertes');
 expect(await decorated(notify)).toEqual([]);
});

test('Importer des données : les modes et les types de données sont en texte seul',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('reports'));
 const modes=page.locator('.gamaExcelModes button');
 await expect(modes).toHaveText(['Données Excel','Photos des produits','Optimiser les photos']);
 expect(await decorated(modes)).toEqual([]);
 const types=page.locator('.gamaExcelTypes button');
 await expect(types).toHaveText(['Produits','Clients','Fournisseurs','Tarifs clients']);
 expect(await decorated(types)).toEqual([]);
});

// «Archivés» sólo aparece cuando hay algo archivado.
test('l’onglet Archivés n’a plus d’icône',async({page})=>{
 await boot(page,'admin',{customers:[{id:'c1',name:'Ferretería Andina',active:true},{id:'c2',name:'Hierros Norte',active:false}],crm_leads:[],crm_contacts:[]});
 await page.evaluate(()=>ArcRouter.open('contacts'));
 const tabs=page.locator('#ctArchive .gamaArcTabs button');
 await expect(tabs).toHaveText(['Actifs (1)','Archivés (1)']);
 expect(await decorated(tabs)).toEqual([]);
});

test('les onglets du CRM sont traduits et en texte seul',async({page})=>{
 await boot(page,'admin',{crm_leads:[],crm_contacts:[]});await page.evaluate(()=>ArcRouter.open('crm'));
 const tabs=page.locator('#crm .crmNav:not(.crmSubNav) button');
 await expect(tabs).toHaveText(['Tableau de bord','Prospects','Opportunités','Activités','Contacts','Rapports','Objectifs']);
 expect(await decorated(tabs)).toEqual([]);
});

test('les tuiles de l’accueil et la navigation gardent leurs logos',async({page})=>{
 await boot(page);
 const tiles=page.locator('#mainmenu .gamaF2Card');
 expect(await tiles.evaluateAll(t=>t.filter(x=>!x.querySelector('svg')).map(x=>x.textContent.trim()))).toEqual([]);
 expect(await page.locator('.arcSidebar .arcNavLink').evaluateAll(l=>l.filter(x=>x.offsetParent&&!x.querySelector('svg')).map(x=>x.textContent.trim()))).toEqual([]);
 // Y la cabecera de un módulo muestra el suyo, sin emoji en el título.
 await page.evaluate(()=>ArcRouter.open('hr'));
 await expect(page.locator('#hr .gamaStdIcon svg')).toHaveCount(1);await expect(page.locator('#hr .gamaStdText h2')).toHaveText('Ressources humaines');
});
