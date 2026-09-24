const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page,role='admin',language='es'){
 await page.addInitScript(({role,language})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Productos'}));
  if(!localStorage.getItem('gama_language_v1'))localStorage.setItem('gama_language_v1',language);
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[]};
 },{role,language});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaI18n&&window.GamaOpenSettings);
 await expect(page.locator('#mainmenu [data-gama-module="products"]')).toBeAttached();
}
test('three accessible flags switch live, persist, and preserve form and business values',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await page.locator('#arcSettings').click();
 await expect(page.locator('#arcSettingsDialog #gamaLanguagePicker button')).toHaveCount(3);
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await page.keyboard.press('Escape');await expect(page.locator('#arcSettingsDialog')).toHaveCount(0);
 await expect(page.locator('#mainmenu [data-gama-module="products"]')).toContainText('Produits');
 await expect(page.locator('html')).toHaveAttribute('lang','fr');
 await expect(page.locator('#gamaACLUser b')).toHaveText('Productos');
 await page.evaluate(()=>GamaUI.backToMenu());
 await page.locator('#mainmenu [data-gama-module="products"]').click();
 const input=page.locator('#pName');
 await input.fill('Productos client entry');
 await page.evaluate(()=>{const p=document.createElement('p');p.id='qaBusiness';p.textContent='Guardar';document.querySelector('#products').appendChild(p)});
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(input).toHaveValue('Productos client entry');await expect(page.locator('#qaBusiness')).toHaveText('Guardar');
 await expect(page.locator('#products .gamaStdText h2')).toContainText('Products');
 expect(await page.evaluate(()=>localStorage.getItem('gama_language_v1'))).toBe('en');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.screenshot({path:'test-results/i18n-mobile-en.png',fullPage:false});
 await page.evaluate(()=>GamaI18n.setLanguage('es'));
 await expect(page.locator('#products .gamaStdText h2')).toContainText('Productos');
 await expect(input).toHaveValue('Productos client entry');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));await page.reload();
 await expect(page.locator('html')).toHaveAttribute('lang','en');
 await expect(page.locator('#mainmenu [data-gama-module="products"]')).toContainText('Products');
});
test('saved French loads lazily rendered sales forms, preserving select values and access rules',async({page})=>{
 await boot(page,'commercial','fr');
 await expect(page.locator('#mainmenu [data-gama-module="quotes"]')).toBeVisible();
 await expect(page.locator('#mainmenu [data-gama-module="sales-orders"]')).toBeHidden();
 await expect(page.locator('#mainmenu [data-gama-module="users"]')).toBeHidden();
 await page.locator('#mainmenu [data-gama-module="quotes"]').click();
 await page.locator('#gqOrdersTab').click();
 await expect(page.locator('#sales-orders .gqModuleTabs')).toContainText('Factures');
 await expect(page.locator('.gsTabs')).toContainText('Toutes les commandes');
 await page.locator('#gsNew').click();
 await expect(page.locator('dialog')).toContainText('Adresse de livraison');
 const source=page.locator('#gsSource');await expect(source).toHaveValue('manual');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(source).toHaveValue('manual');await expect(page.locator('dialog')).toContainText('Delivery address');
 await expect(page.locator('#mainmenu [data-gama-module="users"]')).toBeHidden();
});
test('static options retain original values, user product options are not translated',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{
 const host=document.createElement('div');host.id='qaOptions';
 host.innerHTML='<select id="qaState"><option data-gi-live>Planificada</option><option data-gi-live>Entregada</option></select><select id="qaProduct"><option value="p1">Productos</option></select>';
 document.body.appendChild(host);
 });
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(page.locator('#qaState')).toHaveValue('Planificada');
 await expect(page.locator('#qaState option').first()).toHaveText('Planned');
 await expect(page.locator('#qaProduct option')).toHaveText('Productos');
 await page.locator('#qaState').selectOption('Entregada');
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#qaState')).toHaveValue('Entregada');await expect(page.locator('#qaState option').last()).toHaveText('Livrée');
});
test('numerical messages translate without changing numbers and invalid preferences fall back to Spanish',async({page})=>{
 await boot(page,'admin','bogus');
 await expect(page.locator('html')).toHaveAttribute('lang','es');
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 expect(await page.evaluate(()=>GamaI18n.t('Página 12'))).toBe('Page 12');
 expect(await page.evaluate(()=>GamaI18n.t('🔎 Buscar'))).toBe('🔎 Rechercher');
 await page.evaluate(()=>gamaToast('Acceso denegado para este perfil.'));
 await expect(page.locator('.gamaToastTexto').last()).toHaveText('Accès refusé pour ce profil.');
});
test('desktop sidebar visibility uses stable module identifiers across languages',async({page})=>{
 await page.setViewportSize({width:1500,height:950});await boot(page,'client','fr');
 await expect(page.locator('#mainmenu [data-gama-module="quotes"]')).toBeVisible();
 await expect(page.locator('#mainmenu [data-gama-module="products"]')).toBeHidden();
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(page.locator('#mainmenu [data-gama-module="quotes"]')).toBeVisible();
 await expect(page.locator('#mainmenu [data-gama-module="products"]')).toBeHidden();
 await expect(page.locator('.arcNavLink[data-gama-module="quotes"]')).toBeVisible();
 await expect(page.locator('.arcNavLink[data-gama-module="quotes"]')).toContainText('Quotes');
});
test('settings exposes language to all roles without exposing module switches or header flags',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'client');
 await expect(page.locator('header #gamaLanguagePicker')).toHaveCount(0);
 await page.locator('#arcSettings').click();
 const settings=page.locator('#arcSettingsDialog');
 await expect(settings.locator('#gamaLanguagePicker')).toBeVisible();
 await expect(settings.locator('input[data-mod],button[data-mod]')).toHaveCount(0);
 await settings.locator('[data-language="fr"]').click();
 await expect(settings.locator('h3').first()).toHaveText('Langue de l’application');
 await expect(settings.locator('[data-language="fr"]')).toHaveAttribute('aria-pressed','true');
 // La ventana sigue al idioma elegido dentro de ella, también en lo que sólo se oye.
 await expect(settings.locator('h2')).toHaveText('Configuration');
 await expect(settings.locator('[data-side-close]')).toHaveAttribute('aria-label','Fermer');
 await expect(page.locator('#arcSettings')).toHaveAttribute('aria-label','Configuration');
 expect(await page.evaluate(()=>document.querySelector('header.gamaHeader').getBoundingClientRect().height)).toBeLessThan(168);
 await page.keyboard.press('Escape');
 await expect(page.locator('#gamaLanguagePicker')).toHaveCount(0);
 await expect(page.locator('#mainmenu [data-gama-module="settings"]')).toHaveCount(0);
 await page.reload();await expect(page.locator('html')).toHaveAttribute('lang','fr');
});
test('access settings is separate and restricted, personal configuration has no switches even for admin',async({page})=>{
 await boot(page);await page.locator('#arcSettings').click();
 await expect(page.locator('#arcSettingsDialog [role=tab]')).toHaveCount(7);
 await expect(page.locator('#arcSettingsDialog input[data-mod],#arcSettingsDialog button[data-mod]')).toHaveCount(0);
 await page.keyboard.press('Escape');
 await page.locator('#mainmenu [data-gama-module="access-settings"]').click();
 await expect(page.locator('#access-settings button[data-mod="products"]')).toBeVisible();
 await expect(page.locator('#access-settings input[data-mod]')).toHaveCount(0);
 await expect(page.locator('#access-settings button[data-mod="access-settings"]')).toBeDisabled();
 await expect(page.locator('#access-settings button[data-mod="settings"]')).toBeDisabled();
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#access-settings button[data-mod="products"]')).toHaveText('Désinstaller');
 await page.locator('#access-settings button[data-mod="products"]').scrollIntoViewIfNeeded();
 await page.screenshot({path:'test-results/module-actions-desktop.png'});
 await page.setViewportSize({width:390,height:844});
 await page.locator('#access-settings button[data-mod="products"]').scrollIntoViewIfNeeded();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.screenshot({path:'test-results/module-actions-mobile.png'});
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(page.locator('#access-settings button[data-mod="products"]')).toHaveText('Uninstall');
 await expect(page.locator('#access-settings #gamaLanguagePicker')).toHaveCount(0);
});
for(const role of ['commercial','magasinier','client'])test(`access settings denied to ${role}, configuration available`,async({page})=>{
 await boot(page,role);await expect(page.locator('#mainmenu [data-gama-module="access-settings"]')).toBeHidden();
 await expect(page.locator('#arcSettings')).toBeVisible();
 await page.evaluate(()=>GamaOpenAccessSettings());await expect(page.locator('#access-settings input')).toHaveCount(0);
 await page.evaluate(()=>GamaOpenSettings());await expect(page.locator('#arcSettingsDialog #gamaLanguagePicker')).toBeVisible();
 await expect(page.locator('#arcSettingsDialog [role=tab]')).toHaveText([/Idioma/,/Seguridad de mi cuenta/]);
 await page.evaluate(()=>window.showTab('access-settings'));await expect(page.locator('#arcSettingsDialog')).toBeVisible();
 await expect(page.locator('#access-settings')).toBeHidden();
});
test('login language selector translates immediately and configuration reopens in that language',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaOpenSettings());
 await expect(page.locator('#arcSettingsDialog #gamaLanguagePicker')).toBeVisible();
 // La sesión se cierra: la ventana también, la pantalla de conexión no queda debajo.
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));
 await expect(page.locator('#arcSettingsDialog')).toHaveCount(0);
 await page.evaluate(()=>{const d=document.createElement('div');d.id='gamaCloudLogin';d.style='position:fixed;inset:0;background:white;z-index:100000';d.innerHTML='<div class="box"><h1 data-gi-live>Iniciar sesión</h1><input id="loginEmailTest" value="client@example.com"></div>';document.body.append(d)});
 await page.locator('#gamaCloudLogin [data-language="fr"]').click();
 await expect(page.locator('#gamaCloudLogin h1')).toHaveText('Se connecter');
 await expect(page.locator('#loginEmailTest')).toHaveValue('client@example.com');
 await expect(page.locator('header #gamaLanguagePicker')).toHaveCount(0);
 await page.evaluate(()=>document.getElementById('gamaCloudLogin').remove());
 await page.evaluate(()=>GamaOpenSettings());
 await expect(page.locator('#arcSettingsDialog #gamaLanguagePicker')).toBeVisible();
 await expect(page.locator('#arcSettingsDialog [data-language="fr"]')).toHaveAttribute('aria-pressed','true');
});
