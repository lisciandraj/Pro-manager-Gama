/** Provider-neutral domestic invoice contract. No network, sequence allocation or writes.
 * Decimal strings + integer arithmetic keep the exact amounts of the saved invoice.
 * A valid DTO is preparation only; each supplier still needs a reviewed adapter.
 */
export function invoiceContract({invoice, settings = {}, company = {}, issue = null, paymentCode = ''}) {
  const errors = [], warnings = [];
  const problem = (field, code = 'required') => errors.push({field, code});
  const text = v => typeof v === 'string' ? v.trim() : '';
  const required = (value, field, max = 300) => {
    const v = text(value);
    if (!v || v.length > max) problem(field, v ? 'length' : 'required');
    return v;
  };
  const digits = (value, field, count) => {
    const v = text(value); if (!new RegExp(`^[0-9]{${count}}$`).test(v)) problem(field, 'format'); return v;
  };
  const decimal = (value, scale, field) => {
    const s = String(value ?? '');
    if (!new RegExp(`^\\d{1,12}(?:\\.\\d{1,${scale}})?$`).test(s)) { problem(field, 'decimal'); return 0n; }
    const [a,b = ''] = s.split('.'); return BigInt(a) * 10n ** BigInt(scale) + BigInt(b.padEnd(scale, '0'));
  };
  const fixed = (v, scale = 2) => { const s = v.toString().padStart(scale + 1, '0'); return s.slice(0,-scale) + '.' + s.slice(-scale); };
  const round = (n,d) => (n + d / 2n) / d;
  const date = (v, field) => {
    const s = text(v);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(s) || !Number.isFinite(Date.parse(s)) || new Date(s).toISOString().slice(0,10) !== s) problem(field,'date');
    return s;
  };
  const frozen = issue?.snapshot;
  const saved = invoice.document_snapshot || {};
  const details = saved.details || {};
  const s = frozen || {
    issue_date:invoice.issue_date, due_date:invoice.due_date, source_number:invoice.number,
    source_order_id:invoice.order_id, source_quote_id:invoice.source_quote_id,
    currency:company.currency, issuer:settings.razon_social, address:settings.dir_matriz,
    accounting_obligation:settings.accounting_obligation, trade_name:settings.trade_name,
    establishment_address:settings.establishment_address, provider_ruc:settings.provider_ruc,
    customer:saved.customer, identification:saved.customer_identification,
    customer_address:details.clientAddress, customer_email:details.clientEmail,
    payment_code:paymentCode, subtotal:invoice.subtotal, tax:invoice.tax, total:invoice.total,
    lines:Array.isArray(saved.lines) ? saved.lines.map(entry => {const l=entry && typeof entry==='object' ? entry : {};return ({
      source_line_id:l.line_id, product_id:l.product_id, code:l.reference, description:l.name,
      quantity:l.qty, unit_price:l.price, tax_rate:l.taxRate, subtotal:l.subtotal, tax:l.tax,
      list_price:l.listPrice, discount_percent:l.discount
    });}) : []
  };
  if (invoice.document_kind !== 'internal') problem('source','internal_invoice_required');
  if (issue && issue.source_invoice_id !== invoice.id) problem('source','mismatch');
  if (invoice.fiscal_status !== 'unverified' || invoice.external_number) warnings.push({field:'source',code:'already_linked_or_cancelled'});
  if (!frozen && (!company.configured || company.country !== 'EC' || settings.ruc !== company.tax_id)) problem('issuer','configuration');
  const environment = issue?.environment || settings.environment;
  if (!['pruebas','produccion'].includes(environment)) problem('document.environment','required');
  const currency = s.currency || (frozen ? 'USD' : '');
  if (currency !== 'USD') problem('document.currency','unsupported');
  const issuer = {
    ruc:digits(issue?.issuer_ruc || settings.ruc, 'issuer.ruc',13),
    legal_name:required(s.issuer,'issuer.legal_name'),
    trade_name:text(s.trade_name), address:required(s.address,'issuer.address'),
    establishment_address:text(s.establishment_address) || text(s.address),
    accounting_obligation:text(s.accounting_obligation),
    software_provider_ruc:digits(s.provider_ruc,'issuer.software_provider_ruc',13)
  };
  if (!['SI','NO'].includes(issuer.accounting_obligation)) problem('issuer.accounting_obligation','required');
  const identification = required(s.identification,'buyer.identification',20);
  // No invented check-digit algorithm for RUC; SRI does not prescribe one for all RUCs.
  const identityType = /^\d{13}$/.test(identification) ? '04' : /^\d{10}$/.test(identification) ? '05' : null;
  if (!identityType || identification === '9999999999999') problem('buyer.identification','unsupported');
  const buyer = {identification_type:identityType,identification,
    legal_name:required(s.customer,'buyer.legal_name'),address:required(s.customer_address,'buyer.address'),email:text(s.customer_email)};
  if (!buyer.email) warnings.push({field:'buyer.email',code:'missing_notification_email'});
  else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(buyer.email) || buyer.email.length > 300) problem('buyer.email','format');
  const issueDate = date(s.issue_date,'document.issue_date');
  const dueDate = s.due_date ? date(s.due_date,'document.due_date') : null;
  if (dueDate && dueDate < issueDate) problem('document.due_date','before_issue_date');
  const codes = {'0':'0','5':'5','12':'2','13':'10','14':'3','15':'4'};
  const rawLines = Array.isArray(s.lines) ? s.lines : [];
  if (!rawLines.length || rawLines.length > 1000) problem('lines','count');
  let net = 0n, vat = 0n;
  const groups = new Map();
  const lines = rawLines.slice(0,1000).map((entry,index) => {
    const l = entry && typeof entry === 'object' ? entry : {};
    const path = `lines.${index + 1}`;
    const quantity = decimal(l.quantity,6,path+'.quantity'), price = decimal(l.unit_price,6,path+'.unit_price');
    if (quantity === 0n) problem(path+'.quantity','positive');
    const rate = decimal(l.tax_rate,2,path+'.tax.rate');
    const percentageCode = codes[(rate / 100n).toString()];
    if (!percentageCode || rate % 100n !== 0n) problem(path+'.tax.rate','unsupported');
    const base = round(quantity * price,10000000000n), tax = round(base * rate,10000n);
    if (decimal(l.subtotal,2,path+'.subtotal') !== base) problem(path+'.subtotal','mismatch');
    if (l.tax != null && decimal(l.tax,2,path+'.tax.amount') !== tax) problem(path+'.tax.amount','mismatch');
    net += base; vat += tax;
    const key = percentageCode || 'unsupported';
    const g = groups.get(key) || {code:'2',percentage_code:percentageCode,rate:fixed(rate),base:0n,amount:0n};
    g.base += base; g.amount += tax; groups.set(key,g);
    return {line_number:index+1,source_line_id:l.source_line_id || null,product_id:l.product_id || null,
      code:required(l.code,path+'.code',25),description:required(l.description,path+'.description'),
      quantity:fixed(quantity,6),unit_price:fixed(price,6),discount:'0.00',subtotal:fixed(base),
      tax:{code:'2',percentage_code:percentageCode,rate:fixed(rate),base:fixed(base),amount:fixed(tax)},
      commercial:{list_price:l.list_price == null ? null : String(l.list_price),discount_percent:l.discount_percent == null ? null : String(l.discount_percent)}};
  });
  for (const [field,value] of [['subtotal',net],['tax',vat],['total',net+vat]]) {
    if (decimal(s[field],2,'totals.'+field) !== value) problem('totals.'+field,'mismatch');
  }
  const payment = text(s.payment_code);
  if (!['01','16','19','20'].includes(payment)) problem('payments.1.code','unsupported');
  const termDays = dueDate && !errors.some(e=>e.field.startsWith('document.')) ? Math.round((Date.parse(dueDate)-Date.parse(issueDate))/86400000) : null;
  const payload = {
    schema_version:'coco.sri.invoice.v1',
    source:{invoice_id:invoice.id,internal_number:s.source_number || invoice.number,order_id:s.source_order_id || invoice.order_id || null,quote_id:s.source_quote_id || invoice.source_quote_id || null},
    document:{code:'01',environment,currency,issue_date:issueDate,due_date:dueDate,
      numbering_owner:'coco',establishment:digits(issue?.establishment || settings.estab,'document.establishment',3),
      emission_point:digits(issue?.emission_point || settings.pto_emi,'document.emission_point',3),
      sequential:issue?.sequential || null,numeric_code:issue?.numeric_code || null},
    issuer,buyer,pricing_basis:'net_unit_price',lines,
    totals:{subtotal:fixed(net),discount:'0.00',tax:fixed(vat),tip:'0.00',total:fixed(net+vat)},
    tax_totals:[...groups.values()].map(g=>({...g,base:fixed(g.base),amount:fixed(g.amount)})),
    payments:[{code:payment,total:fixed(net+vat),term_days:termDays,time_unit:termDays === null ? null : 'dias'}],
    additional_information:[{name:'RUC Proveedor',value:issuer.software_provider_ruc}]
  };
  const state = issue?.status || 'unprepared';
  return {schema_version:payload.schema_version,valid:errors.length===0,
    emission_enabled:false,mode:issue?'frozen':'preview',issue_id:issue?.id || null,status:state,
    idempotency_key:issue ? `coco:sri:01:${issue.environment}:${issue.id}` : null,
    can_prepare:!issue && invoice.fiscal_status==='unverified' && !invoice.external_number && errors.length===0,
    requires_provider_adapter:true,errors,warnings,payload};
}
