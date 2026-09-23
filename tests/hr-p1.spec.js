const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const MOCK=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page,role='admin',extra={}){
 await page.addInitScript(({role,extra})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'HR Test'}));window.__DB={products:[],suppliers:[],customers:[],invoices:[],invoice_lines:[],profiles:[{id:'u1',full_name:'Marie',role:'almacenero',active:true},{id:'manager',full_name:'Responsable',role:'almacenero',active:true}],_session:{profile_id:role==='admin'?'admin':role==='manager'?'manager':'u1'},hr_employees:[{id:'e1',full_name:'Marie',profile_id:'u1',manager_id:'e3',active:true},{id:'e2',full_name:'Confidentiel',profile_id:'u2',active:true},{id:'e3',full_name:'Responsable',position:'Jefa de almacén',profile_id:'manager',active:true}],hr_employee_private:[{employee_id:'e1',annual_leave_days:15,salary:1500},{employee_id:'e2',annual_leave_days:20,salary:9876}],hr_absences:[],hr_absence_private:[],...extra};if(role==='manager')localStorage.setItem('gama_session_v1',JSON.stringify({role:'magasinier',name:'Manager'}))},{role,extra});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:MOCK}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>window.GamaHRP1&&window.GamaHR);await page.evaluate(()=>window.GamaHR.open());await expect(page.locator('#hr .hrTabs')).toBeVisible();await page.waitForFunction(()=>window.GamaHRP1.directory.length>0||!['admin','administrador'].includes(JSON.parse(localStorage.getItem('gama_session_v1')).role));
}
async function tab(page,id){await page.locator(`#hr [data-tab="${id}"]`).click()}
test('leave engine splits years, holidays, half days and respects Saturday schedules',async({page})=>{
 await boot(page,'admin',{hr_holidays:[{day:'2027-01-01',label:'Holiday'}],hr_absences:[{id:'a',employee_id:'e1',kind:'vacaciones',status:'aprobada',start_date:'2026-12-30',end_date:'2027-01-04',start_fraction:.5,end_fraction:1}],hr_work_patterns:[{id:'p',employee_id:'e2',effective_from:'2026-01-01',weekdays:[6],daily_hours:4}]});
 expect(await page.evaluate(()=>[GamaHRP1.used('e1',2026),GamaHRP1.used('e1',2027),GamaHRP1.days('e2','2026-09-11','2026-09-13')])).toEqual([1.5,1,1]);
});
test('monthly accrual prorates employment and adds carryover once',async({page})=>{
 await boot(page,'admin',{hr_leave_accounts:[{id:'l',employee_id:'e1',year:2026,entitlement:24,carryover:2,adjustment:-.5,accrual_mode:'monthly',active_from:'2026-02-01'}]});
 const actual=await page.evaluate(()=>GamaHRP1.entitlement('e1',2026,'2026-04-15'));expect(actual).toBeCloseTo(Math.round(24*59/365*100)/100+1.5,2);
});
test('rules form saves employee/year and working pattern',async({page})=>{
 await boot(page);await tab(page,'reglas');await page.fill('#hpWeekdays','1,2,3,4,5,6');await page.fill('#hpDailyHours','7');await page.click('#hpPatternSave');await expect.poll(()=>page.evaluate(()=>window.__DB.hr_work_patterns?.length)).toBe(1);
 await page.fill('#hpEntitlement','18');await page.fill('#hpCarryover','2');await page.fill('#hpLeaveReason','Opening approved');await page.click('#hpLeaveSave');await expect.poll(()=>page.evaluate(()=>window.__DB.hr_leave_accounts?.[0]?.entitlement)).toBe(18);expect(await page.evaluate(()=>window.__DB.hr_leave_accounts[0].carryover)).toBe(2);
});
test('half-day request captures fractions and cancellation retains row',async({page})=>{
 await boot(page,'magasinier');await tab(page,'ausencias');await page.selectOption('#hpStartFraction','0.5');await page.fill('#hrAbsFrom','2026-10-05');await page.fill('#hrAbsTo','2026-10-05');await page.click('#hrAbsAdd');await expect.poll(()=>page.evaluate(()=>window.__DB.hr_absences.length)).toBe(1);expect(await page.evaluate(()=>window.__DB.hr_absences[0].start_fraction)).toBe(.5);
 page.on('dialog',d=>d.accept('Cancelled by employee'));await page.locator('#hr [data-del]').click();await expect.poll(()=>page.evaluate(()=>window.__DB.hr_absences[0].status)).toBe('cancelada');expect(await page.evaluate(()=>window.__DB.hr_absences.length)).toBe(1);
});
test('manager can approve team requests without salary or admin controls',async({page})=>{
 await boot(page,'manager',{hr_absences:[{id:'a',employee_id:'e1',start_date:'2026-10-05',end_date:'2026-10-05',kind:'vacaciones',status:'pendiente'}]});await expect(page.locator('#hr [data-tab="permisos"]')).toHaveCount(0);await expect(page.locator('#hr [data-tab="organigrama"]')).toBeVisible();await expect(page.locator('#hr')).not.toContainText('9.876');await tab(page,'validaciones');await page.locator('[data-absence-status="aprobada"]').click();await expect.poll(()=>page.evaluate(()=>window.__DB.hr_absences[0].status)).toBe('aprobada');
});
test('multiple daily clock sessions share the scheduled hours once',async({page})=>{
 const records=[{id:'a',employee_id:'e1',started_at:'2026-09-10T13:00:00Z',ended_at:'2026-09-10T17:00:00Z',break_seconds:0,status:'approved'},{id:'b',employee_id:'e1',started_at:'2026-09-10T18:00:00Z',ended_at:'2026-09-11T00:00:00Z',break_seconds:3600,status:'pending'}];await boot(page,'admin',{hr_attendance:records});
 expect(await page.evaluate(()=>window.__DB.hr_attendance.map(a=>[GamaHRP1.hours(a),GamaHRP1.overtime(a)]))).toEqual([[4,0],[5,1]]);
});
test('payroll KPI uses validated cost once and subtracts partial payments',async({page})=>{
 const month=new Date().toISOString().slice(0,7);await boot(page,'admin',{hr_payroll:[{id:'p1',employee_id:'e1',period:month+'-01',source_ref:'SAL-1',gross:1000,net:800,employer_cost:1200,status:'validated',cost_center:'Warehouse'},{id:'p2',employee_id:'e2',period:month+'-01',source_ref:'SAL-2',gross:3000,net:2000,employer_cost:4000,status:'draft'}],hr_payroll_payments:[{id:'pay1',payroll_id:'p1',paid_on:month+'-03',amount:300,reference:'BANK-1',status:'confirmed'},{id:'pay2',payroll_id:'p1',paid_on:month+'-03',amount:200,reference:'BANK-2',status:'cancelled'}]});await tab(page,'nomina');const texts=await page.locator('.hpKpis strong').allTextContents();expect(texts.map(s=>Number(s.replace(/[^\d]/g,''))/100)).toEqual([1200,800,300,500]);
});
test('CSV import previews rows and refuses duplicate employee month before write',async({page})=>{
 await boot(page);await tab(page,'nomina');await page.locator('summary:has-text("Importar CSV")').click();const csv='employee_id,period,source_ref,gross,net,employer_cost,cost_center\ne1,2026-10-01,EXT-1,1000,800,1200,"Entrepôt, nord"';await page.setInputFiles('#hpCsvFile',{name:'payroll.csv',mimeType:'text/csv',buffer:Buffer.from(csv)});await expect(page.locator('#hpCsvPreview')).toContainText('Marie');await expect(page.locator('#hpCsvConfirm')).toBeVisible();expect(await page.evaluate(()=>GamaHRP1.parseCSV('employee_id,period,source_ref,gross,net,employer_cost,cost_center\ne1,2026-10-01,EXT-1,1000,800,1200,"Entrepôt, nord"')[0].cost_center)).toBe('Entrepôt, nord');
 await page.setInputFiles('#hpCsvFile',{name:'duplicates.csv',mimeType:'text/csv',buffer:Buffer.from(csv+'\ne1,2026-10-01,EXT-2,1000,800,1200,North')});await expect(page.locator('#hpError')).toContainText('duplicada');await expect(page.locator('#hpCsvConfirm')).toHaveCount(0);expect(await page.evaluate(()=>window.__DB.hr_payroll?.length||0)).toBe(0);
});
test('new HR interface switches French English Spanish without translating names',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'admin');await page.evaluate(()=>GamaI18n.setLanguage('fr'));await tab(page,'nomina');await expect(page.locator('#hpPayrollSave')).toContainText('Enregistrer le brouillon');await page.fill('#hpPayrollRef','Référence à conserver');await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('#hpPayrollSave')).toContainText('Save draft');await expect(page.locator('#hpPayrollRef')).toHaveValue('Référence à conserver');await page.evaluate(()=>GamaI18n.setLanguage('es'));await expect(page.locator('#hpPayrollSave')).toContainText('Guardar borrador');await page.screenshot({path:'test-results/hr-p1-mobile.png',fullPage:true});
});
test('valid CSV import writes one atomic batch after explicit confirmation',async({page})=>{
 await boot(page);await page.evaluate(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>({...await old(),from:table=>({insert:async rows=>{window.__csvWrites=(window.__csvWrites||0)+1;window.__DB[table]=rows.map((r,i)=>({id:'csv'+i,status:'draft',...r}));return {data:rows,error:null}}})})});await tab(page,'nomina');await page.locator('summary:has-text("Importar CSV")').click();await page.setInputFiles('#hpCsvFile',{name:'payroll.csv',mimeType:'text/csv',buffer:Buffer.from('employee_id,period,source_ref,gross,net,employer_cost,cost_center\ne1,2026-10-01,IMPORT-1,1000,800,1200,North\ne2,2026-10-01,IMPORT-2,1500,1200,1700,South')});await expect(page.locator('#hpCsvConfirm')).toBeVisible();expect(await page.evaluate(()=>window.__csvWrites||0)).toBe(0);await page.click('#hpCsvConfirm');await expect.poll(()=>page.evaluate(()=>window.__csvWrites)).toBe(1);expect(await page.evaluate(()=>window.__DB.hr_payroll.length)).toBe(2);
});
test('private document upload records version metadata and a scoped storage path',async({page})=>{
 await boot(page);await page.evaluate(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>({...await old(),storage:{from:bucket=>({upload:async(path,file)=>{window.__upload={bucket,path,type:file.type};return {data:{path},error:null}}})}})});await tab(page,'documentos');await page.selectOption('#hpDocEmployee','e1');await page.fill('#hpDocTitle','Contrat signé');await page.setInputFiles('#hpDocFile',{name:'contract.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.4\n%%EOF')});await page.click('#hpDocSave');await expect.poll(()=>page.evaluate(()=>window.__DB.hr_documents?.length)).toBe(1);const row=await page.evaluate(()=>window.__DB.hr_documents[0]);expect(row.employee_id).toBe('e1');expect(row.storage_path).toMatch(/^e1\/.+\.pdf$/);expect(row.title).toBe('Contrat signé');expect(await page.evaluate(()=>window.__upload.bucket)).toBe('hr-documents');
});
test('token refresh preserves HR form, while sign-out clears private state',async({page})=>{
 await boot(page);await tab(page,'nomina');await page.fill('#hpPayrollRef','Unsaved reference');await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'TOKEN_REFRESHED',session:{user:{id:'admin'}}}})));await expect(page.locator('#hpPayrollRef')).toHaveValue('Unsaved reference');await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT',session:null}})));await expect(page.locator('#hpPayrollRef')).toHaveCount(0);expect(await page.evaluate(()=>GamaHRP1.isHR)).toBe(false);
});

