const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
// Reglas operativas en el doble: la fila única con su versión, y el update
// condicionado a esa versión como en PostgREST.
const policies=`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old(),from=c.from;c.from=t=>t!=='erp_policies'?from(t):{update:data=>{const q={eqs:{},eq:(k,v)=>{q.eqs[k]=v;return q},select:()=>q,maybeSingle:async()=>{window.__policySave={data,eqs:q.eqs};const row=window.__DB.erp_policies[0];if(q.eqs.version!==row.version)return {data:null,error:null};Object.assign(row,data,{version:row.version+1});return {data:{...row},error:null}}};return q}};return c}})();`;
async function boot(page,role='admin'){
 await page.addInitScript(({role})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Settings QA'}));localStorage.setItem('gama_language_v1','fr');
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],invoices:[],erp_policies:[{id:true,version:3,timezone:'America/Guayaquil',purchase_approval_amount:5000,quote_discount_limit:15,minimum_margin:null,stock_adjustment_limit:null,stale_opportunity_days:30,escalation_days:3,stock_visibility:'exact'}]};
 },{role});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+policies}));
 await page.goto('/index.html');
 await expect(page.locator('#mainmenu [data-gama-module="products"],#mainmenu [data-gama-module="quotes"]').first()).toBeAttached();
}
const dialog=page=>page.locator('#arcSettingsDialog');
const tabs=page=>dialog(page).locator('[role=tab]');

test('la rueda está en la barra superior, junto a la campana, y la configuración ya no es un módulo',async({page})=>{
 await boot(page);
 const bell=page.locator('.arcTopbar #arcNotify'),gear=page.locator('.arcTopbar #arcSettings');
 await expect(gear).toBeVisible();await expect(gear).toHaveAttribute('aria-label','Configuration');await expect(gear).toHaveAttribute('aria-haspopup','dialog');
 // Mismo botón que la campana, justo a su derecha.
 expect(await gear.getAttribute('class')).toBe(await bell.getAttribute('class'));
 const [b,g]=[await bell.boundingBox(),await gear.boundingBox()];expect(Math.abs(b.y-g.y)).toBeLessThan(1);expect(g.x).toBeGreaterThan(b.x);
 await expect(page.locator('#mainmenu [data-gama-module="settings"]')).toHaveCount(0);
 await expect(page.locator('.arcSidebar [data-gama-module="settings"]')).toHaveCount(0);
 // Se sigue abriendo por su nombre: búsqueda, enlaces antiguos, el router.
 await page.evaluate(()=>ArcRouter.open('settings'));await expect(dialog(page)).toBeVisible();
});

test('el administrador ve todos los apartados en el menú lateral, cada uno con su contenido',async({page})=>{
 await boot(page);await page.locator('#arcSettings').click();
 await expect(dialog(page)).toBeVisible();await expect(dialog(page).locator('h2')).toHaveText('Configuration');
 await expect(tabs(page)).toHaveText(['Langue','Informations sur l\'entreprise','Identité des documents','Réglages fiscaux','Facturation SRI','Références des documents','Règles opérationnelles','Automatisations et exceptions','Importer des données','Sauvegardes','Utilisateurs','Paramètres d’accès','Agent Coco','Sécurité de mon compte']);
 await expect(dialog(page).locator('[role=tablist]')).toHaveAttribute('aria-orientation','vertical');
 // Se abre en el idioma, con el foco en su pestaña.
 await expect(page.locator('#cfgTab-language')).toHaveAttribute('aria-selected','true');await expect(page.locator('#cfgTab-language')).toBeFocused();
 await expect(page.locator('#cfgPane-language #gamaLanguagePicker')).toBeVisible();
 // Nada se pide al servidor para el idioma: la ficha se carga al pedirla.
 await expect(page.locator('#coForm')).toHaveCount(0);
 const cards=async()=>dialog(page).locator('[data-co-section]').evaluateAll(els=>els.filter(e=>e.offsetParent).map(e=>e.dataset.coSection));
 await page.locator('#cfgTab-company').click();await expect(page.locator('#co_legal_name')).toBeVisible();
 expect(await cards()).toEqual(['company','company']);
 await page.locator('#cfgTab-identity').click();await expect(page.locator('#coLogo')).toBeVisible();await expect(page.locator('#co_legal_name')).toBeHidden();
 expect(await cards()).toEqual(['identity','identity']);
 await page.locator('#cfgTab-fiscal').click();await expect(page.locator('#coFiscalBody')).toBeVisible();
 expect(await cards()).toEqual(['fiscal']);
 // Un único formulario y un único «Enregistrer» en los tres apartados de la empresa.
 await expect(page.locator('#coSave')).toBeVisible();await expect(page.locator('#coForm')).toHaveCount(1);
 await page.locator('#cfgTab-security').click();await expect(page.locator('#cfgSecurity')).toContainText('Ajouter un authentificateur');
 await expect(page.locator('#cfgPane-company')).toBeHidden();
 // La barra de botones de la antigua página no vuelve.
 await expect(dialog(page).locator('[data-controls-bar]')).toHaveCount(0);await expect(page.locator('section#settings')).toHaveCount(0);
});

