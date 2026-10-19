// Local PGlite only. No network, credentials, DATABASE_URL or production access.
// 1,836 synthetic products, 1,795 synthetic image strings; three sequential
// trials per action and version. Stop on SQL error or a trial over 15 seconds.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{createHash}=require('node:crypto');
const {restore}=require('./restore-schema.cjs');
async function main(){
 const proposal=fs.readFileSync(path.join(__dirname,'../docs/audits/proposals/coco-storefront-projection.sql'),'utf8');
 const db=await restore({before:'20261019180838'});
 try{
  await db.exec(`insert into products(id,name,reference,category,sale_price,tax_rate,photo_data)
   select ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Product '||lpad(i::text,4,'0'),'BENCH-'||i,'Category '||(i%13),i,15,
    case when i<=1795 then 'data:image/webp;base64,'||repeat(md5(i::text),596) end
   from generate_series(1,1836) i;
   update private.website_products set public_featured=(right(product_id::text,2)::integer%5=0),public_brand='QA';
   update private.website_public_settings set config=config||'{"site_enabled":true,"show_prices":true}'::jsonb;
   analyze public.products;analyze private.website_products;`);
  const volume=(await db.query('select count(*)::int products,count(photo_data)::int photos,sum(length(photo_data))::bigint photo_characters from public.products')).rows[0];
  const result={database:(await db.query('select version() v')).rows[0].v,runtime:process.version,proposal_sha256:createHash('sha256').update(proposal).digest('hex'),environment:'isolated PGlite; synthetic data; before then after in the same process; no network/browser timings; host CPU not controlled',volume,trials:[]};
  const actions=[['bootstrap',{}],['catalog',{limit:30,offset:0}],['product',{id:'00000000-0000-4000-8000-000000000001'}]],expected=[];
  for(const variant of ['before','proposal']){
   if(variant==='proposal'){await db.exec('reset role');await db.exec(proposal)}
   await db.exec('set role anon');
   for(let trial=1;trial<=3;trial++)for(let i=0;i<actions.length;i++){
    const [action,data]=actions[i],start=performance.now();
    const response=(await db.query('select public.gama_storefront($1,$2) result',[action,data])).rows[0].result;
    const ms=Math.round((performance.now()-start)*10)/10;
    if(variant==='before'&&trial===1)expected[i]=response;else assert.deepEqual(response,expected[i]);
    const row={variant,trial,action,ms};result.trials.push(row);process.stderr.write(JSON.stringify(row)+'\n');
    if(ms>15000)throw Error('Stop criterion: single request exceeded 15 seconds');
   }
  }
  await db.exec('reset role');
  result.diagnostic_plan_query='select * from private.gama_storefront_projection order by featured desc,name,id limit 30';
  result.diagnostic_plan_note='Unpaged projection diagnostic; not the complete RPC plan or the materialized-page query.';
  result.plan=(await db.query('explain (analyze,buffers,format json) '+result.diagnostic_plan_query)).rows[0]['QUERY PLAN'];
  console.log(JSON.stringify(result,null,2));
 }finally{await db.close()}
}
main().catch(e=>{console.error(e);process.exitCode=1});