test('HR follows driving licences on the same record Fleet alerts on',async({page})=>{
 const soon=new Date(Date.now()+12*86400000).toISOString().slice(0,10);
 await boot(page,'admin',{fleet_drivers:[
  {id:'d1',employee_id:'e1',active:true,licence_number:'EC-1042335',licence_categories:['B'],
   licence_expiry:soon,phone:'+593 99 100 2030',vehicles:['PCA-1023']},
  {id:'d2',employee_id:null,active:true,licence_number:'EC-EXT-1'}]});
 await tab(page,'documentos');
 const hr=page.locator('#hr');
 await expect(hr).toContainText('Permisos de conducir');
 await expect(hr).toContainText('EC-1042335');
 await expect(hr).toContainText('PCA-1023');
 await expect(hr).toContainText('12 días restantes');
 // Lo que caduca dentro del mes se marca; el conductor externo se cuenta aparte.
 await expect(hr.locator('.hpSoon')).toHaveCount(1);
 await expect(hr).toContainText('1 conductores externos');

 // Elegir un empleado trae lo ya registrado, para corregir sin volver a teclear.
 await expect(page.locator('#hpLicNumber')).toHaveValue('EC-1042335');
 await expect(page.locator('[data-hp-cat][value="B"]')).toBeChecked();

 // RRHH renueva el permiso: escribe en la misma ficha, no crea una segunda.
 await page.fill('#hpLicExpiry','2030-01-01');
 await page.locator('[data-hp-cat][value="C"]').check();
 await page.locator('#hpLicSave').click();
 await expect.poll(()=>page.evaluate(()=>window.__DB.fleet_drivers.length)).toBe(2);
 expect(await page.evaluate(()=>window.__DB.fleet_drivers[0])).toMatchObject(
  {id:'d1',employee_id:'e1',licence_expiry:'2030-01-01',licence_categories:['B','C']});
});

