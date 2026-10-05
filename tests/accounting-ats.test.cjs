const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),{spawnSync}=require('node:child_process');
const load=async()=>require('../src/domain/accounting-ecuador.js');
const fixture=()=>({from:'2026-10-01',to:'2026-10-31',blockers:[],profile:{regime:'general',ats_required:true,confirmed_on:'2026-10-01',establishments:1},company:{tax_id:'0912345678001',legal_name:'TEST PARTNERS FIXTURE'},documents:['sales_invoice','supplier_invoice'].map((source_type,i)=>({source_type,source_id:String(i),number:'TEST-'+i,issue_date:'2026-10-01',subtotal:100,tax:15,total:115,fiscal_id:String(i),fiscal:{document_type:'01',document_number:'001-001-00000000'+(i+1),identification_type:'04',identification:'0912345678001',authorization_number:'1234567890123456789012345678901234567890123456789',support_code:'01',payment_codes:['20'],base_zero:0,base_taxed:100,base_exempt:0,base_non_taxable:0,vat:15,ice:0}}))});

test('ATS draft is escaped, grouped and valid against the downloaded SRI schema',async()=>{
 const {buildAts}=await load(),f=fixture();f.documents.push({...f.documents[0],number:'TEST-2',source_id:'2'});const r=buildAts(f);assert.deepEqual(r.errors,[]);assert.match(r.xml,/TEST PARTNERS FIXTURE/);assert.match(r.xml,/<numeroComprobantes>2</);assert.match(r.xml,/<totalVentas>200.00</);assert.equal(r.status,'draft_not_submitted');
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'coco-ats-')),xml=path.join(directory,'ats.xml');fs.writeFileSync(xml,r.xml);
 try{const validation=spawnSync('python3',['-c',"from lxml import etree;import sys;s=etree.XMLSchema(etree.parse(sys.argv[1]));d=etree.parse(sys.argv[2]);s.assertValid(d)",path.join(__dirname,'fixtures/accounting/ats.xsd'),xml],{encoding:'utf8'});assert.equal(validation.status,0,validation.stderr);}finally{fs.rmSync(directory,{recursive:true,force:true});}
});
test('ATS never silently omits missing, cancelled, returned, foreign, RIMPE or withheld documents',async()=>{
 const {buildAts}=await load();for(const mutate of [f=>f.company.legal_name='TEST & PARTNERS <script>',f=>f.company.tax_id='',f=>f.to='2026-10-20',f=>f.profile.regime='rimpe_popular',f=>f.documents[0].fiscal=null,f=>f.documents[0].fiscal.base_taxed=99,f=>f.withholdings=[{}],f=>f.return_credits=[{}],f=>f.cancelled_documents=1,f=>f.documents[0].fiscal.identification_type='06']){const f=fixture();mutate(f);const r=buildAts(f);assert.ok(r.errors.length);assert.equal(r.xml,null);}
});

function validateXml(xml){
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'coco-ats-')),file=path.join(directory,'ats.xml');fs.writeFileSync(file,xml);
 try{const v=spawnSync('python3',['-c',"from lxml import etree;import sys;etree.XMLSchema(etree.parse(sys.argv[1])).assertValid(etree.parse(sys.argv[2]))",path.join(__dirname,'fixtures/accounting/ats.xsd'),file],{encoding:'utf8'});assert.equal(v.status,0,v.stderr)}finally{fs.rmSync(directory,{recursive:true,force:true})}
}
test('ATS includes sales credits, both withholding kinds and legally documented cancellations',async()=>{
 const f=fixture();f.profile.withholding_agent=true;f.profile.ats_establishments=['001'];
 f.documents.push({...f.documents[0],source_type:'sales_credit',source_id:'credit',number:'DEV-1',subtotal:20,tax:3,total:23,fiscal_id:'credit',fiscal:{...f.documents[0].fiscal,document_type:'04',document_number:'001-001-000000004',base_taxed:20,vat:3,payment_codes:[]}});
 f.withholdings=[{id:'w1',side:'supplier',supplier_invoice_id:'1',number:'001-001-000000003',authorization_number:'7'.repeat(49),issued_on:'2026-10-02',amount:6.5,lines:[{tax_kind:'income',code:'312',base:100,rate:2},{tax_kind:'vat',code:'1',base:15,rate:30}]},{id:'w2',side:'customer',invoice_id:'0',number:'001-001-000000005',authorization_number:'8'.repeat(49),issued_on:'2026-10-02',amount:13,lines:[{tax_kind:'income',code:'312',base:100,rate:10},{tax_kind:'vat',code:'1',base:15,rate:20}]}];
 f.cancellations=[{document_type:'01',establishment:'001',emission_point:'001',sequential_start:6,sequential_end:6,authorization_number:'1234567890',evidence:'Reviewed cancellation document'}];
 const r=(await load()).buildAts(f);assert.deepEqual(r.errors,[]);assert.match(r.xml,/<totalVentas>80.00</);assert.match(r.xml,/<tipoComprobante>04</);assert.match(r.xml,/<valorRetBienes>4.50</);assert.match(r.xml,/<valRetAir>2.00</);assert.match(r.xml,/<valorRetIva>3.00</);assert.match(r.xml,/<valorRetRenta>10.00</);assert.match(r.xml,/<anulados>/);validateXml(r.xml);
});
test('ATS handles purchase credit support, purchase liquidation and a receipt on a prior-month sale',async()=>{
 const f=fixture();const original=f.documents[1].fiscal;
 f.documents[1].fiscal={...original,document_type:'03',identification_type:'05',identification:'1719304188'};
 f.documents.push({...f.documents[1],source_type:'supplier_credit',source_id:'credit',number:'PRO-CREDIT',subtotal:10,tax:1.5,total:11.5,fiscal_id:'credit',fiscal:{...original,document_type:'04',base_taxed:10,vat:1.5,modified_document_type:'01',modified_number:original.document_number,modified_authorization:original.authorization_number}});
 f.withholdings=[{id:'prior',side:'customer',invoice_id:'prior-month',number:'001-001-000000010',authorization_number:'8'.repeat(49),issued_on:'2026-10-02',amount:2,invoice_fiscal:{...f.documents[0].fiscal,identification:'1719304188001'},lines:[{tax_kind:'income',code:'312',base:100,rate:2}]}];
 const r=(await load()).buildAts(f);assert.deepEqual(r.errors,[]);assert.match(r.xml,/<docModificado>01</);assert.match(r.xml,/<numeroComprobantes>0</);assert.match(r.xml,/<valorRetRenta>2.00</);validateXml(r.xml);
});
test('ATS rejects unreviewed original support, withholding mismatch and unlisted establishments',async()=>{
 const f=fixture();f.documents[1].fiscal={...f.documents[1].fiscal,document_type:'04'};assert.ok((await load()).buildAts(f).errors.some(x=>x.startsWith('ATS_MODIFIED_DOCUMENT_REQUIRED')));
 const g=fixture();g.profile.establishments=2;assert.ok((await load()).buildAts(g).errors.includes('ATS_ESTABLISHMENTS_LIST_REQUIRED'));
 const h=fixture();h.withholdings=[{id:'bad',side:'customer',invoice_id:'0',number:'001-001-000000004',authorization_number:'7'.repeat(49),amount:3,lines:[{tax_kind:'income',code:'312',base:100,rate:2}]}];assert.ok((await load()).buildAts(h).errors.some(x=>x.startsWith('ATS_WITHHOLDING_TOTAL_MISMATCH')));
});
