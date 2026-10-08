const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
test('lightweight notification count equals the full snapshot across roles, preferences and snoozes',async()=>{
 const db=await restore();try{
  for(const [i,role] of ['administrador','comercial','almacenero','cliente'].entries())await db.exec(`insert into auth.users(id,email) values('${id(i+1)}','badge-${i}@example.invalid');update public.profiles set role='${role}',active=true where id='${id(i+1)}';`);
  await db.exec(`insert into public.products(name,reference,min_stock,stock) select 'Badge fixture '||i,'BADGE-'||i,5,0 from generate_series(1,200) i;insert into public.customers(id,name) values('${id(10)}','Badge customer');insert into public.invoices(customer_id,user_id,quote_state,quote_sent_at,quote_valid_until,quote_revision,quote_details) values('${id(10)}','${id(1)}','sent',now()-interval '8 days',current_date-1,1,'{"client":"Badge customer"}');`);
  for(const who of [1,2,3]){
   await db.exec(`select set_config('request.jwt.claim.sub','${id(who)}',false);set role authenticated;`);
   for(const opts of [{},{respect_preferences:true},{respect_preferences:true,notification_class:'action'},{respect_preferences:true,notification_class:'information'}]){
    const first=performance.now();const full=(await db.query("select public.gama_operations_action('snapshot',$1) value",[JSON.stringify(opts)])).rows[0].value;const middle=performance.now();const badge=(await db.query("select public.gama_operations_action('badge',$1) value",[JSON.stringify(opts)])).rows[0].value;
    assert.equal(badge.active_count,full.active_count);assert.deepEqual(Object.keys(badge).sort(),['active_count','generated_at']);
    if(who===1&&!Object.keys(opts).length)console.log('BADGE_BENCHMARK '+JSON.stringify({snapshot_ms:middle-first,badge_ms:performance.now()-middle,full_bytes:JSON.stringify(full).length,badge_bytes:JSON.stringify(badge).length}));
   }
   await db.exec('reset role');
  }
  await db.exec(`select set_config('request.jwt.claim.sub','${id(1)}',false);insert into public.erp_notification_preferences(user_id,hidden_kinds,only_mine) values('${id(1)}',array['low_stock'],true);insert into private.gama_alert_handling(alert_key,fingerprint,status,assigned_to,snoozed_until,note,updated_by) select alert_key,md5(kind||coalesce(detail,'')||coalesce(since::text,'')),'snoozed','${id(1)}',now()+interval '1 day','test','${id(1)}' from private.gama_live_alerts where kind='quote';set role authenticated;`);
  for(const opts of [{respect_preferences:true},{respect_preferences:false}]){const r=(await db.query("select public.gama_operations_action('badge',$1)->'active_count' badge,public.gama_operations_action('snapshot',$1)->'active_count' full",[JSON.stringify(opts)])).rows[0];assert.equal(r.badge,r.full)}
  await db.exec(`reset role;select set_config('request.jwt.claim.sub','${id(4)}',false);set role authenticated;`);await assert.rejects(()=>db.query("select public.gama_operations_action('badge')"),/ROLE_NOT_ALLOWED/);
  await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);set role authenticated;");await assert.rejects(()=>db.query("select public.gama_operations_action('badge')"),/AUTH_OR_MFA_REQUIRED/);
 }finally{await db.close()}
});
