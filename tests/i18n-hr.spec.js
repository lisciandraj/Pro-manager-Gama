const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
// Textos de RH que se quedaban en español con la interfaz en francés.
async function boot(page,role){
 await page.addInitScript(role=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'RH QA'}));localStorage.setItem('gama_language_v1','fr');
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[],profiles:[],
   hr_employees:[{id:'e1',full_name:'Camila Martinez',active:true}],hr_absences:[],hr_employee_private:[],hr_absence_private:[]};
 },role);
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await expect(page.locator('#mainmenu .gamaF2Card').first()).toBeVisible();
}

test('RH en français : sous-titre, indicateurs, fiche et légende du planning',async({page})=>{
 await boot(page,'admin');await page.evaluate(()=>ArcRouter.open('hr'));
 await expect(page.locator('#hr .gamaStdText p')).toHaveText('Employés, absences et calendrier de l’équipe.');
 const year=await page.evaluate(()=>new Date().getFullYear());
 await expect(page.locator('#hr .hrKpi > span')).toHaveText(['Employés actifs','Absents aujourd’hui','En attente d’approbation',`Arrêts maladie ${year}`]);
 await expect(page.locator('#hr .hrGrid h3').first()).toHaveText('Nouvel employé');
 await page.locator('#hr .hrTabs button',{hasText:'Planification'}).click();
 await expect(page.locator('#hr .hrPlanLeyenda')).toHaveText(['Congés','Maladie','Autorisation d’absence','Formation','Autre','En attente d’approbation']);
});

test('RH en français, côté salarié sans fiche : sous-titre et message entier',async({page})=>{
 await boot(page,'commercial');await page.evaluate(()=>ArcRouter.open('hr'));
 await expect(page.locator('#hr .gamaStdText p')).toHaveText('Vos données, vos jours et le calendrier de l’équipe.');
 await expect(page.locator('#hr .hrEmpty',{hasText:'Votre compte'})).toHaveText('Votre compte n’est pas encore lié à une fiche employé. Demandez à un administrateur de le lier depuis Ressources humaines → Employés.');
});

// Le texte qui suit <br> ou une case à cocher appartient à son parent : son identifiant
// de traduction ne doit pas rester sur la balise vide, sinon il n’est jamais traduit.
test('aucun identifiant de traduction sur une balise vide',()=>{
 const root=path.join(__dirname,'..');
 const files=['index.html',...fs.readdirSync(root).filter(f=>/^gama-.*\.js$/.test(f)&&!f.startsWith('gama-i18n'))];
 const bad=files.flatMap(f=>[...fs.readFileSync(path.join(root,f),'utf8').matchAll(/<(?:area|base|br|col|embed|hr|img|input|link|meta|source|track|wbr)\b[^<>]*\sdata-gi=[^<>]*>/g)].map(m=>f+': '+m[0].slice(0,90)));
 expect(bad).toEqual([]);
});

test('la case « Conserver les photos existantes » est traduite',async({page})=>{
 await boot(page,'admin');await page.evaluate(()=>ArcRouter.open('reports'));
 await page.locator('.gamaExcelModes [data-mode=photos]').click();
 await expect(page.locator('label.gamaPhotoOpt')).toHaveText('Conserver les photos existantes (sans les remplacer)');
 await expect(page.locator('#gamaPhotoKeep')).not.toBeChecked();
 await page.locator('label.gamaPhotoOpt').click();await expect(page.locator('#gamaPhotoKeep')).toBeChecked();
});
