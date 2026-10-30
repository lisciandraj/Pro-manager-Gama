const fs=require('node:fs'),path=require('node:path'),{performance}=require('node:perf_hooks'),assert=require('node:assert/strict');
const {restore}=require('./restore-schema.cjs'),{seed,roadMatrix}=require('../tests/helpers/tms-routing.cjs');
const root=path.join(__dirname,'..'),migration=fs.readdirSync(path.join(root,'supabase/migrations')).find(f=>f.endsWith('_tms_road_optimization.sql'));
function evaluate(routes,deliveries,points,matrix){
 const map=new Map(deliveries.map(d=>[d.id,d])),point=p=>points.findIndex(x=>Math.abs(x[0]-p.lng)<1e-6&&Math.abs(x[1]-p.lat)<1e-6);
 let km=0,minutes=0,late=0,served=0,shiftViolations=0;
 for(const r of routes){let prev=point(r.route_points.start),clock=480,paused=false;
  for(const id of r.stops.filter(x=>x!=='__depot')){
   const d=map.get(id),idx=point(d),drive=Math.ceil(matrix.durations[prev][idx]/60);km+=matrix.distances[prev][idx];let arrival=clock+drive;
   if(!paused&&arrival+d.service_minutes>=720){arrival+=30;paused=true}
   const limit=Number(id.slice(-12))%1000%5===0?960:1080;if(arrival>limit)late++;
   clock=arrival+d.service_minutes;prev=idx;served++;
  }
  const last=point(r.route_points.end);clock+=Math.ceil(matrix.durations[prev][last]/60);km+=matrix.distances[prev][last];if(!paused&&clock>=720)clock+=30;
  if(clock>1080)shiftViolations++;minutes+=clock-480;
 }
 return {km:Number(km.toFixed(2)),estimated_minutes:minutes,served,window_violations:late,window_compliance:served?Number((100*(served-late)/served).toFixed(2)):null,shift_violations:shiftViolations};
}
(async()=>{
 const results=[];
 for(const [count,vehicles] of [[20,2],[50,3],[100,5]]){
  const db=await restore({before:migration});
  try{
   const f=await seed(db,count,vehicles),{one,as,day}=f;
   await as();let at=performance.now();const baseline=await one('select gama_tms_plan_day($1::date)',[day]),baseMs=performance.now()-at;
   const oldRoutes=(await db.query('select * from tms_routes where route_date=$1',[day])).rows,deliveries=(await db.query('select * from tms_deliveries where delivery_date=$1',[day])).rows;
   await db.exec('reset role');await db.exec(fs.readFileSync(path.join(root,'supabase/migrations',migration),'utf8'));await as();
   const claim=await one('select gama_tms_routing($1,$2)',['claim',{day,scope:'b'.repeat(64)}]),matrix=roadMatrix(claim.points);
   await db.exec("reset role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);set role service_role");await one('select gama_tms_routing_commit($1)',[{...claim,...matrix}]);await db.exec("reset role;select set_config('request.jwt.claims','{}',false)");await as();
   at=performance.now();const optimized=await one('select gama_tms_plan_day($1::date)',[day]),optMs=performance.now()-at;
   const newRoutes=(await db.query('select * from tms_routes where route_date=$1',[day])).rows;
   const before=evaluate(oldRoutes,deliveries,claim.points,matrix),after=evaluate(newRoutes,deliveries,claim.points,matrix);
   assert.equal(optimized.routing.mode,'road');assert.equal(after.window_violations,0);assert.equal(after.shift_violations,0);assert.equal(after.served,count);
   const result={deliveries:count,vehicles,locations:claim.points.length,baseline:{...before,calculation_ms:Math.round(baseMs)},optimized:{...after,calculation_ms:Math.round(optMs)},km_change_percent:Number((100*(after.km-before.km)/before.km).toFixed(2)),minutes_change_percent:Number((100*(after.estimated_minutes-before.estimated_minutes)/before.estimated_minutes).toFixed(2))};
   results.push(result);console.log(JSON.stringify(result));
  }finally{await db.close()}
 }
 const output=process.argv[2];if(output)fs.writeFileSync(output,JSON.stringify({dataset:'synthetic directional grid; not real Quito routes; no live traffic',scope:'isolated PGlite, current planner versus road-aware native assignment plus bounded 2-opt; matrix acquisition excluded',results},null,2)+'\n');
})().catch(e=>{console.error(e);process.exitCode=1});