test('teclado: flechas, Inicio y Fin recorren el menú; Escape cierra y devuelve el foco a la rueda',async({page})=>{
 await boot(page);await page.locator('#arcSettings').click();await expect(page.locator('#cfgTab-language')).toBeFocused();
 await page.keyboard.press('ArrowDown');await expect(page.locator('#cfgTab-company')).toBeFocused();await expect(page.locator('#cfgTab-company')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('#cfgPane-company')).toBeVisible();await expect(page.locator('#cfgPane-language')).toBeHidden();
 await page.keyboard.press('End');await expect(page.locator('#cfgTab-security')).toBeFocused();
 await page.keyboard.press('ArrowDown');await expect(page.locator('#cfgTab-language')).toBeFocused();
 await page.keyboard.press('ArrowUp');await expect(page.locator('#cfgTab-security')).toBeFocused();
 await page.keyboard.press('Home');await expect(page.locator('#cfgTab-language')).toBeFocused();
 // Sólo la pestaña elegida entra en el orden de tabulación.
 expect(await tabs(page).evaluateAll(t=>t.map(x=>x.tabIndex))).toEqual([0,...Array(13).fill(-1)]);
 await expect(page.locator('#cfgTab-language')).toHaveAttribute('aria-controls','cfgPane-language');
 await expect(page.locator('#cfgPane-language')).toHaveAttribute('aria-labelledby','cfgTab-language');
 await page.keyboard.press('Escape');await expect(dialog(page)).toHaveCount(0);await expect(page.locator('#arcSettings')).toBeFocused();
 // El aspa también cierra.
 await page.locator('#arcSettings').click();await dialog(page).locator('[data-side-close]').click();await expect(dialog(page)).toHaveCount(0);
});

test('abrir en un apartado, y un dato obligatorio de otro apartado se enseña al guardar',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaSettings.open('fiscal'));
 await expect(page.locator('#cfgTab-fiscal')).toHaveAttribute('aria-selected','true');await expect(page.locator('#coFiscalBody')).toBeVisible();
 // Con la ventana abierta, pedir otro apartado cambia de apartado.
 await page.evaluate(()=>GamaSettings.open('references'));await expect(page.locator('#cfgTab-references')).toHaveAttribute('aria-selected','true');
 await expect(dialog(page)).toHaveCount(1);
 await page.locator('#cfgTab-company').click();await page.locator('#co_legal_name').fill('');
 await page.locator('#cfgTab-fiscal').click();await expect(page.locator('#co_legal_name')).toBeHidden();
 await page.locator('#coSave').click();
 // El navegador no puede señalar un campo escondido: la ventana va antes a su apartado.
 await expect(page.locator('#cfgTab-company')).toHaveAttribute('aria-selected','true');await expect(page.locator('#co_legal_name')).toBeVisible();
 await expect(page.locator('#co_legal_name')).toBeFocused();
});

// Un botón que lleva a otra pantalla (aquí «Ouvrir Comptabilité») cierra la ventana: si no, la
// pantalla se abriría detrás, tapada.
test('ir a otra pantalla desde la ventana la cierra, para que se vea lo abierto',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaSettings.open('fiscal'));await expect(page.locator('#coAccounting')).toBeVisible();
 await page.evaluate(()=>{window.GamaAccounting=Object.assign(window.GamaAccounting||{},{open:()=>ArcRouter.show('products')})});
 await page.locator('#coAccounting').click();
 await expect(dialog(page)).toHaveCount(0);await expect(page.locator('#products')).toBeVisible();
});

