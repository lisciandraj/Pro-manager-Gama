/* Local, keyless map. Municipal streets are an on-demand, same-origin asset. */
(function(){'use strict';
const E=window.ArcUI.esc,NS='http://www.w3.org/2000/svg',GRID=256*.02/360;
const project=(lng,lat)=>{const s=Math.sin(Math.max(-85,Math.min(85,lat))*Math.PI/180);return [(lng+180)/360*256,(.5-Math.log((1+s)/(1-s))/(4*Math.PI))*256]};
const path=coordinates=>coordinates.map((p,i)=>(i?'L':'M')+project(...p).map(n=>n.toFixed(6)).join(',')).join('');
let geography,streetNetwork,streetPromise,streetFailure;
function decodeStreets(data){
 const bytes=atob(data.packed),roads=[],index=new Map();let cursor=0;
 const uint=()=>{let value=0,shift=0,byte;do{byte=bytes.charCodeAt(cursor++);if(!Number.isFinite(byte)||shift>28)throw Error('INVALID_MAP_SNAPSHOT');value+=(byte&127)*2**shift;shift+=7}while(byte&128);return value};
 const signed=()=>{const value=uint();return value%2?-(value+1)/2:value/2};
 for(let n=0;n<data.count;n++){
  const name=uint(),rank=uint(),count=uint();let x=0,y=0;
  const points=[];for(let j=0;j<count;j++){x+=signed();y+=signed();points.push(project(data.origin[0]+x/data.scale,data.origin[1]+y/data.scale))}
  const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);
  const bounds=[Math.min(...xs),Math.min(...ys),Math.max(...xs),Math.max(...ys)];
  const road={name:data.names[name]||'',rank,points,bounds,d:points.map((p,i)=>(i?'L':'M')+p.map(value=>value.toFixed(6)).join(',')).join('')};
  const id=roads.push(road)-1;
  for(let gx=Math.floor(bounds[0]/GRID);gx<=Math.floor(bounds[2]/GRID);gx++)for(let gy=Math.floor(bounds[1]/GRID);gy<=Math.floor(bounds[3]/GRID);gy++){const key=gx+','+gy;if(!index.has(key))index.set(key,[]);index.get(key).push(id)}
 }
 if(cursor!==bytes.length)throw Error('INVALID_MAP_SNAPSHOT');
 return {roads,index};
}
// A resize/background redraw must not retry a failed optional asset.
// The next map gesture clears the failure and can request it again.
function streets(){
 if(streetNetwork)return Promise.resolve(streetNetwork);
 if(streetFailure)return Promise.reject(streetFailure);
 if(!streetPromise)streetPromise=(window.CocoQuitoMapData?Promise.resolve():window.ArcLoadScript('gama-tms-quito-map-data.js',{validate:()=>!!window.CocoQuitoMapData}))
  .then(()=>streetNetwork=decodeStreets(window.CocoQuitoMapData)).catch(error=>{streetPromise=null;streetFailure=error;throw error});
 return streetPromise;
}
function visibleStreets(left,top,right,bottom){
 const ids=new Set();
 for(let x=Math.floor(left/GRID);x<=Math.floor(right/GRID);x++)for(let y=Math.floor(top/GRID);y<=Math.floor(bottom/GRID);y++)for(const id of streetNetwork.index.get(x+','+y)||[])ids.add(id);
 return [...ids].map(id=>streetNetwork.roads[id]).filter(r=>r.bounds[0]<=right&&r.bounds[2]>=left&&r.bounds[1]<=bottom&&r.bounds[3]>=top);
}
const palette=['#28677d','#b75a11','#6c50a4','#237854','#a13962'];
const routeColor=(r,i)=>r.color||palette[i%palette.length];
const positionedPoints=points=>points.filter(p=>p.lng!==null&&p.lat!==null&&p.lng!==''&&p.lat!==''&&Number.isFinite(+p.lng)&&Number.isFinite(+p.lat)&&Math.abs(+p.lat)<=85&&Math.abs(+p.lng)<=180).map(p=>({...p,p:project(+p.lng,+p.lat)}));
function create(host,{points=[],routes=[],vehicles=[],onSelect=()=>{},view=null}={}){
 const svg=document.createElementNS(NS,'svg');svg.setAttribute('role','group');svg.setAttribute('aria-label',window.GamaI18n?.t('Mapa de entregas. Usa las flechas para desplazar y + o − para ampliar.')||'Mapa de entregas. Usa las flechas para desplazar y + o − para ampliar.');svg.setAttribute('tabindex','0');svg.classList.add('tmsLocalMap');
 if(!geography){const data=window.CocoMapData||{};geography=`<g class="tmsMapLand">${(data.land||[]).map(r=>`<path d="${path(r)}Z"/>`).join('')}</g><g class="tmsMapRoads">${(data.roads||[]).map(r=>`<path d="${path(r)}"/>`).join('')}</g>`}
 svg.innerHTML=geography+'<g data-map-streets></g><g data-map-street-labels></g><g data-map-cities></g><g data-map-routes></g><g data-map-pins></g><g data-map-vehicles></g><g data-map-scale aria-hidden="true"></g>';host.replaceChildren(svg);
 let center=project(-78.4678,-.1807),zoom=12,selected=null,width=0,height=0,autoFit=true,requested=false,frame=0;
 let positioned=positionedPoints(points);const pointers=new Map();let gesture;
 // Explicit dimensions also give Safari a definite SVG viewport in flex layouts.
 const measure=()=>{width=host.clientWidth||700;height=host.clientHeight||380;svg.setAttribute('width',String(width));svg.setAttribute('height',String(height))};
 const queueDraw=()=>{if(!frame)frame=requestAnimationFrame(()=>{frame=0;if(svg.isConnected)draw()})};
 function drawStreets(left,top,vw,vh,unit){
  const roadsHost=svg.querySelector('[data-map-streets]'),labelsHost=svg.querySelector('[data-map-street-labels]');
  // The municipal snapshot covers Quito. The national local background remains
  // visible outside it and while the detailed same-origin asset is loading.
  const nw=project(-79,.26),se=project(-78.18,-.49);
  if(zoom<10||left>se[0]||left+vw<nw[0]||top>se[1]||top+vh<nw[1]){roadsHost.replaceChildren();labelsHost.replaceChildren();return}
  if(!streetNetwork){if(!requested){requested=true;streets().then(()=>{if(svg.isConnected)draw()}).catch(()=>{requested=false})}return}
  const minZoom=[10,11,12,13,15],visible=visibleStreets(left,top,left+vw,top+vh).filter(road=>zoom>=minZoom[road.rank]);
  const groups=Array.from({length:5},()=>[]);for(const road of visible)groups[road.rank].push(road.d);
  roadsHost.innerHTML=groups.map((group,rank)=>group.length?`<g class="tmsStreet tmsStreet-${rank}"><path class="tmsStreetOutline" d="${group.join('')}"/><path class="tmsStreetCenter" d="${group.join('')}"/></g>`:'').join('');
  svg.dataset.streetCount=String(visible.length);svg.dataset.streetSource='municipal';
  const occupied=[],names=new Set(),labels=[];
  for(const road of visible.sort((a,b)=>a.rank-b.rank)){
   if(!road.name||names.has(road.name)||zoom<(road.rank<=1?13:road.rank===2?14:16))continue;
   const candidates=[];
   for(let n=1;n<road.points.length;n++){
    const a=road.points[n-1],b=road.points[n],length=Math.hypot(b[0]-a[0],b[1]-a[1])/unit,textWidth=road.name.length*5.8+12;
    if(length<textWidth)continue;
    const x=(a[0]+b[0])/2,y=(a[1]+b[1])/2;let angle=Math.atan2(b[1]-a[1],b[0]-a[0]);
    if(Math.abs(angle)>Math.PI/2)angle+=Math.PI;
    const dx=(Math.abs(Math.cos(angle))*textWidth+Math.abs(Math.sin(angle))*16)/2,dy=(Math.abs(Math.sin(angle))*textWidth+Math.abs(Math.cos(angle))*16)/2;
    const px=(x-left)/unit,py=(y-top)/unit,box=[px-dx,py-dy,px+dx,py+dy];
    if(box[0]<12||box[1]<12||box[2]>width-12||box[3]>height-32)continue;
    candidates.push({x,y,angle,box,length});
   }
   const c=candidates.sort((a,b)=>b.length-a.length).find(c=>!occupied.some(b=>c.box[0]<b[2]+12&&c.box[2]>b[0]-12&&c.box[1]<b[3]+10&&c.box[3]>b[1]-10));
   if(!c)continue;
   occupied.push(c.box);names.add(road.name);labels.push(`<text class="tmsStreetName" transform="translate(${c.x},${c.y}) rotate(${c.angle*180/Math.PI})" font-size="${11*unit}" stroke-width="${3*unit}" text-anchor="middle">${E(road.name)}</text>`);
   if(labels.length>=Math.max(8,width*height/7000))break;
  }
  labelsHost.innerHTML=labels.join('');
 }
 function draw(){
  measure();const unit=2**-zoom,vw=width*unit,vh=height*unit,left=center[0]-vw/2,top=center[1]-vh/2;
  svg.setAttribute('viewBox',[left,top,vw,vh].join(' '));svg.dataset.zoom=String(zoom);svg.dataset.points=String(positioned.length);
  drawStreets(left,top,vw,vh,unit);
  const g=window.CocoMapData||{};
  svg.querySelector('[data-map-cities]').innerHTML=(g.cities||[]).filter(c=>zoom>=8||c.rank<5).map(c=>{const p=project(...c.point);return p[0]<left||p[0]>left+vw||p[1]<top||p[1]>top+vh?'':`<g transform="translate(${p.join(',')})"><circle r="${2*unit}" fill="#73808b"/><text x="${5*unit}" y="${-5*unit}" font-size="${12*unit}" fill="#4b5c68">${E(c.name)}</text></g>`}).join('');
  const stopLabels=new Map();
  svg.querySelector('[data-map-routes]').innerHTML=routes.map((r,i)=>{
   let number=0;for(const id of r.stops||[])if(id!=='__depot')stopLabels.set(id,{number:++number,color:routeColor(r,i)});
   // Break the line at a missing GPS stop instead of implying a direct journey.
   let connected=false;const ordered=(r.stops||[]).map(id=>{const p=positioned.find(p=>p.id===id);if(!p){connected=false;return ''}const d=(connected?'L':'M')+p.p.join(',');connected=true;return d}).join('');
   const road=Array.isArray(r.geometry)&&r.geometry.length>1;
   return `<path data-map-route="${E(r.id||i)}" data-route-basis="${road?'road':'order'}" d="${road?path(r.geometry):ordered}" fill="none" stroke="${E(routeColor(r,i))}" stroke-width="${road?4:2.5}"${road?'':' stroke-dasharray="6 5"'} stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"><title>${E(r.reference||r.driver||'')}</title></path>`;
  }).join('');
  const used=[],gap=autoFit?Math.min(28,Math.sqrt(Math.max(1,(width-40)*(height-40))/Math.max(1,positioned.length))*.8):28;
  const radius=Math.max(5,Math.min(13,gap/2-1)),margin=radius+5;
  const free=(x,y)=>used.every(q=>Math.hypot(q[0]-x,q[1]-y)>=gap);
  svg.querySelector('[data-map-pins]').innerHTML=positioned.map((p,i)=>{
   const px=(p.p[0]-left)/unit,py=(p.p[1]-top)/unit;let x=px,y=py;
   if(autoFit){x=Math.max(margin,Math.min(width-margin,x));y=Math.max(margin,Math.min(height-margin,y))}
   let attempt=0;
   while(!free(x,y)&&attempt<positioned.length*16){
    attempt++;const angle=attempt*2.39996,offset=gap*.65*Math.sqrt(attempt),cx=px+Math.cos(angle)*offset,cy=py+Math.sin(angle)*offset;
    if(!autoFit||(cx>=margin&&cx<=width-margin&&cy>=margin&&cy<=height-margin)){x=cx;y=cy}
   }
   if(autoFit&&!free(x,y)){
    let nearest=null;for(let gy=margin;gy<=height-margin;gy+=gap)for(let gx=margin;gx<=width-margin;gx+=gap){const distance=(gx-px)**2+(gy-py)**2;if((!nearest||distance<nearest.distance)&&free(gx,gy))nearest={x:gx,y:gy,distance}}
    if(nearest){x=nearest.x;y=nearest.y}
   }
   used.push([x,y]);const moved=Math.hypot(x-px,y-py)>.5;x=left+x*unit;y=top+y*unit;
   const color=p.isDepot?'#35495e':p.status==='Entregada'?'#15803d':p.status==='Excepción'?'#c2410c':stopLabels.get(p.id)?.color||'#28677d',label=p.isDepot?'D':String(stopLabels.get(p.id)?.number||i+1);
   return `<g data-map-pin="${E(p.id)}" role="button" tabindex="0" aria-label="${E([label,p.reference,p.customer,p.address].filter(Boolean).join(' · '))}"><title>${E(p.customer||p.address)}</title>${moved?`<path d="M${p.p.join(',')}L${x},${y}" stroke="${color}" stroke-width="1" vector-effect="non-scaling-stroke"/>`:''}<circle cx="${x}" cy="${y}" r="${(selected===p.id?radius+3:radius)*unit}" fill="${color}" stroke="#fff" stroke-width="2" vector-effect="non-scaling-stroke"/><text x="${x}" y="${y+4*unit}" text-anchor="middle" fill="#fff" font-size="${Math.min(11,radius)*unit}" font-weight="700" pointer-events="none">${label}</text></g>`;
  }).join('');
  svg.querySelector('[data-map-vehicles]').innerHTML=positionedPoints(vehicles).map(p=>`<g data-map-vehicle="${E(p.id)}" transform="translate(${p.p.join(',')})"><title>${E(p.customer||'')} · ${E(p.observedAt||'')}</title><circle r="${17*unit}" fill="${E(p.color||'#28677d')}" fill-opacity=".18"/><rect x="${-10*unit}" y="${-8*unit}" width="${20*unit}" height="${16*unit}" rx="${4*unit}" fill="${E(p.color||'#28677d')}" stroke="#fff" stroke-width="2" vector-effect="non-scaling-stroke"/><text y="${4*unit}" text-anchor="middle" font-size="${11*unit}" fill="#fff">${E(p.label||'V')}</text></g>`).join('');
  const latitude=Math.atan(Math.sinh(Math.PI*(1-2*center[1]/256))),meters=40075016.686*Math.cos(latitude)/256*unit,target=100*meters,power=10**Math.floor(Math.log10(target)),distance=[5,2,1].map(n=>n*power).find(n=>n<=target),length=distance/meters;
  const sx=left+20*unit,sy=top+(height-16)*unit;
  svg.querySelector('[data-map-scale]').innerHTML=`<path d="M${sx},${sy-4*unit}v${4*unit}h${length*unit}v${-4*unit}" stroke="#42586b" stroke-width="2" vector-effect="non-scaling-stroke" fill="none"/><text x="${sx}" y="${sy-7*unit}" font-size="${10*unit}" fill="#42586b">${distance>=1000?distance/1000+' km':distance+' m'}</text>`;
 }
 function fit(){measure();autoFit=true;selected=null;if(!positioned.length){center=project(-78.4678,-.1807);zoom=12}else{const xs=positioned.map(p=>p.p[0]),ys=positioned.map(p=>p.p[1]);center=[(Math.min(...xs)+Math.max(...xs))/2,(Math.min(...ys)+Math.max(...ys))/2];zoom=Math.min(15,Math.max(2,Math.log2(Math.min(Math.max(80,width-90)/Math.max(.00001,Math.max(...xs)-Math.min(...xs)),Math.max(80,height-90)/Math.max(.00001,Math.max(...ys)-Math.min(...ys))))))}draw()}
 function retryStreets(){streetFailure=null;requested=false}
 function changeZoom(delta){retryStreets();autoFit=false;zoom=Math.min(19,Math.max(2,zoom+delta));draw()}
 function focus(id){retryStreets();if(id==='all')return fit();autoFit=false;selected=id;center=id==='__quito'?project(-78.4678,-.1807):positioned.find(p=>p.id===id)?.p||center;zoom=id==='__quito'?12:16;draw()}
 svg.onclick=e=>{retryStreets();const pin=e.target.closest('[data-map-pin]');if(pin){selected=pin.dataset.mapPin;draw();onSelect(selected)}};
 svg.onkeydown=e=>{const pin=e.target.closest('[data-map-pin]');if(pin&&['Enter',' '].includes(e.key)){e.preventDefault();onSelect(pin.dataset.mapPin);return}if(['+','=','-','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();retryStreets();if(['+','=','-'].includes(e.key))changeZoom(e.key==='-'?-1:1);else{autoFit=false;const n=60*2**-zoom;center=[center[0]+(e.key==='ArrowRight'?n:e.key==='ArrowLeft'?-n:0),center[1]+(e.key==='ArrowDown'?n:e.key==='ArrowUp'?-n:0)];draw()}}};
 const snapshot=()=>{const p=[...pointers.values()];return p.length===1?{point:p[0],center:[...center]}:p.length===2?{distance:Math.hypot(p[1].x-p[0].x,p[1].y-p[0].y),zoom}:null};
 svg.onpointerdown=e=>{retryStreets();if(e.target.closest('[data-map-pin]'))return;svg.setPointerCapture(e.pointerId);pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});gesture=snapshot()};
 svg.onpointermove=e=>{if(!pointers.has(e.pointerId)||!gesture)return;autoFit=false;pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});if(pointers.size===1&&gesture.point){center=[gesture.center[0]-(e.clientX-gesture.point.x)*2**-zoom,gesture.center[1]-(e.clientY-gesture.point.y)*2**-zoom];queueDraw()}else if(pointers.size===2&&gesture.distance){const p=[...pointers.values()];zoom=Math.min(19,Math.max(2,gesture.zoom+Math.log2(Math.hypot(p[1].x-p[0].x,p[1].y-p[0].y)/gesture.distance)));queueDraw()}};
 svg.onpointerup=svg.onpointercancel=e=>{pointers.delete(e.pointerId);gesture=snapshot()};
 svg.addEventListener('wheel',e=>{if(e.ctrlKey||document.activeElement===svg){e.preventDefault();changeZoom(e.deltaY>0?-.5:.5)}},{passive:false});
 if(view&&Array.isArray(view.center)&&view.center.every(Number.isFinite)&&Number.isFinite(view.zoom)){center=[...view.center];zoom=view.zoom;selected=view.selected;autoFit=view.autoFit;if(autoFit)fit();else draw()}else fit();
 return {fit:()=>{retryStreets();fit()},focus,zoom:changeZoom,resize:()=>autoFit?fit():draw(),snapshot:()=>({center:[...center],zoom,selected,autoFit}),
  update:data=>{positioned=positionedPoints(data.points||[]);routes=data.routes||[];vehicles=data.vehicles||[];onSelect=data.onSelect||onSelect;if(autoFit)fit();else draw()},
  destroy:()=>{cancelAnimationFrame(frame);pointers.clear();svg.remove()}};
}
window.CocoDeliveryMap={create,routeColor};
})();
