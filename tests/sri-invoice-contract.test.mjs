import {test} from 'node:test';
import assert from 'node:assert/strict';
import {invoiceContract} from '../supabase/functions/_shared/sri-invoice-contract.mjs';
const id='00000000-0000-4000-8000-000000000001';
export function fixture() {return {
 invoice:{id,number:'FI-1',order_id:id,document_kind:'internal',fiscal_status:'unverified',issue_date:'2026-10-10',due_date:'2026-11-09',subtotal:18,tax:2.7,total:20.7,
  document_snapshot:{customer:'Buyer at invoice time',customer_identification:'1719304188',details:{clientAddress:'Quito',clientEmail:'buyer@example.invalid'},lines:[{line_id:id,reference:'PAPER',name:'Paper',qty:2,price:9,listPrice:10,discount:10,taxRate:15,subtotal:18,tax:2.7}]}},
 settings:{environment:'pruebas',ruc:'1790012345001',razon_social:'GAMA',dir_matriz:'Quito',estab:'001',pto_emi:'002',accounting_obligation:'NO',provider_ruc:'1790012345001'},
 company:{configured:true,country:'EC',currency:'USD',tax_id:'1790012345001'},paymentCode:'20'
};}
test('API contract preserves net discounted price, identities, decimal strings and payment term',()=>{
 const r=invoiceContract(fixture());assert.equal(r.valid,true);assert.equal(r.emission_enabled,false);assert.equal(r.can_prepare,true);assert.equal(r.idempotency_key,null);
 assert.equal(r.payload.buyer.identification_type,'05');assert.equal(r.payload.lines[0].unit_price,'9.000000');assert.equal(r.payload.lines[0].discount,'0.00');assert.equal(r.payload.lines[0].commercial.discount_percent,'10');
 assert.equal(r.payload.totals.total,'20.70');assert.equal(r.payload.payments[0].term_days,30);assert.equal(r.payload.tax_totals[0].percentage_code,'4');assert.equal(r.payload.document.sequential,null);
});
test('integer arithmetic rounds line amounts half up and keeps six decimal unit precision',()=>{
 const f=fixture();Object.assign(f.invoice,{subtotal:1.01,tax:.15,total:1.16});Object.assign(f.invoice.document_snapshot.lines[0],{qty:1,price:1.005,subtotal:1.01,tax:.15});
 const r=invoiceContract(f);assert.equal(r.valid,true);assert.equal(r.payload.totals.total,'1.16');
});
test('mixed VAT groups, zero rate and original fiscal snapshot are independent from mutable settings',()=>{
 const f=fixture();f.issue={id,source_invoice_id:id,status:'processing',environment:'pruebas',issuer_ruc:f.settings.ruc,establishment:'001',emission_point:'002',sequential:'000000012',numeric_code:'00000001',snapshot:{issue_date:'2026-10-10',currency:'USD',source_number:'FI-1',issuer:'Original issuer',address:'Original address',accounting_obligation:'NO',provider_ruc:f.settings.provider_ruc,customer:'Frozen buyer',identification:'1790012345001',customer_address:'Quito',payment_code:'01',subtotal:28,tax:2.7,total:30.7,lines:[{code:'A',description:'Paper',quantity:2,unit_price:9,tax_rate:15,subtotal:18},{code:'B',description:'Book',quantity:1,unit_price:10,tax_rate:0,subtotal:10}]}};
 f.settings={};f.company={};f.invoice.document_snapshot={};const r=invoiceContract(f);
 assert.equal(r.valid,true);assert.equal(r.mode,'frozen');assert.equal(r.payload.buyer.legal_name,'Frozen buyer');assert.equal(r.payload.issuer.legal_name,'Original issuer');assert.equal(r.payload.tax_totals.length,2);assert.equal(r.idempotency_key,`coco:sri:01:pruebas:${id}`);assert.equal(r.can_prepare,false);
});
test('missing fiscal data, totals, invalid decimals and unsupported identities fail closed',()=>{
 for(const mutate of [f=>f.invoice.document_snapshot.customer_identification='',f=>f.invoice.document_snapshot.customer_identification='9999999999999',f=>f.invoice.total=20.71,f=>f.invoice.document_snapshot.lines[0].price='NaN',f=>f.invoice.document_snapshot.lines[0].qty=0,f=>f.invoice.document_snapshot.lines[0].taxRate=7,f=>f.settings.provider_ruc='',f=>f.company.currency='EUR',f=>f.invoice.document_snapshot.lines=[],f=>f.invoice.document_snapshot.lines=[null],f=>f.invoice.issue_date='2026-02-30',f=>f.invoice.due_date='2026-10-09']){
  const f=fixture();mutate(f);const r=invoiceContract(f);assert.equal(r.valid,false);assert.equal(r.can_prepare,false);assert.ok(r.errors.length);
 }
});
test('legacy missing snapshots never read mutable customer records or change input',()=>{
 const f=fixture();f.invoice.document_snapshot={};const before=JSON.stringify(f);const r=invoiceContract(f);assert.equal(r.valid,false);assert.equal(JSON.stringify(f),before);
});
