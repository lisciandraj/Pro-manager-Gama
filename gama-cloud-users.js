/* GAMA V17 — Usuarios y accesos: lista central Supabase + realtime */
(function(){
'use strict';
const ROLE={administrador:'Administrador',admin:'Administrador',comercial:'Comercial',commercial:'Comercial',almacenero:'Almacenero',magasinier:'Almacenero',rrhh:'Responsable RH',rh:'Responsable RH',cliente:'Cliente',client:'Cliente'};
const esc=window.ArcUI.esc;
let realtime=null, booted=false, selfId=null, generation=0;
function wait(){
  if(!window.GamaCloud||!window.GamaCloudReady)return setTimeout(wait,250);
  window.GamaCloudReady.then(init).catch(e=>console.warn('[GAMA Cloud Users]',e));
}
window.addEventListener('gama:auth-change',event=>{if(event.detail?.event==='TOKEN_REFRESHED')return;generation++;document.getElementById('cuRows')?.replaceChildren();booted=false;if(document.getElementById('users')?.classList.contains('active'))init()});
async function init(){
  if(booted)return;
  booted=true;
  try{
    const sr=await window.GamaCloud.getSession(), session=sr?.data?.session;
    if(!session)return;
    const pr=await window.GamaCloud.getProfile();
    const role=pr?.data?.role;
    selfId=pr?.data?.id||session.user?.id||null;
    if(role!=='administrador' && role!=='admin')return;
    // The router needs its target section before the first navigation. Create
    // the shell now; profiles are still fetched only when the module opens.
    patch();
    if(window.ArcRouter.current==='users')await load();
    if(!realtime){
      try{realtime=await window.GamaCloud.subscribe('profiles',()=>{if(window.ArcRouter.current==='users')load()})}
      catch(e){console.warn('[GAMA] profiles realtime unavailable',e)}
    }

    window.addEventListener('gama:access-profiles-change',()=>{if(window.ArcRouter.current==='users')load()});
    // Fechas y horas en el formato del idioma elegido.
    window.addEventListener('gama:language-change',()=>{if(window.ArcRouter.current==='users')load()});
  }catch(e){console.warn('[GAMA Cloud Users] init failed',e)}
}
function patch(){
  let s=document.getElementById('users');
  if(!s){s=document.createElement('section');s.id='users';(document.querySelector('.wrap')||document.body).appendChild(s)}
  if(s.querySelector('.cloudUsersV17'))return;
  window.ArcUI.render(s,`${window.GamaUI.header({title:'Usuarios y accesos',lead:'Quién entra en Coco ERP y con qué permisos.'})}<div class="arcPanel card cloudUsersV17"><div class="cuBar"><h3 data-gi=a1a13eae50f0>Usuarios cloud</h3><span class="cuOnline"><i></i> <span data-gi=f0c9e4e7c1ee>Cloud conectado</span></span></div><div id="cuPending" class="cuPending" data-gi-live hidden></div><div id="cuStatus" class="cuStatus" data-gi=633d7ba5f776>Cargando usuarios…</div><div class="cuTable"><table class="arcTable"><thead><tr><th data-gi=562bb15757a8>Nombre</th><th data-gi=969ccbd3cf63>Email</th><th data-gi=fb9f51fe9250>Rol</th><th data-gi=98e5acddb6c4>Estado</th><th data-gi=1bba71a51144>Creado</th><th data-gi=fb89a30ba7f6>Acciones</th></tr></thead><tbody id="cuRows"></tbody></table></div><div class="cuFoot"><span id="cuCount">0 usuarios</span><span data-gi=49469fa2cf35>● Actualización automática activa</span></div></div>`);
  window.GamaUI.bindBack(s);
  if(!document.getElementById('cuStyle')){const st=document.createElement('style');st.id='cuStyle';document.head.appendChild(st)}
}
async function load(){
  const token=++generation;
  const s=document.getElementById('users');
  if(!s)return;
  if(!s.querySelector('.cloudUsersV17'))patch();
  const status=document.getElementById('cuStatus'),body=document.getElementById('cuRows');
  if(!status||!body)return;
  try{
    status.textContent='Sincronizando con la nube…';
    const r=await window.ArcData.all('profiles',{order:'id',ascending:false});
    if(r.error)throw r.error;if(token!==generation)return;
    const rows=Array.isArray(r.data)?r.data:[];
    const ROLES=window.GamaRoleAccess.options();
    const key=x=>x.access_profile||(window.ArcModules.roleAliases[x.role]||x.role);
    const label=x=>ROLES.find(r=>r.id===key(x))?.label||ROLE[x.role]||x.role;
    /* Cada perfil de base tiene su color; un perfil creado por la empresa va en
       neutro y su nombre, escrito por ella, no se traduce. */
    const builtIn=x=>['admin','commercial','magasinier','rh','client'].includes(key(x));
    const locale=window.GamaI18n?.locale||'es-EC';
    window.ArcUI.render(body,rows.length?rows.map(x=>{
      const self=x.id===selfId;
      const actions=self?'<b data-gi=d30c5ae09ef0>Tu cuenta</b>':
        `<select data-cu-role="${esc(x.id)}">${ROLES.map(r=>`<option value="${esc(r.id)}"${r.id===key(x)?' selected':''} ${r.custom?'data-gi-ignore':'data-gi-live'}>${esc(r.label)}</option>`).join('')}</select> `+
        `<button class="arcButton ${x.active===false?'primary':'secondary'}" data-cu-toggle="${esc(x.id)}" data-cu-next="${x.active===false?'1':'0'}" data-gi-live>${x.active===false?'Aprobar':'Desactivar'}</button>`;
      return `<tr><td><b>${x.full_name?esc(x.full_name):'<span data-gi-live data-gi=c4dc040a07c5>Sin nombre</span>'}</b><br><span class="cuId">${esc(x.id)}</span></td><td>${esc(x.email||'—')}</td><td><span class="cuBadge" data-role="${builtIn(x)?esc(key(x)):'custom'}"${builtIn(x)?' data-gi-live':''}>${esc(label(x))}</span></td><td class="${x.active===false?'cuInactive':'cuActive'}"><span class="cuState" data-gi-live>${x.active===false?'Pendiente / desactivado':'Activo'}</span></td><td>${x.created_at?esc(new Date(x.created_at).toLocaleString(locale)):'—'}</td><td>${actions}</td></tr>`;
    }).join(''):'<tr><td colspan="6" data-gi=ed24da31a76e>No se encontraron usuarios en Supabase.</td></tr>');
    wireActions();
    const pending=rows.filter(x=>x.active===false).length, banner=document.getElementById('cuPending');
    if(banner){banner.hidden=!pending;banner.textContent=pending?`${pending} cuenta(s) pendiente(s) de aprobación. Mientras no las apruebes no pueden leer ningún dato.`:'';}
    document.getElementById('cuCount').textContent=rows.length===1?'1 usuario':`${rows.length} usuarios`;
    status.textContent=`Última sincronización: ${new Date().toLocaleTimeString(locale)}`;
  }catch(e){
    console.error('[GAMA Cloud Users]',e);
    status.textContent='No se pudieron leer los usuarios: '+(e.message||e);
    window.ArcUI.render(body,'<tr><td colspan="6" class="cuInactive" data-gi=fc66cd550451>No se pudo leer la tabla profiles. Verifica la política SELECT RLS en Supabase.</td></tr>');
  }
}
/* Toda cuenta nueva nace desactivada (trigger gama_on_auth_user_created) y no
   lee nada hasta que un administrador la aprueba aquí. */
function wireActions(){
  document.querySelectorAll('[data-cu-toggle]').forEach(b=>b.onclick=async()=>{
    const id=b.dataset.cuToggle, next=b.dataset.cuNext==='1';
    if(!next&&!confirm('¿Desactivar esta cuenta? Perderá el acceso inmediatamente.'))return;
    b.disabled=true;
    try{const r=await window.GamaCloud.update('profiles',id,{active:next});if(r&&r.error)throw r.error;await load();}
    catch(e){alert('No se pudo cambiar el estado: '+(e.message||e));b.disabled=false;}
  });
  document.querySelectorAll('[data-cu-role]').forEach(sel=>sel.onchange=async()=>{
    const id=sel.dataset.cuRole, role=sel.value;
    sel.disabled=true;
    try{await window.GamaRoleAccess.assign(id,role);await load();}
    catch(e){await load();alert('No se pudo cambiar el rol: '+(e.message||e));}
  });
}
window.ArcRouter.onEnter('users',async()=>{await window.GamaCloudReady;await init();if(selfId){patch();await load();window.ArchitectIdentity?.mount(document.getElementById('users'))}});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',wait,{once:true});else wait();
})();