test('reglas operativas: se editan en su apartado y se guardan con su versión',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaSettings.open('policies'));
 const pane=page.locator('#cfgPolicies');await expect(pane.locator('h3')).toHaveText('Règles opérationnelles');
 await expect(pane.locator('[name=timezone]')).toHaveValue('America/Guayaquil');await expect(pane.locator('[name=minimum_margin]')).toHaveValue('');
 await pane.locator('[name=minimum_margin]').fill('12.5');await pane.locator('[name=purchase_approval_amount]').fill('');await pane.locator('[name=stock_visibility]').selectOption('availability');
 await pane.getByRole('button',{name:'Enregistrer les règles'}).click();await expect(pane.locator('[role=status]')).toHaveText('Règles enregistrées.');
 const saved=await page.evaluate(()=>window.__policySave);
 expect(saved.eqs).toEqual({id:true,version:3});expect(saved.data).toMatchObject({minimum_margin:12.5,purchase_approval_amount:null,stock_visibility:'availability',timezone:'America/Guayaquil'});
 // Un segundo guardado usa la versión nueva, no la leída al abrir.
 await pane.locator('[name=escalation_days]').fill('5');await pane.getByRole('button',{name:'Enregistrer les règles'}).click();await expect(pane.locator('[role=status]')).toHaveText('Règles enregistrées.');
 expect((await page.evaluate(()=>window.__policySave)).eqs.version).toBe(4);
 // Si otro administrador guardó antes, se dice y no se pierde lo escrito.
 await page.evaluate(()=>{window.__DB.erp_policies[0].version=9});
 await pane.locator('[name=escalation_days]').fill('7');await pane.getByRole('button',{name:'Enregistrer les règles'}).click();
 await expect(pane.locator('[role=alert]')).toContainText('Un autre administrateur');await expect(pane.locator('[name=escalation_days]')).toHaveValue('7');
 await pane.getByRole('button',{name:'Recharger'}).click();await expect(pane.locator('[name=escalation_days]')).toHaveValue('5');
});

test('sin ser administrador: idioma y seguridad de la cuenta, nada de la empresa',async({page})=>{
 await boot(page,'commercial');await page.locator('#arcSettings').click();
 await expect(tabs(page)).toHaveText(['Langue','Importer des données','Sécurité de mon compte']);
 for(const id of ['company','identity','fiscal','references','policies','users'])await expect(page.locator('#cfgTab-'+id)).toHaveCount(0);
 await expect(page.locator('#coCompany,#cfgReferences,#cfgPolicies')).toHaveCount(0);
 // Pedir un apartado de administración abre el idioma.
 await page.keyboard.press('Escape');await page.evaluate(()=>GamaSettings.open('policies'));await expect(page.locator('#cfgTab-language')).toHaveAttribute('aria-selected','true');
 await page.locator('#cfgTab-security').click();await expect(page.locator('#cfgSecurity [data-enroll]')).toBeVisible();await expect(page.locator('#cfgSecurity [role=alert]')).toBeEmpty();
 // Renovar el token no cierra la ventana; dejar de ser administrador cierra la del administrador.
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'TOKEN_REFRESHED'}})));await expect(dialog(page)).toBeVisible();
});

test('la ventana del administrador se cierra si la cuenta deja de serlo',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaSettings.open('company'));await expect(page.locator('#co_legal_name')).toBeVisible();
 await page.evaluate(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'commercial'}));window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'USER_UPDATED'}}))});
 await expect(dialog(page)).toHaveCount(0);await expect(page.locator('#coForm')).toHaveCount(0);
});

test('teléfono: la ventana ocupa la pantalla y el menú se pone en fila, sin desbordar',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.locator('#arcSettings').click();
 const box=await dialog(page).boundingBox();expect(box).toMatchObject({x:0,y:0,width:390,height:844});
 const side=page.locator('.arcSideNav');
 // Los apartados en una fila que se desliza; la página no se desborda.
 const first=await page.locator('#cfgTab-language').boundingBox(),second=await page.locator('#cfgTab-company').boundingBox();
 expect(Math.abs(first.y-second.y)).toBeLessThan(1);
 expect(await side.evaluate(e=>e.scrollWidth>e.clientWidth&&getComputedStyle(e).overflowX)).toBe('auto');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.keyboard.press('End');await expect(page.locator('#cfgTab-security')).toBeInViewport();
 await page.keyboard.press('ArrowLeft');await expect(page.locator('#cfgTab-agent-coco')).toBeFocused();
 await expect(page.locator('#cfgAgentCoco button')).toHaveText('Agent Coco');
 await page.locator('#cfgTab-policies').click();
 await expect(page.locator('#cfgPolicies [name=timezone]')).toBeVisible();
 expect(await page.locator('.arcSidePanes').evaluate(e=>e.scrollWidth<=e.clientWidth)).toBe(true);
 for(const tab of ['company','identity','fiscal','references']){await page.locator('#cfgTab-'+tab).click();await page.waitForTimeout(50);expect(await page.locator('.arcSidePanes').evaluate(e=>e.scrollWidth<=e.clientWidth),tab).toBe(true)}
 await page.screenshot({path:test.info().outputPath('settings-window-mobile.png')});
});

