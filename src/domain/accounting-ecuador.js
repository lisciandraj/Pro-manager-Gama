(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;if(root)root.ArcEcuador=api})(typeof window==='object'?window:null,function(){
'use strict';
// Monthly domestic ATS: fiscal facts, credits, withheld taxes and documented cancellations.
// SRI: https://descargas.sri.gob.ec/download/anexos/ats/ats.xsd
const escapeXml=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const tag=(k,v)=>`<${k}>${escapeXml(v)}</${k}>`;
const cents=v=>Math.round(Number(v)*100);const cash=v=>(Number(v)/100).toFixed(2);
const date=v=>v.slice(8,10)+'/'+v.slice(5,7)+'/'+v.slice(0,4);
function buildAts(review){
 const errors=[...(review.blockers||[])],p=review.profile||{},company=review.company||{};
 const from=review.from||'',to=review.to||'';const start=from.slice(0,7)+'-01';const end=/^\d{4}-\d{2}-\d{2}$/.test(from)?new Date(Date.UTC(Number(from.slice(0,4)),Number(from.slice(5,7)),0)).toISOString().slice(0,10):'';
 if(from!==start||to!==end)errors.push('ATS_FULL_MONTH_REQUIRED');
 if(p.regime!=='general')errors.push('ATS_REGIME_REQUIRES_SEPARATE_REVIEW');
 if(p.ats_required!==true||!p.confirmed_on)errors.push('ATS_OBLIGATION_UNCONFIRMED');
 if(!/^\d{10}001$/.test(company.tax_id||''))errors.push('RUC_REQUIRED');
 if(String(company.legal_name||'').trim().length<5)errors.push('LEGAL_NAME_REQUIRED');
 if(!/^[a-zA-Z0-9][a-zA-Z0-9\s]+[a-zA-Z0-9\s]$/.test(company.legal_name||''))errors.push('ATS_LEGAL_NAME_SCHEMA_FORMAT');
 if(!Number.isInteger(p.establishments)||p.establishments<1||p.establishments>999)errors.push('ESTABLISHMENTS_REQUIRED');
 if((review.adjustments||[]).length)errors.push('ATS_ADJUSTMENTS_REQUIRE_FISCAL_DETAILS');
 if((review.return_credits||[]).length||review.cancelled_documents>0)errors.push('ATS_RETURNS_CANCELLATIONS_REQUIRE_REVIEW');
 let purchases='',sales='';const groups=new Map(),establishments=new Map(),salesGroups=new Map(),usedWithholdings=new Set();let totalSales=0;
 const withholdings=review.withholdings||[];
 const value=l=>Math.round(Number((cents(l.base)*Number(l.rate)/100).toFixed(6)));
 const taxTotals=w=>{let ir=0,vat=0;for(const l of w.lines||[]){if(!Number.isFinite(Number(l.base))||Number(l.base)<=0||!Number.isFinite(Number(l.rate))||Number(l.rate)<=0||Number(l.rate)>100||!/^\d{1,5}$/.test(l.code||'')||!['income','vat'].includes(l.tax_kind))errors.push('ATS_WITHHOLDING_INVALID:'+w.number);else if(l.tax_kind==='income')ir+=value(l);else vat+=value(l);}if(ir+vat!==cents(w.amount))errors.push('ATS_WITHHOLDING_TOTAL_MISMATCH:'+w.number);return{ir,vat}};
 const retByInvoice=new Map();for(const w of withholdings){if(!['customer','supplier'].includes(w.side)||!/^\d{3}-\d{3}-\d{9}$/.test(w.number||'')||!/^\d{10,49}$/.test(w.authorization_number||'')||!Array.isArray(w.lines)||!w.lines.length){errors.push('ATS_WITHHOLDING_DETAILS_REQUIRED');continue;}taxTotals(w);const id=w.invoice_id||w.supplier_invoice_id;const key=w.side+':'+id;retByInvoice.set(key,[...(retByInvoice.get(key)||[]),w]);}
 for(const d of review.documents||[]){
  const f=d.fiscal;
  const fail=code=>errors.push(`${code}:${d.number}`);
  if(!f||!d.fiscal_id){fail('FISCAL_DETAILS_REQUIRED');continue;}
  if(!['01','03','04','05'].includes(f.document_type)||!['04','05','07'].includes(f.identification_type)){fail('ATS_DOCUMENT_UNSUPPORTED');continue;}
  if(!/^\d{3}-\d{3}-\d{9}$/.test(f.document_number)||!/^\d{10,49}$/.test(f.authorization_number)){fail('ATS_DOCUMENT_ID_INVALID');continue;}
  const nums=['base_zero','base_taxed','base_exempt','base_non_taxable','ice','vat'];
  if(nums.some(k=>!Number.isFinite(Number(f[k]))||Number(f[k])<0)){fail('ATS_AMOUNT_INVALID');continue;}
  const base=cents(f.base_zero)+cents(f.base_taxed)+cents(f.base_exempt)+cents(f.base_non_taxable);
  if(base!==cents(d.subtotal)||cents(f.vat)!==cents(d.tax)||base+cents(f.vat)+cents(f.ice)!==cents(d.total)){fail('FISCAL_TOTAL_MISMATCH');continue;}
  if(!Array.isArray(f.payment_codes)||(!['04','05'].includes(f.document_type)&&!f.payment_codes.length)||f.payment_codes.some(c=>!['01','15','16','18','19','20','21'].includes(c))){fail('PAYMENT_CODE_REQUIRED');continue;}
  if(f.identification_type==='04'&&!/^\d{13}$/.test(f.identification)||f.identification_type==='05'&&!/^\d{10}$/.test(f.identification)||f.identification_type==='07'&&f.identification!=='9999999999999'){fail('ATS_PARTNER_ID_INVALID');continue;}
  const codes={customer:{'04':'04','05':'05','07':'07'},supplier:{'04':'01','05':'02'}};
  const payments=`<formasDePago>${[...new Set(f.payment_codes)].sort().map(c=>tag('formaPago',c)).join('')}</formasDePago>`;
  const [est,point,seq]=f.document_number.split('-');
  if(['sales_invoice','sales_credit','customer_adjustment'].includes(d.source_type)){
   if(cents(f.base_exempt)>0){fail('ATS_EXEMPT_SALE_REQUIRES_REVIEW');continue;}
   const key=[f.identification_type,f.identification,f.document_type,est,f.authorization_number.length===49?'E':'F'].join('|');
   const g=groups.get(key)||{f,est,count:0,zero:0,taxed:0,non:0,vat:0,ice:0,irRet:0,vatRet:0,paymentSet:new Set()};f.payment_codes.forEach(c=>g.paymentSet.add(c));g.count++;g.zero+=cents(f.base_zero);g.taxed+=cents(f.base_taxed);g.non+=cents(f.base_non_taxable);g.vat+=cents(f.vat);g.ice+=cents(f.ice);groups.set(key,g);
   const sign=f.document_type==='04'?-1:1;establishments.set(est,(establishments.get(est)||0)+base*sign);totalSales+=base*sign;
   if(d.source_type==='sales_invoice'){salesGroups.set(d.source_id,g);for(const w of retByInvoice.get('customer:'+d.source_id)||[]){const t=taxTotals(w);g.irRet+=t.ir;g.vatRet+=t.vat;usedWithholdings.add(w.id||w);}}
  }else{
   if(!codes.supplier[f.identification_type]||!/^\d{2}$/.test(f.support_code||'')){fail('ATS_PURCHASE_SUPPORT_REQUIRED');continue;}
   const ret=retByInvoice.get('supplier:'+d.source_id)||[];const vatFields={'10':0,'20':0,'30':0,'50':0,'70':0,'100':0};let air='';
   if(ret.length>2){fail('ATS_MULTIPLE_RETENTION_CERTIFICATES_REVIEW');continue;}
   for(const w of ret){usedWithholdings.add(w.id||w);for(const l of w.lines){if(l.tax_kind==='income')air+='<detalleAir>'+tag('codRetAir',l.code)+tag('baseImpAir',cash(cents(l.base)))+tag('porcentajeAir',l.rate)+tag('valRetAir',cash(value(l)))+'</detalleAir>';else if(Object.hasOwn(vatFields,String(Number(l.rate))))vatFields[String(Number(l.rate))]+=value(l);else fail('ATS_VAT_WITHHOLDING_RATE_UNSUPPORTED');}}
   if(!air&&p.withholding_agent===true&&!['04','05'].includes(f.document_type))air='<detalleAir>'+tag('codRetAir','332')+tag('baseImpAir',cash(base))+tag('porcentajeAir','0')+tag('valRetAir','0.00')+'</detalleAir>';
   let certs='';ret.forEach((w,i)=>{const [e,pt,sq]=w.number.split('-');certs+=tag('estabRetencion'+(i+1),e)+tag('ptoEmiRetencion'+(i+1),pt)+tag('secRetencion'+(i+1),sq)+tag('autRetencion'+(i+1),w.authorization_number);if(i===0)certs+=tag('fechaEmiRet1',date(w.issued_on));});
   let modified='';if(['04','05'].includes(f.document_type)){if(!/^\d{2}$/.test(f.modified_document_type||'')||!/^\d{3}-\d{3}-\d{9}$/.test(f.modified_number||'')||!/^\d{10,49}$/.test(f.modified_authorization||'')){fail('ATS_MODIFIED_DOCUMENT_REQUIRED');continue;}const [me,mp,ms]=f.modified_number.split('-');modified=tag('docModificado',f.modified_document_type)+tag('estabModificado',me)+tag('ptoEmiModificado',mp)+tag('secModificado',ms)+tag('autModificado',f.modified_authorization);}
   const issued=f.document_issued_on||d.issue_date;if(!/^\d{4}-\d{2}-\d{2}$/.test(issued)||issued>d.issue_date){fail('ATS_DOCUMENT_DATE_INVALID');continue;}
   purchases+='<detalleCompras>'+tag('codSustento',f.support_code)+tag('tpIdProv',codes.supplier[f.identification_type])+tag('idProv',f.identification)+tag('tipoComprobante',f.document_type)+tag('parteRel',f.related_party?'SI':'NO')+tag('fechaRegistro',date(d.issue_date))+tag('establecimiento',est)+tag('puntoEmision',point)+tag('secuencial',seq)+tag('fechaEmision',date(issued))+tag('autorizacion',f.authorization_number)+tag('baseNoGraIva',cash(cents(f.base_non_taxable)))+tag('baseImponible',cash(cents(f.base_zero)))+tag('baseImpGrav',cash(cents(f.base_taxed)))+tag('baseImpExe',cash(cents(f.base_exempt)))+tag('montoIce',cash(cents(f.ice)))+tag('montoIva',cash(cents(f.vat)))+tag('valRetBien10',cash(vatFields['10']))+tag('valRetServ20',cash(vatFields['20']))+tag('valorRetBienes',cash(vatFields['30']))+tag('valRetServ50',cash(vatFields['50']))+tag('valorRetServicios',cash(vatFields['70']))+tag('valRetServ100',cash(vatFields['100']))+'<pagoExterior>'+tag('pagoLocExt','01')+tag('paisEfecPago','NA')+tag('aplicConvDobTrib','NA')+tag('pagExtSujRetNorLeg','NA')+'</pagoExterior>'+(f.payment_codes.length?payments:'')+(air?'<air>'+air+'</air>':'')+certs+modified+'</detalleCompras>';
  }
 }
 // A receipt received this month may refer to an earlier invoice: report the
 // withholding with zero new documents, without repeating the earlier sale.
 for(const w of withholdings){if(usedWithholdings.has(w.id||w))continue;if(w.side!=='customer'){errors.push('ATS_WITHHOLDING_PURCHASE_SOURCE_NOT_IN_PERIOD:'+w.number);continue;}const f=w.invoice_fiscal;if(!f||!/^\d{3}-\d{3}-\d{9}$/.test(f.document_number||'')||!['04','05'].includes(f.identification_type)){errors.push('ATS_WITHHOLDING_INVOICE_DETAILS_REQUIRED:'+w.number);continue;}const est=f.document_number.slice(0,3),key=[f.identification_type,f.identification,'01',est,f.authorization_number?.length===49?'E':'F'].join('|'),g=groups.get(key)||{f:{...f,document_type:'01'},est,count:0,zero:0,taxed:0,non:0,vat:0,ice:0,irRet:0,vatRet:0,paymentSet:new Set(f.payment_codes||[])};const t=taxTotals(w);g.irRet+=t.ir;g.vatRet+=t.vat;groups.set(key,g);if(!establishments.has(est))establishments.set(est,0);}
 // ATS table 4 uses 18 for an ordinary sale; electronic invoice XML uses 01.
 for(const g of groups.values())sales+='<detalleVentas>'+tag('tpIdCliente',codesSales(g.f.identification_type))+tag('idCliente',g.f.identification)+tag('parteRelVtas',g.f.related_party?'SI':'NO')+tag('tipoComprobante',g.f.document_type==='01'?'18':g.f.document_type)+tag('tipoEmision',g.f.authorization_number.length===49?'E':'F')+tag('numeroComprobantes',g.count)+tag('baseNoGraIva',cash(g.non))+tag('baseImponible',cash(g.zero))+tag('baseImpGrav',cash(g.taxed))+tag('montoIva',cash(g.vat))+tag('montoIce',cash(g.ice))+tag('valorRetIva',cash(g.vatRet))+tag('valorRetRenta',cash(g.irRet))+(g.paymentSet.size?'<formasDePago>'+[...g.paymentSet].sort().map(c=>tag('formaPago',c)).join('')+'</formasDePago>':'')+'</detalleVentas>';
 let cancelled='';for(const c of review.cancellations||[]){if(!/^\d{2}$/.test(c.document_type||'')||!/^\d{3}$/.test(c.establishment||'')||!/^\d{3}$/.test(c.emission_point||'')||!Number.isInteger(Number(c.sequential_start))||Number(c.sequential_start)<1||Number(c.sequential_end)<Number(c.sequential_start)||Number(c.sequential_end)>999999999||!/^\d{3,49}$/.test(c.authorization_number||'')||!c.evidence){errors.push('ATS_CANCELLATION_DETAILS_REQUIRED');continue;}cancelled+='<detalleAnulados>'+tag('tipoComprobante',c.document_type)+tag('establecimiento',c.establishment)+tag('puntoEmision',c.emission_point)+tag('secuencialInicio',c.sequential_start)+tag('secuencialFin',c.sequential_end)+tag('autorizacion',c.authorization_number)+'</detalleAnulados>';}
 if(p.ats_establishments){if(!Array.isArray(p.ats_establishments)||p.ats_establishments.length!==p.establishments||new Set(p.ats_establishments).size!==p.establishments||p.ats_establishments.some(e=>!/^\d{3}$/.test(e)||e==='000')||[...establishments.keys()].some(e=>!p.ats_establishments.includes(e)))errors.push('ATS_ESTABLISHMENTS_INVALID');else p.ats_establishments.forEach(e=>{if(!establishments.has(e))establishments.set(e,0)});}else if(establishments.size&&establishments.size!==p.establishments)errors.push('ATS_ESTABLISHMENTS_LIST_REQUIRED');
 if(errors.length)return {errors:[...new Set(errors)],xml:null};
 const xml='<?xml version="1.0" encoding="UTF-8"?>\n<iva>'+tag('TipoIDInformante','R')+tag('IdInformante',company.tax_id)+tag('razonSocial',company.legal_name)+tag('Anio',from.slice(0,4))+tag('Mes',from.slice(5,7))+tag('numEstabRuc',String(p.establishments).padStart(3,'0'))+tag('totalVentas',cash(totalSales))+tag('codigoOperativo','IVA')+(purchases?'<compras>'+purchases+'</compras>':'')+(sales?'<ventas>'+sales+'</ventas>':'')+(establishments.size?'<ventasEstablecimiento>'+[...establishments].sort().map(([est,value])=>'<ventaEst>'+tag('codEstab',est)+tag('ventasEstab',cash(value))+'</ventaEst>').join('')+'</ventasEstablecimiento>':'')+(cancelled?'<anulados>'+cancelled+'</anulados>':'')+'</iva>';
 return {errors:[],xml,filename:`AT${from.slice(5,7)}${from.slice(0,4)}-revision.xml`,status:'draft_not_submitted'};
}
function codesSales(code){return code;}

return {buildAts};
});
