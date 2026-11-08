/* Original Coco PDF assembly. This module is loaded only for enriched exports. */
(function(root){'use strict';
const sourceKeys=Object.freeze(['quote.reference','quote.date','quote.valid_until','quote.client_name','quote.client_id','quote.client_address','quote.client_email','quote.currency','quote.subtotal','quote.tax','quote.total','item.name','item.reference','item.quantity']);
const MAX_FILE=10485760,MAX_TOTAL=41943040,MAX_PAGES=300,MAX_ATTACHMENTS=20;
function lib(){if(!root.PDFLib?.PDFDocument)throw Error('PDF_COMPOSER_UNAVAILABLE');return root.PDFLib}
async function bytes(value){if(value instanceof Blob)return new Uint8Array(await value.arrayBuffer());if(value instanceof Uint8Array)return value;if(value instanceof ArrayBuffer)return new Uint8Array(value);throw Error('PDF_FILE_INVALID')}
function validateMappings(map){if(!map||Array.isArray(map)||typeof map!=='object'||Object.keys(map).length>100)throw Error('PDF_FIELD_MAPPING_INVALID');for(const [key,value]of Object.entries(map))if(!key||key.length>160||!sourceKeys.includes(value))throw Error('PDF_FIELD_MAPPING_INVALID');return map}
function value(source,q,item){const keys={'quote.reference':q.number,'quote.date':q.dateLabel,'quote.valid_until':q.validUntil,'quote.client_name':q.client,'quote.client_id':q.clientId,'quote.client_address':q.clientAddress,'quote.client_email':q.clientEmail,'quote.currency':q.currency,'quote.subtotal':q.sub,'quote.tax':q.tax,'quote.total':q.total,'item.name':item?.name,'item.reference':item?.reference,'item.quantity':item?.qty};return String(keys[source]??'').slice(0,4000)}
async function inspect(input){const data=await bytes(input);if(data.length<8||data.length>MAX_FILE||!String.fromCharCode(...data.slice(0,5)).startsWith('%PDF-'))throw Error('PDF_FILE_INVALID');let doc;try{doc=await lib().PDFDocument.load(data,{updateMetadata:false})}catch{throw Error('PDF_FILE_INVALID')}
 const count=doc.getPageCount();if(count<1||count>100||doc.getForm().hasXFA())throw Error('PDF_FILE_UNSUPPORTED');const fields=doc.getForm().getFields().map(f=>({name:f.getName(),type:f.constructor.name}));if(fields.length>100||fields.some(f=>f.name.length>160))throw Error('PDF_FILE_UNSUPPORTED');return{pages:count,fields};}
function clearField(form,field){if(typeof field.setText==='function')field.setText('');else if(typeof field.uncheck==='function')field.uncheck();else if(typeof field.clear==='function')field.clear();else form.removeField(field)}
async function fillAndSanitize(doc,map,q,item){const P=lib(),form=doc.getForm();if(form.hasXFA())throw Error('PDF_FILE_UNSUPPORTED');validateMappings(map||{});const font=await doc.embedFont(P.StandardFonts.Helvetica);
 const fields=form.getFields(),known=new Set(fields.map(f=>f.getName()));for(const key of Object.keys(map||{}))if(!known.has(key))throw Error('PDF_FIELD_NOT_FOUND');
 for(const field of fields){const source=map?.[field.getName()];if(!source){clearField(form,field);continue}const text=value(source,q,item);
  try{font.encodeText(text)}catch{throw Error('PDF_FIELD_ENCODING_INVALID')}
  try{if(typeof field.setText==='function')field.setText(text);else if(typeof field.check==='function'){if(/^(true|yes|1|sí|oui)$/i.test(text))field.check();else field.uncheck()}else if(typeof field.select==='function'){if(text)field.select(text);else field.clear()}else throw Error('PDF_FIELD_UNSUPPORTED')}catch(e){if(e.message==='PDF_FIELD_UNSUPPORTED')throw e;throw Error('PDF_FIELD_VALUE_INVALID')}
 }
 form.updateFieldAppearances(font);form.flatten({updateFieldAppearances:false});
 // Attachments are passive pages: strip launch actions, scripts, embedded-file
 // name trees and interactive annotations after explicitly filling form fields.
 for(const name of ['OpenAction','AA','Names','AcroForm'])doc.catalog.delete(P.PDFName.of(name));
 for(const page of doc.getPages())for(const name of ['AA','Annots'])page.node.delete(P.PDFName.of(name));
}
async function compose({body,documents,quote}){if(!Array.isArray(documents)||documents.length>MAX_ATTACHMENTS)throw Error('PDF_ATTACHMENT_LIMIT');if(documents.some(d=>!d||!['cover','product','footer'].includes(d.position)))throw Error('PDF_FILE_INVALID');const P=lib(),target=await P.PDFDocument.create();let total=0;
 const append=async(input,map,item,attached)=>{const data=await bytes(input);total+=data.length;if(total>MAX_TOTAL||attached&&data.length>MAX_FILE)throw Error('PDF_ATTACHMENT_LIMIT');let doc;try{doc=await P.PDFDocument.load(data,{updateMetadata:false})}catch{throw Error('PDF_FILE_INVALID')}
  if(target.getPageCount()+doc.getPageCount()>MAX_PAGES)throw Error('PDF_ATTACHMENT_LIMIT');if(attached)await fillAndSanitize(doc,map||{},quote,item);
  for(const page of await target.copyPages(doc,doc.getPageIndices()))target.addPage(page);
 };
 for(const d of documents.filter(d=>d.position==='cover'))await append(d.bytes,d.field_map,d.item,true);
 await append(body,{},null,false);
 for(const d of documents.filter(d=>d.position==='product'))await append(d.bytes,d.field_map,d.item,true);
 for(const d of documents.filter(d=>d.position==='footer'))await append(d.bytes,d.field_map,d.item,true);
 for(const page of target.getPages())for(const name of ['AA','Annots'])page.node.delete(P.PDFName.of(name));
 target.setTitle(String(quote.number||'').slice(0,200));target.setProducer('Coco ERP');target.setCreator('Coco ERP');return new Blob([await target.save({useObjectStreams:false})],{type:'application/pdf'});
}
root.CocoQuoteDocumentCompose={sourceKeys,validateMappings,inspect,compose,limits:{file:MAX_FILE,total:MAX_TOTAL,pages:MAX_PAGES,attachments:MAX_ATTACHMENTS}};
})(typeof window==='undefined'?globalThis:window);
