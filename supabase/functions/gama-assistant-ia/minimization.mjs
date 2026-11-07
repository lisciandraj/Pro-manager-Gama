/* Policy is evaluated from the human question before the model sees a catalog.
   It narrows provider disclosure; it never substitutes for database RLS. */
const personal=new Set(['identification','customer_identification','tax_id','issuer_ruc','ruc','address','delivery_address','city','province','phone','email','contact_name','notes','decision_reason','reason','comment','properties']);
const payroll=new Set(['salary','gross','net','employer_cost','bank_account','account_number','contract_type']);
export function questionScope(question){
 const q=String(question).normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 return {
  hr:/\b(hr|rh|rrhh|payroll|nomina|salary|salaries|salaires?|salari[oa]s?|sueldo|emplead[oa]s?|employees?|employes?|absences?|ausencias?|vacacion(?:es)?|conges?|personnel|recursos humanos|remuneration)\b/.test(q),
  payroll:/payroll|nomina|salary|salari|salair|sueldo|remuneration/.test(q),
  contacts:/contact|cliente|customer|proveedor|supplier|fournisseur|email|correo|telephone|telefono|direccion|address|identific|ruc/.test(q),
  stock:/stock|inventar|existencia|reposicion|reorder|producto|product|almacen/.test(q),
  finance:/factur|invoice|cobro|pago|payment|receiv|creance|finance|contab|accounting/.test(q),
  knowledge:/knowledge|article|connaissance|conocimiento|guide|manual|procedure|procedimiento|politica/.test(q),
  workspace:/workspace|workhub|canal|channel|proyecto|project|discussion|discusion/.test(q)
 };
}
export function minimizeCatalog(catalog,scope){
 const inventoryModules=new Set(['products','warehouses','stock','gamaPurchasesV14','suppliers']);
 return catalog.filter(t=>t.table!=='profiles'&&(t.module!=='hr'||scope.hr)&&(!(scope.stock&&!scope.finance&&!scope.hr)||inventoryModules.has(t.module))&&(!(scope.hr&&!scope.finance&&!scope.stock)||t.module==='hr')).map(t=>({...t,columns:t.columns.filter(c=>!(!scope.contacts&&personal.has(c))&&!(!scope.payroll&&payroll.has(c)))}));
}
export function minimizeOverview(overview,scope){
 const data={...overview};
 if(!scope.hr)delete data.hr;
 if(data.coverage)data.coverage=data.coverage.filter(t=>scope.hr||t.module!=='hr');
 if(data.receivables)data.receivables={...data.receivables,rows:scope.finance?(data.receivables.rows||[]).map(r=>({id:r.id,number:r.number,balance:r.balance,due_date:r.due_date,payment_status:r.payment_status,...(scope.contacts?{customer_name:r.customer_name}:{})})):[]};
 // A product-specific question needs no financial or personal team overview.
 if(scope.stock&&!scope.finance&&!scope.hr){for(const k of ['sales','receivables','purchases','logistics','crm','knowledge'])delete data[k];}
 if(scope.hr&&!scope.finance&&!scope.stock){for(const k of ['stock','sales','receivables','purchases','logistics','crm','knowledge'])delete data[k];}
 return data;
}
export function scopedQuery(query,catalog){
 const spec=catalog.find(t=>t.table===query?.table);if(!spec)throw Error('TABLE_NOT_ALLOWED');
 const refs=[...(query.columns||[]),...(query.group_by||[]),...(query.filters||[]).map(f=>f.column),query.column,query.order_by].filter(Boolean);
 if(refs.some(c=>!spec.columns.includes(c)))throw Error('COLUMN_NOT_ALLOWED');
 return query.operation==='rows'&&(!Array.isArray(query.columns)||!query.columns.length)?{...query,columns:spec.columns}:query;
}
export function minimizeHistory(history,scope={}){
 // Prior answers may contain unrelated private records. The current request's
 // question and scoped tools are the only disclosure basis, not history IDs.
 return history.filter(h=>{const prior=questionScope(h.question);return (scope.hr||!prior.hr)&&(scope.contacts||!prior.contacts);}).map(h=>({question:String(h.question||'').slice(0,4000)}));
}