for(const width of [390,1280])test('import, backup and access move into Configuration with compatible links at '+width,async({page})=>{
 await page.setViewportSize({width,height:900});await boot(page);
 for(const id of ['reports','backup','access-settings'])await expect(page.locator('#mainmenu [data-gama-module="'+id+'"],.arcSidebar [data-gama-module="'+id+'"]')).toHaveCount(0);
 await page.evaluate(()=>ArcRouter.open('reports'));await expect(dialog(page)).toBeVisible();await expect(page.locator('#cfgTab-reports')).toHaveAttribute('aria-selected','true');await expect(page.locator('#gamaExcelFile')).toBeAttached();await expect(page.locator('#reports [data-gama-standard-header]')).toHaveCount(0);
 await page.locator('#gamaExcelFile').setInputFiles({name:'keep.csv',mimeType:'text/csv',buffer:Buffer.from('Nombre,Referencia\nProducto,TEST-1')});
 await page.locator('#cfgTab-backup').click();await expect(page.locator('#recoveryExport')).toBeVisible();await expect(page.locator('#recoveryFile')).toBeVisible();await expect(page.locator('#backup [data-gama-standard-header]')).toHaveCount(0);
 await page.evaluate(()=>ArcRouter.show('access-settings'));await expect(page.locator('#cfgTab-access-settings')).toHaveAttribute('aria-selected','true');await expect(page.locator('#access-settings [data-mod=products]')).toBeVisible();await expect(page.locator('#access-settings [data-gama-standard-header]')).toHaveCount(0);
 await page.locator('#cfgTab-reports').click();expect(await page.locator('#gamaExcelFile').evaluate(e=>e.files[0]?.name)).toBe('keep.csv');
 await expect(dialog(page)).toHaveCount(1);expect(await dialog(page).locator('.arcSidePanes').evaluate(e=>e.scrollWidth<=e.clientWidth+1)).toBe(true);
 await dialog(page).locator('[data-side-close]').click();await expect(dialog(page)).toHaveCount(0);for(const id of ['reports','backup','access-settings'])await expect(page.locator('#'+id)).toBeHidden();
 await page.evaluate(()=>ArcRouter.open('backup'));await expect(page.locator('#cfgTab-backup')).toHaveAttribute('aria-selected','true');await expect(page.locator('#recoveryExport')).toBeVisible();await page.locator('#cfgTab-reports').click();expect(await page.locator('#gamaExcelFile').evaluate(e=>e.files[0]?.name)).toBe('keep.csv');
 await page.screenshot({path:test.info().outputPath('configuration-admin-tabs-'+width+'.png')});
});

test('backup exports and verifies files from its Configuration tab',async({page})=>{
 await boot(page);await page.evaluate(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>fn==='gama_recovery_export'?{data:{format:'architect-application-export',version:1,created_at:'2026-10-03T10:00:00Z',tables:{products:[]},counts:{products:0},storage_objects:[]}}:c.rpc(fn,args)}}});
 await page.evaluate(()=>ArcRouter.open('backup'));const downloaded=page.waitForEvent('download');await page.locator('#recoveryExport').click();const d=await downloaded;const bytes=fs.readFileSync(await d.path());await expect(page.locator('#recoveryStatus')).toContainText('Export vérifié');
 await page.locator('#recoveryFile').setInputFiles({name:'test.json',mimeType:'application/json',buffer:bytes});await page.locator('#recoveryVerify').click();await expect(page.locator('#recoveryStatus')).toContainText('Intégrité vérifiée');
});

