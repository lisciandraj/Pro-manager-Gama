const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const path=require('node:path');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');

const VERSION='1234567890abcdef1234567890abcdef12345678';
const CLOUD=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8')+
 '\nObject.defineProperty(window.GamaCloud,"verifiedProfile",{get:()=>window.__verifiedProfile,configurable:true});';

// Load the real application shell, environment bootstrap and translations.
// Only the server-verified profile and the release destinations are fixtures.
async function boot(page,{admin=true,environment='development',packaged=true}={}){
 await isolateLocalPage(page);
 await page.addInitScript(({admin,environment,packaged,version})=>{
  const prefix=packaged?'coco:'+environment+':':'';
  localStorage.setItem(prefix+'gama_session_v1',JSON.stringify({role:'admin',name:'Browser session'}));
  localStorage.setItem(prefix+'gama_language_v1','fr');
  if(packaged)window.CocoEnvironmentConfig={environment,version,supabaseUrl:'https://fixture.supabase.co',publishableKey:'public-fixture-key',productionUrl:'/production/',developmentUrl:'/development/'};
  window.__verifiedProfile=admin?{role:'administrador',active:true}:null;
 },{admin,environment,packaged,version:VERSION});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:CLOUD}));
 await page.route('**/production/',r=>r.fulfill({contentType:'text/html',body:'<h1>Production release</h1>'}));
 await page.route('**/development/',r=>r.fulfill({contentType:'text/html',body:'<h1>Development release</h1>'}));
 await page.goto('/index.html');
 await expect(page.locator('.arcSidebar .arcNavLink[data-arc-home]')).toBeAttached();
}

test('the desktop sidebar shows the active release and opens production with the keyboard',async({page})=>{
 await page.setViewportSize({width:1440,height:900});
 await boot(page);
 const group=page.locator('#cocoAppMenu').getByRole('group',{name:'Environnements de travail'});
 await expect(group.locator('strong')).toHaveText('Développement');
 await expect(group.locator('small')).toHaveAttribute('title',VERSION);
 const link=group.getByRole('link',{name:'Passer en production'});
 await expect(link).toHaveAttribute('href','http://127.0.0.1:4173/production/');
 await expect(page.locator('#mainmenu [data-coco-environment]')).toHaveCount(0);
 await expect(group.getByRole('link')).toHaveCount(1);
 await link.focus();
 await page.keyboard.press('Enter');
 await expect(page).toHaveURL(/\/production\/$/);
 await expect(page.getByRole('heading',{name:'Production release'})).toBeVisible();
});

test('the mobile drawer offers development in a full-sized control',async({page})=>{
 await page.setViewportSize({width:390,height:844});
 await boot(page,{environment:'production'});
 const more=page.locator('[data-coco-mobile=more]');
 const drawer=page.locator('#cocoAppMenu');
 const link=drawer.getByRole('link',{name:'Passer en développement'});
 await expect(drawer).toHaveJSProperty('inert',true);
 await more.click();
 await expect(drawer).toHaveJSProperty('inert',false);
 for(const width of [390,320]){
  await page.setViewportSize({width,height:844});
  await expect(link).toBeInViewport();
  expect((await link.boundingBox()).height).toBeGreaterThanOrEqual(44);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBe(0);
 }
 await link.click();
 await expect(page).toHaveURL(/\/development\/$/);
 await expect(page.getByRole('heading',{name:'Development release'})).toBeVisible();
});

test('only active verified administrators see the development destination',async({page})=>{
 await page.setViewportSize({width:1440,height:900});
 await boot(page,{admin:false,environment:'production'});
 const group=page.getByRole('group',{name:'Environnements de travail'});
 await expect(group.locator('strong')).toHaveText('Production');
 await expect(group.getByRole('link')).toHaveCount(0);
 await page.evaluate(()=>{window.__verifiedProfile={role:'administrador',active:true};window.dispatchEvent(new CustomEvent('gama:profile-ready'))});
 await expect(group.getByRole('link',{name:'Passer en développement'})).toBeVisible();
 await page.evaluate(()=>{window.__verifiedProfile.active=false;window.dispatchEvent(new CustomEvent('coco:environment-access-change'))});
 await expect(group.getByRole('link')).toHaveCount(0);
 await expect(group.locator('.arcEnvironmentLink')).not.toHaveAttribute('href');
});

test('the language changes without duplicating the environment control',async({page})=>{
 await page.setViewportSize({width:1440,height:900});
 await boot(page,{environment:'production'});
 await page.locator('#arcLangSelect').selectOption('en');
 await expect(page.getByRole('group',{name:'Work environments'}).getByRole('link',{name:'Switch to development'})).toBeVisible();
 await page.locator('#arcLangSelect').selectOption('es');
 await expect(page.getByRole('group',{name:'Entornos de trabajo'}).getByRole('link',{name:'Cambiar a desarrollo'})).toBeVisible();
 await expect(page.locator('.arcEnvironment')).toHaveCount(1);
});

test('an unpackaged build has no links to sibling releases',async({page})=>{
 await boot(page,{packaged:false});
 await expect(page.locator('.arcEnvironment')).toBeHidden();
 await expect(page.locator('.arcEnvironmentLink')).not.toHaveAttribute('href');
});
