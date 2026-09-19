import {entities} from '../domain/entities.js';
import {normalizeError} from '../domain/format.js';
const cache = new Map();
const cloud = () => { if (!window.GamaCloud) throw Error('NETWORK_ERROR'); return window.GamaCloud; };
export function invalidate(table) { for (const key of cache.keys()) if (!table || key.startsWith(table + ':')) cache.delete(key); }
export async function all(table, options = {}, cached = false) {
  const key=table+':'+JSON.stringify(options);
  if (cached && cache.has(key)) return cache.get(key);
  const pending=(async()=>{
    const data=[], seen=new Set(); let offset=0;
    for (let page=0;page<10000;page++) {
      const r=await cloud().list(table,{...options,order:options.order || 'id',range:[offset,offset+199]});
      if(r.error)return r;
      const rows=r.data || [];
      if(!rows.length)return {data,error:null};
      // Fail explicitly if a transport ignored the range; never silently truncate an export.
      const signature=JSON.stringify(rows.map(row=>row.id ?? row));
      if(seen.has(signature))throw Error('PAGINATION_RANGE_IGNORED');
      seen.add(signature); data.push(...rows); offset+=rows.length;
      if(typeof r.count==='number' && offset>=r.count)return {data,error:null};
    }
    throw Error('PAGINATION_LIMIT');
  })();
  if(cached)cache.set(key,pending);
  try {const r=await pending;if(r.error)cache.delete(key);return r;} catch(e){cache.delete(key);throw e;}
}
/** Bound IN filters as well as result ranges, so large document sets fit URL limits. */
export async function byIds(table,column,ids,options={},cached=false) {
  if(!/^[_a-z][_a-z0-9]*$/.test(column))throw Error('INVALID_FILTER_COLUMN');
  const keys=[...new Set(ids)],data=[];
  for(let i=0;i<keys.length;i+=100){
    const result=await all(table,{...options,in:{...options.in,[column]:keys.slice(i,i+100)}},cached);
    if(result.error)return result;
    data.push(...result.data);
  }
  return {data,error:null};
}
export async function page(entity, options = {}) {
  const schema=entities[entity];if(!schema)throw Error('UNKNOWN_ENTITY');
  const size=Math.min(100,Math.max(1,Number(options.pageSize)||20)), index=Math.max(0,Number(options.page)||0);
  const order=options.sort || schema.order;
  if(!schema.select.split(',').includes(order))throw Error('INVALID_SORT');
  const request={select:schema.select,count:'exact',order,ascending:options.ascending!==false,eq:{active:options.archived!==true},range:[index*size,(index+1)*size-1]};
  const term=String(options.search||'').trim();
  if(term)request.search={columns:schema.search,value:term};
  const result=await cloud().list(schema.table,request);
  if(result.error)throw result.error;
  if(typeof result.count!=='number')throw Error('COUNT_REQUIRED');
  return {items:(result.data||[]).map(schema.fromRow),total:result.count,page:index,pageSize:size,sort:order};
}
export async function rpc(name, data = {}) {
  const r=await rawRpc(name,data);
  if(r.error){const e=new Error(r.error.message || 'UNKNOWN_ERROR');Object.assign(e,r.error,{details:normalizeError(r.error)});throw e;}
  return r.data;
}
export async function rawRpc(name,data={}) {return (await cloud().db()).rpc(name,data);}
export const action = (domain, operation, data = {}) => rpc('gama_'+domain+'_action',{p_action:operation,p_data:data});
export function startDataEvents() {
  window.addEventListener('gama:data-change',event=>invalidate(event.detail?.table));
  window.addEventListener('gama:auth-change',()=>invalidate());
  window.addEventListener('gama:products-cloud-change',()=>invalidate('products'));
  window.addEventListener('gama:stock-cloud-change',()=>{invalidate('products');invalidate('stock_movements');});
  window.addEventListener('gama:sales-change',()=>{invalidate('invoices');invalidate('invoice_lines');invalidate('customers');});
}