test('HR can register a licence for an employee who has no driver record yet',async({page})=>{
 await boot(page,'admin');
 await tab(page,'documentos');
 await page.selectOption('#hpLicEmployee','e2');
 await expect(page.locator('#hpLicNumber')).toHaveValue('');
 await page.fill('#hpLicNumber','EC-7654321');
 await page.fill('#hpLicExpiry','2029-06-30');
 await page.locator('[data-hp-cat][value="B"]').check();
 await page.locator('#hpLicSave').click();
 await expect.poll(()=>page.evaluate(()=>window.__DB.fleet_drivers?.length)).toBe(1);
 expect(await page.evaluate(()=>window.__DB.fleet_drivers[0])).toMatchObject(
  {employee_id:'e2',licence_number:'EC-7654321',licence_categories:['B']});
});

test('a manager without HR rights never sees the licences',async({page})=>{
 await boot(page,'manager',{fleet_drivers:[{id:'d1',employee_id:'e1',active:true,licence_number:'EC-1042335'}]});
 await tab(page,'documentos');
 await expect(page.locator('#hr')).not.toContainText('EC-1042335');
 await expect(page.locator('#hpLicSave')).toHaveCount(0);
});

// «Responsable RH» es un perfil de base: gestiona RRHH como el administrador,
// sin la antigua pestaña de derechos.
test('the HR base role runs HR without the old rights tab',async({page})=>{
 await boot(page,'rh');
 for(const id of ['empleados','ausencias','planificacion','reglas','documentos','nomina','organigrama'])await expect(page.locator(`#hr [data-tab="${id}"]`)).toHaveCount(1);
 await expect(page.locator('#hr [data-tab="permisos"]')).toHaveCount(0);
 await expect(page.locator('#hr')).toContainText('9.876');
 await tab(page,'organigrama');await expect(page.locator('#hpOrgSave')).toBeVisible();
});
// El organigrama sale del N+1 de cada empleado; RRHH lo cambia sin círculos.
test('the org chart draws each team under its N+1, and HR changes it without cycles',async({page})=>{
 await boot(page);await tab(page,'organigrama');
 const chart=page.locator('#hr .hoChart');
 await expect(chart.locator('.hoTree > li > .hoNode b')).toHaveText(['Responsable']);
 await expect(chart.locator('.hoTree > li > .hoNode')).toContainText('Jefa de almacén');
 await expect(chart.locator('.hoTree > li > .hoNode .hoCount')).toHaveText('1 a cargo');
 await expect(chart.locator('.hoTree > li > ul > li .hoNode b')).toHaveText(['Marie']);
 await expect(page.locator('#hr .hoAlone .hoNode b')).toHaveText(['Confidentiel']);
 // Elegir a Confidentiel en el dibujo: el formulario la trae y se le da su N+1.
 await page.locator('#hr .hoAlone [data-org-pick="e2"]').click();
 await expect(page.locator('#hpOrgEmployee')).toHaveValue('e2');await expect(page.locator('#hpOrgManager')).toBeFocused();
 await page.selectOption('#hpOrgManager','e3');await page.click('#hpOrgSave');
 await expect.poll(()=>page.evaluate(()=>__DB.hr_employees.find(e=>e.id==='e2').manager_id)).toBe('e3');
 await expect(chart.locator('.hoTree > li > ul > li .hoNode b')).toHaveText(['Confidentiel','Marie']);
 await expect(chart.locator('.hoTree > li > .hoNode .hoCount')).toHaveText('2 a cargo');
 await expect(page.locator('#hr .hoAlone')).toHaveCount(0);
 // Responsable no puede depender de su propio equipo: no se ofrece…
 await page.selectOption('#hpOrgEmployee','e3');
 await expect(page.locator('#hpOrgManager option')).toHaveText(['Sin N+1']);
 // …y si llega igual, la base lo rechaza con un mensaje claro.
 await page.evaluate(()=>{const o=document.createElement('option');o.value='e1';o.textContent='Marie';document.getElementById('hpOrgManager').append(o)});
 await page.selectOption('#hpOrgManager','e1');await page.click('#hpOrgSave');
 await expect(page.locator('#hpError')).toHaveText('Ese N+1 depende de este empleado: el organigrama formaría un círculo.');
 expect(await page.evaluate(()=>__DB.hr_employees.find(e=>e.id==='e3').manager_id)).toBeFalsy();
});
test('the employee file sets or clears the N+1',async({page})=>{
 await boot(page);
 await page.locator('#hr [data-edit="e1"]').click();
 await expect(page.locator('#hrManager')).toHaveValue('e3');
 await expect(page.locator('#hrManager option[value="e1"]')).toHaveCount(0);
 await page.selectOption('#hrManager','');await page.click('#hrSave');
 await expect.poll(()=>page.evaluate(()=>__DB.hr_employees.find(e=>e.id==='e1').manager_id)).toBe(null);
});
test('every employee reads the org chart, without editing it',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'magasinier');await tab(page,'organigrama');
 await expect(page.locator('#hr .hoNode')).toHaveCount(3);await expect(page.locator('#hr [data-org-pick], #hpOrgSave')).toHaveCount(0);
 await expect(page.locator('#hr .hoMine')).toContainText('Marie');await expect(page.locator('#hr .hoMine')).toContainText('Tú');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
// Con ocho personas o más las listas llevan buscador: elegir en el dibujo pone
// al día lo que se ve y deja el foco en el buscador del N+1.
test('picking someone in a large org chart updates the searchable lists',async({page})=>{
 const people=Array.from({length:10},(_,i)=>({id:'p'+i,full_name:'Persona '+i,manager_id:i?'p0':null,active:true}));
 await boot(page,'admin',{hr_employees:people});await tab(page,'organigrama');
 await page.locator('#hr [data-org-pick="p5"]').click();
 await expect(page.locator('[data-gama-for="hpOrgEmployee"]')).toHaveValue('Persona 5');
 await expect(page.locator('[data-gama-for="hpOrgManager"]')).toBeFocused();
 await page.locator('#hpOrgManager').selectOption('p3',{force:true});await page.click('#hpOrgSave');
 await expect.poll(()=>page.evaluate(()=>__DB.hr_employees.find(e=>e.id==='p5').manager_id)).toBe('p3');
});
