/** Bounded, local performance diagnostics. No business payloads or authentication data. */
export function startPerformance(){
 const entries=[],start=performance.now();
 const record=(type,detail)=>{entries.push({type,at:Math.round(performance.now()),...detail});if(entries.length>100)entries.shift()};
 window.addEventListener('arc:route-change',e=>record('navigation',{route:e.detail.id}));
 window.addEventListener('architect:route-data-ready',e=>record('data',{route:e.detail.route,milliseconds:Math.round(e.detail.milliseconds),tables:e.detail.tables.length}));
 let measured=false;window.addEventListener('gama:modules-change',()=>{if(!measured&&window.GamaRoleAccess?.isReady()){measured=true;record('access_ready',{milliseconds:Math.round(performance.now()-start)})}});
 window.ArchitectPerformance={snapshot:()=>({entries:entries.map(x=>({...x})),resources:performance.getEntriesByType('resource').filter(r=>['fetch','xmlhttprequest','script'].includes(r.initiatorType)).map(r=>({kind:r.initiatorType,milliseconds:Math.round(r.duration),bytes:r.transferSize||null})),navigation:performance.getEntriesByType('navigation').map(n=>({domContentLoaded:Math.round(n.domContentLoadedEventEnd),load:Math.round(n.loadEventEnd)}))})};
}
