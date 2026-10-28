const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20261028175918_coco_three_workstreams.sql';
test('three continuations preserve history, calculate exact depreciation, filter GPS gaps and keep agenda source rights',async t=>{
 const db=await restore({before:migration}),admin=uuid(),colleague=uuid(),client=uuid();
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0]||{})[0];
 const api=(fn,action,data={})=>v('select public.'+fn+'($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const audit=(action,data={})=>api('gama_accounting_audit',action,{request_key:uuid(),...data});
 const actor=async(id,role='postgres')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback');await actor(admin)}});
 const deny=async(fn,re)=>{await db.exec('savepoint denied');try{await assert.rejects(fn(),re)}finally{await db.exec('rollback to denied;release denied')}};
 const calendar=data=>v('select public.coco_workhub_calendar($1::jsonb)',[JSON.stringify({from:'2026-10-01',to:'2026-10-31',...data})]);
 let chart,assetAccount,accumulated,project,old;
 const asset=async(extra={})=>{
  const eid=await v("select private.gama_accounting_book('OD','2026-01-01','Isolated acquisition','manual',null,'Documented fixture',$1::jsonb)",[JSON.stringify([{account_id:assetAccount,debit:1000},{account_id:chart['3000'],credit:1000}])]);
  return (await api('gama_accounting_ec','asset_save',{request_key:uuid(),name:'Isolated vehicle',acquired_on:'2026-01-01',first_depreciation:'2026-01-01',cost:1000,residual:100,months:5,asset_account_id:assetAccount,depreciation_account_id:accumulated,expense_account_id:chart['6080'],acquisition_entry_id:eid,...extra})).id;
 };
 const schedule=id=>v('select jsonb_agg(amount order by period) from private.accounting_asset_schedules where asset_id=$1',[id]);
 try{
  for(const [id,role]of [[admin,'administrador'],[colleague,'comercial'],[client,'cliente']]){await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set active=true,role=$2 where id=$1',[id,role])}
  await actor(admin);chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('6080','3000')")).rows.map(x=>[x.code,x.id]));
  assetAccount=await v("insert into accounting_accounts(code,name,type) values('QA-ASSET','Isolated asset','asset') returning id");accumulated=await v("insert into accounting_accounts(code,name,type) values('QA-ACCUM','Isolated accumulated','asset') returning id");
  old=await asset();await audit('asset_policy_save',{id:old,prorata:false});await audit('asset_depreciate',{id:old,period:'2026-01-31'});
  const snapshot=async()=>{const r={};for(const name of ['public.accounting_assets','public.accounting_entries','public.accounting_entry_lines','public.accounting_depreciations','private.accounting_asset_schedules','private.coco_module_events']){const row=name==='public.accounting_assets'?"to_jsonb(t)-'depreciation_method'-'declining_factor'-'depreciation_prorata'":'to_jsonb(t)';r[name]=await v(`select md5(coalesce(jsonb_agg(${row} order by (${row})::text),'[]')::text) from ${name} t`)}return r};
  const before=await snapshot();await db.exec(fs.readFileSync(__dirname+'/../supabase/migrations/'+migration,'utf8'));
  assert.deepEqual(await snapshot(),before,'schema upgrade preserves all historical business values and history');
  await scenario('declining applies the monthly factor and catches up the final cent-exact balance',async()=>{
   const id=await asset(),entryCount=await v('select count(*) from accounting_entries');
   const p={id,method:'declining',declining_factor:'0.4',prorata:false,request_key:uuid()};assert.equal((await audit('asset_policy_save',p)).method,'declining');assert.deepEqual(await schedule(id),[360,216,129.6,77.76,116.64]);
   assert.equal(await v('select count(*) from accounting_entries'),entryCount,'schedule creation does not post depreciation');assert.deepEqual(await audit('asset_policy_save',p),await audit('asset_policy_save',p));
   await audit('asset_depreciate',{id,period:'2026-01-31'});assert.equal(Number(await v('select amount from accounting_depreciations where asset_id=$1',[id])),360);
   await deny(()=>audit('asset_policy_save',{id,method:'linear'}),/ASSET_SCHEDULE_LOCKED/);
   assert.equal(Number(await v('select sum(debit-credit) from accounting_entry_lines')),0);
  });
  await scenario('declining then straight line switches to a constant remainder',async()=>{
   const id=await asset();await audit('asset_policy_save',{id,method:'declining_linear',declining_factor:'0.4'});assert.deepEqual(await schedule(id),[360,216,129.6,97.2,97.2]);
   const r=(await audit('assets')).rows.find(x=>x.id===id);assert.equal(r.depreciation_method,'declining_linear');assert.equal(r.declining_factor,.4);
  });
  await scenario('proration, leap dates and small residuals never create negative amounts or lose cents',async()=>{
   const id=await asset({acquired_on:'2026-01-10',first_depreciation:'2026-01-10'});await audit('asset_policy_save',{id,method:'declining_linear',declining_factor:'0.4',prorata:true});
   assert.equal((await schedule(id)).length,6);assert.equal(Number(await v('select sum(amount) from private.accounting_asset_schedules where asset_id=$1',[id])),900);assert.equal(await v('select count(*)::int from private.accounting_asset_schedules where asset_id=$1 and amount<0',[id]),0);
   const tiny=await asset({cost:1,residual:.95,months:5});await audit('asset_policy_save',{id:tiny,method:'declining_linear',declining_factor:'0.9'});assert.equal(Number(await v('select sum(amount) from private.accounting_asset_schedules where asset_id=$1',[tiny])),.05);
   const leap=await asset({acquired_on:'2024-02-29',first_depreciation:'2024-02-29'});await audit('asset_policy_save',{id:leap,method:'declining',declining_factor:'0.2',prorata:true});assert.equal(await v('select min(period)::text from private.accounting_asset_schedules where asset_id=$1',[leap]),'2024-02-29');
  });
  await scenario('invalid factors, stale policies, AI approval and private helper access are rejected',async()=>{
   const id=await asset();for(const factor of [null,'0','1','NaN','0.1234567'])await deny(()=>audit('asset_policy_save',{id,method:'declining',declining_factor:factor}),/ASSET_FACTOR_INVALID/);
   await deny(()=>audit('asset_policy_save',{id,method:'arbitrary'}),/ASSET_METHOD_INVALID/);
   await deny(()=>audit('asset_policy_save',{id,expected_policy:{method:'declining'}}),/DOCUMENT_CHANGED/);
   await q("select set_config('coco.activity_source_type','chat',true)");await deny(()=>audit('asset_policy_save',{id,method:'linear'}),/HUMAN_APPROVAL/);
   await q("select set_config('coco.activity_source_type','',true)");await deny(()=>audit('asset_policy_save',{id:old,method:'declining',declining_factor:'.4'}),/ASSET_SCHEDULE_LOCKED/);
   assert.equal(await v("select has_function_privilege('authenticated','private.coco_asset_policy(uuid,jsonb)','EXECUTE')"),false);
  });
  await scenario('GPS sums only short precise plausible segments, preserving gaps and zero distance',async()=>{
   const rid=await v("insert into tms_routes(route_date,driver_name) values('2026-10-20','Isolated trace') returning id");
   const points=[[0,0,10,0],[0,.001,10,60],[0,.002,10,120],[0,.003,10,720],[0,.004,100,780],[0,.005,10,840],[0,20,10,900],[0,20,10,960]];
   for(const [lat,lng,accuracy,sec]of points)await q("insert into private.tms_pro_positions(id,route_id,actor_id,lat,lng,accuracy,observed_at) values($1,$2,$3,$4,$5,$6,'2026-10-20T12:00:00Z'::timestamptz+make_interval(secs=>$7))",[uuid(),rid,admin,lat,lng,accuracy,sec]);
   const data=await api('gama_tms_pro','analytics',{from:'2026-10-20',to:'2026-10-20'}),trace=data.routes.find(x=>x.id===rid).trace;
   assert.equal(trace.accepted_segments,3);assert.equal(trace.excluded_segments,4);assert.equal(trace.observed_km,.222);assert.equal(trace.observed_minutes,3);assert.equal(trace.max_gap_seconds,600);assert.equal(trace.basis,'gps_chords_partial');
   const none=await v('select private.coco_tms_trace($1)',[uuid()]);assert.equal(none.observed_km,null);assert.equal(none.accepted_segments,0);
   assert.equal(await v("select has_function_privilege('authenticated','private.coco_tms_trace(uuid)','EXECUTE')"),false);
   await actor(client,'authenticated');await deny(()=>api('gama_tms_pro','analytics',{from:'2026-10-20',to:'2026-10-20'}),/NOT_ALLOWED|ROLE|FORBIDDEN|ACCESS_DENIED/);
  });
  project=(await api('gama_projects_action','create_project',{name:'Agenda sources',start_date:'2026-10-01',due_date:'2026-12-31',request_key:uuid()})).project_id;
  await scenario('agenda is personally scoped, bounded, paginated and uses the company civil day',async()=>{
   for(const [title,owner,due,status]of [['Owned task',admin,'2026-10-02','todo'],['Colleague task',colleague,'2026-10-02','todo'],['Done task',admin,'2026-10-03','done'],['No date',admin,null,'todo']])await q("insert into pm_items(project_id,kind,title,owner_id,due_date,status,created_by) values($1,'task',$2,$3,$4,$5,auth.uid())",[project,title,owner,due,status]);
   const customer=await v("insert into customers(name,address) values('Agenda customer','Quito') returning id");await q("insert into crm_activities(customer_id,kind,subject,owner_id,due_at,status) values($2,'tarea','Quito October', $1,'2026-11-01T04:59:00Z','pendiente'),($2,'tarea','Quito November',$1,'2026-11-01T05:00:00Z','pendiente'),($2,'tarea','Completed CRM',$1,'2026-10-03T12:00:00Z','hecha')",[admin,customer]);
   await actor(admin,'authenticated');const data=await calendar({limit:1});assert.equal(data.total,2);assert.equal(data.rows.length,1);assert.equal(data.rows[0].title,'Owned task');assert.equal(data.timezone,'America/Guayaquil');
   const next=await calendar({offset:1,limit:1});assert.equal(next.rows[0].title,'Quito October');assert.equal(next.rows[0].calendar_day,'2026-10-31');
   await deny(()=>calendar({to:'2027-10-31'}),/CALENDAR_PERIOD/);await deny(()=>calendar({from:null}),/CALENDAR_PERIOD/);
   await actor(client,'authenticated');await deny(()=>calendar(),/FORBIDDEN/);await actor(admin,'anon');await deny(()=>calendar(),/permission denied/);
  });
  await scenario('agenda rechecks module rights without granting source access',async()=>{
   await q("insert into pm_items(project_id,kind,title,owner_id,due_date,status,created_by) values($1,'task','Restricted task',$2,'2026-10-02','todo',auth.uid())",[project,colleague]);
   await v("select gama_save_role_module_access('comercial',array['projects'],0)");await actor(colleague,'authenticated');assert.equal((await calendar()).total,0);
  });
 }finally{await db.close()}
});
