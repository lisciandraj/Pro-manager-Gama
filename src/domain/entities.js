/** Explicit public application contracts; SQL names are confined to these adapters. */
const text = value => value ?? '';
const number = value => Number(value ?? 0);
export const productFromRow = p => ({
  id:p.id, name:text(p.name), barcode:text(p.barcode), reference:text(p.reference), category:text(p.category),
  description:text(p.description), family:text(p.family), lines:text(p.lines), brand:text(p.brand), presentation:text(p.presentation),
  location:text(p.location), supplierId:p.supplier_id || null, minStock:number(p.min_stock), maxStock:number(p.max_stock),
  qtyPerCarton:number(p.qty_per_carton), weightG:number(p.weight_g), volumeCm3:number(p.volume_cm3), stock:number(p.stock),
  salePrice:number(p.sale_price), salePriceB:number(p.sale_price_b), purchasePrice:number(p.purchase_price), taxRate:Number(p.tax_rate ?? 15),
  active:p.active !== false, hasPhoto:!!(p.has_photo || p.photo_data), photo:text(p.photo_data)
});
export const customerFromRow = c => ({id:c.id, taxId:text(c.identification), name:text(c.name), category:c.category || 'A', address:text(c.address), phone:text(c.phone), email:text(c.email), city:text(c.city), province:text(c.province), notes:text(c.notes), paymentTermsDays:c.payment_terms_days ?? null, active:c.active !== false});
export const supplierFromRow = s => ({id:s.id, taxId:text(s.tax_id), name:text(s.name), contactName:text(s.contact_name), address:text(s.address), phone:text(s.phone), email:text(s.email), city:text(s.city), province:text(s.province), postalCode:text(s.postal_code), country:text(s.country), notes:text(s.notes), active:s.active !== false});
export const supplierToRow = s => ({name:s.name, tax_id:s.taxId || null, contact_name:s.contactName || null, address:s.address || null, phone:s.phone || null, email:s.email || null, city:s.city || null, province:s.province || null, postal_code:s.postalCode || null, country:s.country || null, notes:s.notes || null, active:s.active !== false});
// The remaining document editors use historical shapes. Conversion happens once here.
export const legacyProduct = p => {const x=productFromRow(p);return {...x, ref:x.reference, cat:x.category, loc:x.location, min:x.minStock, qtyCarton:x.qtyPerCarton, price:x.salePrice, purchase_price:x.purchasePrice, iva:x.taxRate, supplierId:x.supplierId || ''};};
export const legacyCustomer = c => {const x=customerFromRow(c);return {...x, cloudId:x.id, id:x.taxId, idType:'RUC'};};
export const legacySupplier = s => {const x=supplierFromRow(s);return {...x, tax:x.taxId, contact:x.contactName};};
export const entities = {
  suppliers:{table:'suppliers', select:'id,name,tax_id,contact_name,phone,email,city,address,province,postal_code,country,notes,active,created_at,updated_at', order:'name', search:['name','tax_id','contact_name','email','phone','city'], fromRow:supplierFromRow, toRow:supplierToRow},
  customers:{table:'customers', select:'id,name,identification,category,address,phone,email,city,province,notes,payment_terms_days,active,created_at,updated_at', order:'name', search:['name','identification','email','phone','city'], fromRow:customerFromRow},
  products:{table:'products', select:'id,barcode,name,description,reference,category,family,lines,brand,presentation,location,supplier_id,min_stock,max_stock,qty_per_carton,weight_g,volume_cm3,stock,sale_price,sale_price_b,purchase_price,tax_rate,active,has_photo,created_at,updated_at', order:'name', search:['name','barcode','reference','category'], fromRow:productFromRow}
};
export const supplierFields = [
  {id:'supName',key:'name',label:'Nombre / razón social',required:true,maxLength:300},
  {id:'supTax',key:'taxId',label:'RUC / identificación',maxLength:100},
  {id:'supContact',key:'contactName',label:'Persona de contacto',maxLength:200},
  {id:'supPhone',key:'phone',label:'Teléfono',type:'tel',maxLength:80},
  {id:'supEmail',key:'email',label:'Email',type:'email',maxLength:250},
  {id:'supCity',key:'city',label:'Ciudad / país',maxLength:200},
  {id:'supAddress',key:'address',label:'Dirección',maxLength:500},
  {id:'supNotes',key:'notes',label:'Información clave',type:'textarea',maxLength:4000}
];
