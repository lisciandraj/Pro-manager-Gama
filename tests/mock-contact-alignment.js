/* Browser fixture only. Authorization, triggers and transactions are tested on PostgreSQL. */
;(()=>{
 const original=window.GamaCloud.db;
 window.GamaCloud.db=async()=>{const c=await original();return {...c,rpc:async(name,args)=>{
  if(!['coco_contact_record','coco_contact_save'].includes(name))return c.rpc(name,args);
  const db=window.__DB,table={clients:'customers',suppliers:'suppliers',people:'crm_contacts',prospects:'crm_contacts',leads:'crm_leads'}[args.p_kind];
  const versions=window.__CONTACT_VERSIONS||(window.__CONTACT_VERSIONS={});
  let row=(db[table]||[]).find(r=>r.id===args.p_id);
  if(name==='coco_contact_save'){
   if(args.p_id&&!row)return {error:{message:'CONTACT_NOT_FOUND'}};
   if(row&&args.p_version!==(versions[row.contact_entity_id||row.id]||1))return {error:{message:'CONTACT_VERSION_CONFLICT'}};
   if(!row){row={id:crypto.randomUUID(),active:true,...(table==='customers'?{category:'A'}:{}),...(table==='crm_contacts'?{address_mode:'parent'}:{})};(db[table]||(db[table]=[])).push(row)}
   Object.assign(row,args.p_data);const eid=row.contact_entity_id||row.id;versions[eid]=(versions[eid]||1)+1;
   if(row.contact_entity_id)for(const t of ['customers','suppliers','crm_leads'])for(const peer of db[t]||[])if(peer!==row&&peer.contact_entity_id===row.contact_entity_id){for(const k of ['email','phone','phone2','address','city','province','postal_code','country','lat','lng','website','industry','language'])if(Object.hasOwn(args.p_data,k))peer[k]=args.p_data[k];}
  }
  if(!row)return {error:{message:'CONTACT_NOT_FOUND'}};
  const version=versions[row.contact_entity_id||row.id]||1;
  const parent=table==='crm_contacts'&&row.address_mode!=='own'?(db.customers||[]).find(c=>c.id===row.customer_id)||(db.crm_leads||[]).find(l=>l.id===row.lead_id):null;
  const inherited=parent?{id:parent.id,name:parent.name||parent.company,...Object.fromEntries(['address','city','province','postal_code','country','lat','lng'].map(k=>[k,parent[k]??null]))}:null;
  return {data:{record:{...row},profile:{id:row.contact_entity_id||row.id,version,tags:[],website:row.website||null,industry:row.industry||null,language:row.language||null,alignment_conflicts:{}},version,inherited_address:inherited}};
 }}};
})();
