/* Pure project calculations shared by the UI and regression tests. Server is authoritative. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.GamaProjectsCore=api})(typeof window==='undefined'?globalThis:window,function(){
'use strict';
const statuses={project:['draft','planned','active','on_hold','completed','cancelled'],task:['backlog','todo','in_progress','review','done'],phase:['planned','in_progress','review','completed','on_hold'],work_package:['planned','in_progress','review','completed'],deliverable:['in_progress','submitted','approved','changes_requested'],milestone:['planned','achieved','cancelled'],risk:['open','in_progress','closed'],issue:['open','in_progress','closed'],change:['request','assessment','approval','approved','implementation','closed','rejected'],decision:['recorded','superseded'],lesson:['recorded'],assumption:['open','in_progress','closed'],dependency:['open','in_progress','closed'],stakeholder:['active','inactive'],raci:['active']};
const terminal=new Set(['done','completed','approved','achieved','cancelled','closed','rejected','recorded','superseded','inactive']);
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:(globalThis.window?.GamaCompany?.get()?.timezone||'America/Guayaquil'),year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const days=(a,b)=>Math.round((Date.parse(a+'T12:00:00Z')-Date.parse(b+'T12:00:00Z'))/86400000);
const addDays=(d,n)=>{const x=new Date(d+'T12:00:00Z');x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10)};
const score=i=>Number(i.data?.probability||0)*Number(i.data?.impact||0);
const riskHealth=i=>score(i)>=15?2:score(i)>=6?1:0;
const milestoneHealth=(i,now=today())=>i.status!=='planned'?0:i.due_date&&i.due_date<now?2:i.forecast_date>i.due_date?1:0;
function progress(items,parent){const tasks=items.filter(t=>t.kind==='task'&&(!parent||(parent.kind==='phase'?t.phase_id===parent.id:parent.kind==='work_package'?t.work_package_id===parent.id:t.deliverable_id===parent.id)));return tasks.length?Math.round(tasks.reduce((s,t)=>s+(t.status==='done'?100:Number(t.progress||0)),0)/tasks.length):0}
function myItems(items,user,view='tasks',now=today()){
 const active=items.filter(i=>!['completed','cancelled'].includes(i.project_status));
 const mine=active.filter(i=>i.owner_id===user||(i.data?.collaborators||[]).includes(user));
 if(view==='approvals')return active.filter(i=>i.approver_id===user&&((i.kind==='phase'&&i.status==='review')||(i.kind==='deliverable'&&i.status==='submitted')||(i.kind==='change'&&i.status==='approval')));
 if(view==='deliverables')return mine.filter(i=>i.kind==='deliverable'&&!terminal.has(i.status));
 if(view==='actions')return mine.filter(i=>['issue','risk','change'].includes(i.kind)&&!terminal.has(i.status));
 const tasks=mine.filter(i=>i.kind==='task'&&i.status!=='done');
 if(view==='today')return tasks.filter(i=>i.due_date===now);
 if(view==='week'){const end=addDays(now,7);return tasks.filter(i=>i.due_date>=now&&i.due_date<end)}
 if(view==='late')return tasks.filter(i=>i.due_date&&i.due_date<now);return tasks;
}
function load(items,user,now=today()){
 let planned=0,actual=0;const end=addDays(now,7);
 for(const i of items.filter(i=>i.kind==='task'&&i.owner_id===user)){
  actual+=Number(i.data?.spent_hours||0);
  if(i.status==='done')continue;
  const start=i.start_date||now,due=i.due_date||end,total=Math.max(1,days(due,start)+1),a=start>now?start:now,b=due<end?due:addDays(end,-1);
  if(b>=a)planned+=Number(i.data?.estimated_hours||0)*(1-Number(i.progress||0)/100)*Math.min(1,(days(b,a)+1)/total);
 }
 return {planned:Math.round(planned*10)/10,actual};
}
function filterTasks(items,f={}){return items.filter(i=>i.kind==='task'&&(!f.phase_id||i.phase_id===f.phase_id)&&(!f.owner_id||i.owner_id===f.owner_id)&&(!f.priority||i.priority===f.priority)&&(!f.due_date||(i.due_date&&i.due_date<=f.due_date))&&(!f.search||(i.reference+' '+i.title).toLowerCase().includes(f.search.toLowerCase())))}
function timeline(items){const dated=items.filter(i=>i.start_date||i.due_date);if(!dated.length)return null;const min=dated.map(i=>i.start_date||i.due_date).sort()[0],max=dated.map(i=>i.due_date||i.start_date).sort().at(-1),span=Math.max(1,days(max,min)+1);return {min,max,span,rows:dated.map(i=>({...i,left:Math.max(0,days(i.start_date||i.due_date,min)/span*100),width:Math.max(.5,(days(i.due_date||i.start_date,i.start_date||i.due_date)+1)/span*100)}))}}
return {statuses,terminal,today,days,addDays,score,riskHealth,milestoneHealth,progress,myItems,load,filterTasks,timeline};
});
