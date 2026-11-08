const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function document(documentType){
 const headers=[],footers=[];
 const drawing={setFontSize(){},splitTextToSize:t=>[String(t)],text(){},setFillColor(){},rect(){},setTextColor(){},setDrawColor(){},setLineWidth(){},line(){},setFont(){},addPage(){},output:()=>({pdf:true})};
 const window={jspdf:{jsPDF:function(){return drawing}},GamaPdfTemplate:{theme:()=>({ink:[0],teal:[0],secondary:[0],onSecondary:[0]}),header:(_,q)=>{headers.push(q);return 30},footer:(_,s)=>footers.push(s)}};
 vm.runInNewContext(fs.readFileSync('src/features/sales/quote-pdf.js','utf8'),{window,GamaCurrency:{symbol:()=>'$'},navigator:{}});
 window.GamaQuotePdf.build({documentType,number:'COT-1',items:[],total:0});return {headers,footers};
}
test('the pro forma PDF identifies its document purpose and cannot look like a fiscal or paid invoice',()=>{
 const result=document('proforma');assert.equal(result.headers[0].title,'PRO FORMA');assert.match(result.footers[0],/No constituye una factura ni acredita un pago/);
 const invoice=document('internal_invoice');assert.equal(invoice.headers[0].title,'FACTURA INTERNA');assert.match(invoice.footers[0],/Sin validez fiscal/);
 assert.equal(document('quote').headers[0].title,'PRESUPUESTO');
});
