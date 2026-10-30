const {randomUUID:uuid}=require('node:crypto');
// Isolated, deliberately synthetic Quito-shaped directional road grid. This is
// not a municipal road extract or a traffic forecast.
function gridPoint(i){return {lat:Number((-.32+Math.floor(i/12)*.008).toFixed(6)),lng:Number((-78.54+(i%12)*.006).toFixed(6))}}
function roadMatrix(points){
 const nearest=p=>Math.max(0,Math.min(23,Math.round((p[1]+.32)/.008)))*12+Math.max(0,Math.min(11,Math.round((p[0]+78.54)/.006)));
 const ids=points.map(nearest),rows=new Map();
 for(const source of new Set(ids)){
  const time=Array(288).fill(Infinity),km=Array(288).fill(Infinity),seen=new Set();time[source]=km[source]=0;
  for(let k=0;k<288;k++){
   let a=-1;for(let i=0;i<288;i++)if(!seen.has(i)&&(a<0||time[i]<time[a]))a=i;
   if(a<0||!Number.isFinite(time[a]))break;seen.add(a);const r=Math.floor(a/12),c=a%12,edges=[];
   if(r>0)edges.push([a-12,.889,32]);if(r<23)edges.push([a+12,.889,38]);
   const east=r%2===0;
   if(c<11&&(east||r%6===0)&&!(c===5&&![2,12,21].includes(r)))edges.push([a+1,.667,r%6===0?45:22]);
   if(c>0&&(!east||r%6===0)&&!(c===6&&![2,12,21].includes(r)))edges.push([a-1,.667,r%6===0?45:18]);
   for(const [b,d,speed] of edges){const t=time[a]+d/speed*3600;if(t<time[b]){time[b]=t;km[b]=km[a]+d}}
  }
  rows.set(source,{time,km});
 }
 return {distances:ids.map(a=>ids.map(b=>Number(rows.get(a).km[b].toFixed(6)))),durations:ids.map(a=>ids.map(b=>Math.round(rows.get(a).time[b])))};
}
async function seed(db,count,vehicles){
 const admin=uuid(),customer=uuid(),order=uuid(),drivers=[],trucks=[],deliveries=[];
 const one=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];
 await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'routing-'+count+'@example.invalid']);
 await db.query("update profiles set active=true,role='administrador' where id=$1",[admin]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 const day=await one("select (now() at time zone private.erp_timezone())::date::text");
 await db.query("insert into customers(id,name) values($1,'Synthetic road client')",[customer]);
 await db.query("insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values($1,$2,'Synthetic road client',$3,$4,'confirmed')",[order,customer,admin,uuid()]);
 await db.exec("update fleet_drivers set active=false;update private.tms_pro_settings set balance='orders';update private.tms_dispatch_config set max_stops=50");
 const depot=gridPoint(145);
 await db.query("insert into tms_settings(id,depot,depot_lat,depot_lng,return_depot) values(true,'Synthetic depot',$1,$2,true) on conflict(id) do update set depot_lat=excluded.depot_lat,depot_lng=excluded.depot_lng,return_depot=true",[depot.lat,depot.lng]);
 for(let i=0;i<vehicles;i++){
  const dr='72000000-0000-0000-0000-'+String(count*100+i).padStart(12,'0'),v='73000000-0000-0000-0000-'+String(count*100+i).padStart(12,'0');drivers.push(dr);trucks.push(v);
  await db.query("insert into fleet_drivers(id,name,active) values($1,$2,true)",[dr,'Synthetic driver '+i]);
  await db.query("insert into fleet_vehicles(id,plate,brand,model,kind,energy,payload_kg,cargo_volume_m3) values($1,$2,'Test','Van','truck','other',1000,30)",[v,'ROAD-'+count+'-'+i]);
  await db.query('insert into fleet_assignments(vehicle_id,driver_id,started_on) values($1,$2,$3)',[v,dr,day]);
  const start=gridPoint(140+i*3),end=gridPoint(143+i*3);
  await db.query("insert into private.tms_pro_driver_rules(driver_id,skills,shift_start,shift_end,start_location,end_location,end_mode) values($1,array['handling'],'08:00','18:00',$2,$3,'custom')",[dr,{...start,label:'Start '+i},{...end,label:'Return '+i}]);
  await db.query("insert into private.tms_pro_vehicle_rules(vehicle_id,features,capacities) values($1,array['covered'],'{\"boxes\":60}')",[v]);
 }
 await db.exec("update private.tms_pro_settings set dimensions='[{\"key\":\"boxes\",\"label\":\"Boxes\",\"unit\":\"box\"}]';begin;set session_replication_role=replica");
 for(let i=0;i<count;i++){
  const id='74000000-0000-0000-0000-'+String(count*1000+i).padStart(12,'0'),p=gridPoint((i*73+17)%288);deliveries.push(id);
  await db.query("insert into tms_deliveries(id,customer,address,delivery_date,weight,volume,lat,lng,service_minutes,priority) values($1,'Synthetic client','Synthetic address',$2,10,0.1,$3,$4,4,$5)",[id,day,p.lat,p.lng,i%11===0?'Alta':'Normal']);
  await db.query("insert into sales_deliveries(number,order_id,request_key,tms_delivery_id,created_by,loading_required) values($1,$2,$3,$4,$5,false)",['SYN-'+count+'-'+i,order,uuid(),id,admin]);
  await db.query("insert into private.tms_pro_order_rules(delivery_id,skills,features,driver_id,windows,loads) values($1,array['handling'],array['covered'],$2,$3,'{\"boxes\":1}')",[id,i%23===0?drivers[0]:null,[{from:'08:00',to:i%5===0?'16:00':'18:00'}]]);
 }
 await db.exec('set session_replication_role=origin;commit');
 const as=async()=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated')};
 return {admin,day,drivers,trucks,deliveries,as,one};
}
module.exports={seed,gridPoint,roadMatrix};
