const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
function boot({fixtures={},role='administrador',failure,cap=200}={}){
 const calls=[],downloads=[],messages=[],button={disabled:false,parentElement:{querySelector(){return {set textContent(x){messages.push(x)}}}}};
 const context={console:{error(){}},document:{documentElement:{lang:'fr'},querySelectorAll(){return [button]}},window:null};context.window=context;
 context.GamaI18n={language:'fr'};context.XLSX={utils:{book_new:()=>({SheetNames:[],Sheets:{}}),aoa_to_sheet:r=>({rows:r}),book_append_sheet(w,s,n){w.SheetNames.push(n);w.Sheets[n]=s}},writeFile(w,n){downloads.push({w,n})}};
 context.GamaCloud={getProfile:async()=>({data:{role,active:true}}),db:async()=>({from(table){const q={select(columns){calls.push({table,columns,orders:[]});return q},order(k){calls.at(-1).orders.push(k);return q},async range(a,b){calls.at(-1).range=[a,b];if(failure?.table===table)return {error:failure};return {data:(fixtures[table]||[]).slice(a,Math.min(b+1,a+cap))}}};return q}})};
 vm.createContext(context);for(const f of ['gama-export-schema.js','gama-excel-export.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'..',f),'utf8'),context);return {context,calls,downloads,messages,button};
}
test('all business tables map to a module; paginated export preserves text and amounts',async()=>{
 const products=Array.from({length:1201},(_,i)=>({id:String(i),barcode:'000'+i,name:i===0?'=SUM(1,2)':'Produit '+i,sale_price:12.5,description:'é & < >'}));
 const x=boot({fixtures:{products,suppliers:[{id:'s',name:'Fournisseur'}],customer_special_prices:[{id:'t',contract_ref:'Contrat 001'}],knowledge_articles:[{id:'k',body:'é'.repeat(70000),properties:[{label:'Auteur',value:'Jimmy'}]}],
  fleet_vehicles:[{id:'v',plate:'TCA-9001',brand:'Mercedes-Benz',odometer:164300}],
  expenses:[{id:'e',reference:'GA-00000001',amount_total:55}]}});
 for(const s of x.context.GamaExportSchema)assert.ok(x.context.GamaExcelExport.group(s.table)>=0);
 await x.context.GamaExcelExport.run();assert.equal(x.downloads.length,1);const w=x.downloads[0].w;assert.equal(w.SheetNames.length,27);assert.ok(w.Sheets.Projets);assert.ok(w.Sheets.SAV);assert.ok(w.Sheets.Documents);
 assert.ok(w.Sheets.Flotte.rows.some(r=>r.includes('TCA-9001')&&r.includes(164300)));
 assert.ok(w.Sheets['Comptabilité'].rows.some(r=>r.includes('GA-00000001')&&r.includes(55)));const p=w.Sheets.Produits.rows;assert.equal(p.length,1204);assert.equal(p[2][p[1].indexOf('barcode')],'0000');assert.equal(p[2][p[1].indexOf('name')],'=SUM(1,2)');assert.equal(p[2][p[1].indexOf('sale_price')],12.5);assert.equal(p[1202][p[1].indexOf('id')],'1200');
 const k=w.Sheets.Knowledge.rows,body=k[1].flatMap((h,i)=>h.startsWith('body')?[k[2][i]]:[]).join('');assert.equal(body,'é'.repeat(70000));assert.ok(k[2].some(v=>typeof v==='string'&&v.includes('Jimmy')));
 assert.ok(x.calls.every(c=>!c.columns.split(',').some(col=>['photo_data','content_base64','photo','data_url','encrypted_key','signature'].includes(col))));assert.equal(x.calls.filter(c=>c.table==='products').length,8);assert.equal(x.button.disabled,false);
 assert.equal(x.calls.find(c=>c.table==='external_invoice_deliveries').orders.join(','),'invoice_id,delivery_id');
});
test('permission errors are recorded in summary; other modules still export',async()=>{const x=boot({failure:{table:'hr_employee_private',code:'42501',message:'denied'}});await x.context.GamaExcelExport.run();assert.equal(x.downloads.length,1);assert.ok(x.downloads[0].w.Sheets.Sommaire.rows.some(r=>r[1]==='hr_employee_private'&&r[3]==='Accès refusé'));});
test('network errors never download a workbook presented as complete, and retry works',async()=>{const failure={table:'suppliers',code:'NETWORK',message:'offline'},x=boot({failure});await x.context.GamaExcelExport.run();assert.equal(x.downloads.length,0);assert.equal(x.button.disabled,false);assert.match(x.messages.at(-1),/Export interrompu/);failure.table='none';await x.context.GamaExcelExport.run();assert.equal(x.downloads.length,1)});
test('client accounts cannot initiate the internal export',async()=>{const x=boot({role:'cliente'});await x.context.GamaExcelExport.run();assert.equal(x.downloads.length,0);assert.equal(x.calls.length,0)});