for(const width of [390,1280])test('users work inside Configuration, refresh live and keep compatible links at '+width,async({page})=>{
 await page.setViewportSize({width,height:900});await boot(page);
 await page.evaluate(()=>{__DB.profiles=[{id:'test-admin-uid',full_name:'Admin QA',email:'admin@example.com',role:'administrador',active:true},{id:'staff',full_name:'Staff QA',email:'staff@example.com',role:'comercial',active:false}];GamaCloud.subscribe=(table,changed)=>{if(table==='profiles')window.__profileChanged=changed;return {unsubscribe(){}}}});
 await expect(page.locator('#mainmenu [data-gama-module=users],.arcSidebar [data-gama-module=users]')).toHaveCount(0);
 await page.locator('#arcSettings').click();await page.locator('#cfgTab-users').click();
 await expect(page.locator('#cfgPane-users #users')).toBeVisible();await expect(page.locator('#cuRows tr')).toHaveCount(2);
 await expect(page.locator('#users [data-invite-user]')).toBeVisible();await expect(page.locator('#users [data-gama-standard-header]')).toHaveCount(0);
 await page.locator('[data-cu-toggle=staff]').click();await expect(page.locator('#cuRows tr').filter({hasText:'Staff QA'})).toContainText('Actif');
 await page.evaluate(()=>{__DB.profiles.find(p=>p.id==='staff').full_name='Staff actualizado';window.__profileChanged()});
 await expect(page.locator('#cuRows')).toContainText('Staff actualizado');
 await page.locator('#cfgTab-language').click();await expect(page.locator('#users')).toBeHidden();
 await page.evaluate(()=>{__DB.profiles.find(p=>p.id==='staff').full_name='Staff al volver';window.__profileChanged()});
 await page.evaluate(()=>ArcRouter.show('users'));await expect(page.locator('#cfgTab-users')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('#cuRows')).toContainText('Staff al volver');
 await expect(page.locator('#users')).toHaveCount(1);await expect(page.locator('#users [data-invite-user]')).toHaveCount(1);
 expect(await dialog(page).locator('.arcSidePanes').evaluate(e=>e.scrollWidth<=e.clientWidth+1)).toBe(true);
 await page.screenshot({path:test.info().outputPath('configuration-users-'+width+'.png')});
 await dialog(page).locator('[data-side-close]').click();await expect(dialog(page)).toHaveCount(0);await expect(page.locator('#users')).toBeHidden();
 await page.evaluate(()=>ArcRouter.open('users'));await expect(page.locator('#cfgTab-users')).toHaveAttribute('aria-selected','true');await expect(page.locator('#cuRows')).toContainText('Staff al volver');
 await page.evaluate(()=>{__DB.app_modules=[{id:'users',enabled:false}];return GamaModules.load()});
 await expect(page.locator('#cfgTab-users')).toHaveCount(0);await expect(page.locator('#cfgTab-language')).toHaveAttribute('aria-selected','true');
 await page.evaluate(()=>ArcRouter.open('users'));await expect(page.locator('#cfgTab-users')).toHaveCount(0);
});

test('Configuration honours tab permissions and module deactivation',async({page})=>{
 await boot(page,'commercial');await page.evaluate(()=>ArcRouter.open('reports'));await expect(page.locator('#cfgTab-reports')).toHaveAttribute('aria-selected','true');await expect(page.locator('#cfgTab-backup,#cfgTab-users,#cfgTab-access-settings')).toHaveCount(0);await page.evaluate(()=>{GamaSettings.open('backup');GamaSettings.open('users');ArcRouter.open('users');GamaSettings.open('access-settings')});await expect(page.locator('#cfgTab-reports')).toHaveAttribute('aria-selected','true');await expect(page.locator('#cuRows')).toHaveCount(0);
 await page.evaluate(()=>{__DB.app_modules=[{id:'reports',enabled:false}];return GamaModules.load()});await expect(page.locator('#cfgTab-reports')).toHaveCount(0);await expect(page.locator('#cfgTab-language')).toHaveAttribute('aria-selected','true');
 await page.evaluate(()=>ArcRouter.open('reports'));await expect(page.locator('#cfgTab-reports')).toHaveCount(0);
 await dialog(page).locator('[data-side-close]').click();await expect(dialog(page)).toHaveCount(0);await page.locator('#arcSettings').click();await expect(page.locator('#cfgTab-reports')).toHaveCount(0);
 await page.evaluate(()=>{__DB.app_modules=[{id:'reports',enabled:true}];return GamaModules.load()});await page.locator('#cfgTab-reports').click();await expect(page.locator('#gamaExcelFile')).toBeAttached();await expect(page.locator('#reports')).toBeVisible();
});
