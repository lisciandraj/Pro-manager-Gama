/** Bounded, local performance diagnostics. No business payloads or authentication data. */
export function startPerformance(){
 const entries=[],start=performance.now();
 let samples=[],epoch=0,pending=false;
 const capture=detail=>{if(!window.GamaRoleAccess?.isReady?.())return;const module=detail.module||window.ArcRouter?.current||'mainmenu';if(!/^[a-zA-Z0-9_-]{1,64}$/.test(module)||!/^[a-zA-Z0-9_-]{0,64}$/.test(detail.operation||''))return;
  samples.push({metric:detail.metric,module,operation:detail.operation||'',duration_ms:Math.min(300000,Math.max(0,detail.duration_ms||0)),success:detail.success!==false,device:innerWidth<768?'mobile':'desktop',network:navigator.connection?.effectiveType?['slow-2g','2g'].includes(navigator.connection.effectiveType)?'slow':'normal':'unknown'});if(samples.length>100)samples.shift();};
 const flush=async()=>{if(pending||document.hidden||!samples.length)return;pending=true;const token=epoch,batch=samples.splice(0,50);try{const db=await window.GamaCloud.db();if(token===epoch)await db.rpc('gama_operational_metrics',{p_action:'record',p_data:{samples:batch}})}catch(_){}finally{pending=false}};
 window.addEventListener('arc:metric',e=>capture(e.detail));
 document.addEventListener('click',e=>{if(e.target.closest?.('button,[role=button],a'))capture({metric:'action',duration_ms:1,success:true})},{passive:true});
 window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;samples=[]});
 setInterval(flush,30000);
 const record=(type,detail)=>{entries.push({type,at:Math.round(performance.now()),...detail});if(entries.length>100)entries.shift()};
 window.addEventListener('arc:route-change',e=>record('navigation',{route:e.detail.id}));
 window.addEventListener('architect:route-data-ready',e=>record('data',{route:e.detail.route,milliseconds:Math.round(e.detail.milliseconds),tables:e.detail.tables.length}));
 let measured=false;window.addEventListener('gama:modules-change',()=>{if(!measured&&window.GamaRoleAccess?.isReady()){measured=true;record('access_ready',{milliseconds:Math.round(performance.now()-start)})}});
 window.ArchitectPerformance={snapshot:()=>({entries:entries.map(x=>({...x})),resources:performance.getEntriesByType('resource').filter(r=>['fetch','xmlhttprequest','script'].includes(r.initiatorType)).map(r=>({kind:r.initiatorType,milliseconds:Math.round(r.duration),bytes:r.transferSize||null})),navigation:performance.getEntriesByType('navigation').map(n=>({domContentLoaded:Math.round(n.domContentLoadedEventEnd),load:Math.round(n.loadEventEnd)}))}),open:async()=>{const token=epoch,r=await window.ArcData.rpc('gama_operational_metrics',{p_action:'report'});if(token!==epoch)return;window.ArcUI.dialog({title:'Rendimiento observado',saveLabel:'Cerrar',body:'<p data-gi=4fc41b9622bf>Últimos 7 días. El percentil 95 se calcula sobre mediciones reales; sin muestras no se estima. Los tiempos de navegación miden la apertura; los RPC miden la respuesta del servidor.</p>'+window.ArcUI.table({columns:[{key:'module',label:'Módulo'},{key:'operation',label:'Operación'},{key:'metric',label:'Medición'},{key:'device',label:'Dispositivo'},{key:'network',label:'Red'},{key:'samples',label:'Muestras'},{key:'p95_ms',label:'P95 (ms)'},{key:'errors',label:'Errores'}],items:r.rows}),onSave:async()=>{}})}};
}
