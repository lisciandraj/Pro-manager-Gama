/* Generated from src/features/access/cloud-users.js. Edit the source and run npm run build. */
/* GAMA V17 — Usuarios y accesos: lista central Supabase + realtime */
(function(){
'use strict';
if(window.GamaCloudUsers)return;
const ROLE={administrador:'Administrador',admin:'Administrador',comercial:'Comercial',commercial:'Comercial',almacenero:'Almacenero',magasinier:'Almacenero',rrhh:'Responsable RH',rh:'Responsable RH',cliente:'Cliente',client:'Cliente'};
const esc=window.ArcUI.esc;
const t=(es,fr,en)=>({fr,en}[window.GamaI18n?.locale?.slice(0,2)]||es);
let realtime=null, booted=false, initialization=null, selfId=null, generation=0, authEpoch=0;
const isOpen=()=>!!window.gamaAccessAllowed?.('users')&&!!document.getElementById('users')?.closest('#arcSettingsDialog[open] [data-side-pane="users"]:not([hidden])');
function wait(){
  if(!window.GamaCloud||!window.GamaCloudReady)return setTimeout(wait,250);
  window.GamaCloudReady.then(init).catch(e=>console.warn('[GAMA Cloud Users]',e));
}
window.addEventListener('gama:auth-change',event=>{if(event.detail?.event==='TOKEN_REFRESHED')return;authEpoch++;generation++;document.getElementById('cuRows')?.replaceChildren();selfId=null;booted=false;initialization=null;if(isOpen())mount()});
window.addEventListener('gama:access-profiles-change',()=>{if(isOpen())load()});
window.addEventListener('gama:language-change',()=>{if(isOpen())load()});
function init(){
  if(booted)return initialization;
  booted=true;
  const token=authEpoch;
  initialization=(async()=>{
  try{
    const sr=await window.GamaCloud.getSession(), session=sr?.data?.session;
    if(!session)return;
    const pr=await window.GamaCloud.getProfile();
    const role=pr?.data?.role;
    if(token!==authEpoch||(role!=='administrador' && role!=='admin'))return;
    selfId=pr?.data?.id||session.user?.id||null;
    // Keep one screen; Configuration moves it into its Users pane on demand.
    patch();
    if(!realtime){
      try{realtime=await window.GamaCloud.subscribe('profiles',()=>{if(isOpen())load()})}
      catch(e){console.warn('[GAMA] profiles realtime unavailable',e)}
    }
  }catch(e){console.warn('[GAMA Cloud Users] init failed',e)}
  })();
  return initialization;
}
function patch(){
  let s=document.getElementById('users');
  if(!s){s=document.createElement('section');s.id='users';(document.querySelector('.wrap')||document.body).appendChild(s)}
  if(s.querySelector('.cloudUsersV17'))return;
  window.ArcUI.render(s,`<div class="arcPanel card cloudUsersV17"><div class="cuBar"><h3 data-gi=a1a13eae50f0>Usuarios cloud</h3><span class="cuOnline"><i></i> <span data-gi=f0c9e4e7c1ee>Cloud conectado</span></span></div><div id="cuPending" class="cuPending" data-gi-live hidden></div><div id="cuStatus" class="cuStatus" data-gi=633d7ba5f776>Cargando usuarios…</div><div class="cuTable"><table class="arcTable"><thead><tr><th data-gi=562bb15757a8>Nombre</th><th data-gi=969ccbd3cf63>Email</th><th data-gi=fb9f51fe9250>Rol</th><th data-gi=98e5acddb6c4>Estado</th><th data-gi=1bba71a51144>Creado</th><th data-gi=fb89a30ba7f6>Acciones</th></tr></thead><tbody id="cuRows"></tbody></table></div><div class="cuFoot"><span id="cuCount">0 usuarios</span><span data-gi=49469fa2cf35>● Actualización automática activa</span></div></div>`);
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
    const rows=Array.isArray(r.data)?r.data.filter(x=>!x.deleted_at):[];
    const ROLES=window.GamaRoleAccess.options();
    // Cada cuenta tiene los accesos por defecto de su tipo de usuario.
    const key=x=>window.ArcModules.roleAliases[x.role]||x.role;
    const label=x=>ROLES.find(r=>r.id===key(x))?.label||ROLE[x.role]||x.role;
    // Cada tipo de usuario tiene su color; un rol desconocido va en neutro.
    const builtIn=x=>['admin','commercial','magasinier','rh'].includes(key(x));
    const locale=window.GamaI18n?.locale||'es-EC';
    window.ArcUI.render(body,rows.length?rows.map(x=>{
      const self=x.id===selfId,retired=['cliente','client'].includes(x.role);
      const actions=retired?`<span>${t('Acceso retirado — pedidos desde el sitio público','Accès retiré — commandes depuis le site public','Access retired — orders through public website')}</span> <button type="button" class="arcButton secondary" data-cu-delete="${esc(x.id)}" data-gi-ignore>${t('Eliminar definitivamente','Supprimer définitivement','Delete permanently')}</button>`:self?'<b data-gi=d30c5ae09ef0>Tu cuenta</b>':
        `<select data-cu-role="${esc(x.id)}">${ROLES.map(r=>`<option value="${esc(r.id)}"${r.id===key(x)?' selected':''} data-gi-live>${esc(r.label)}</option>`).join('')}</select> `+
        `<button class="arcButton ${x.active===false?'primary':'secondary'}" data-cu-toggle="${esc(x.id)}" data-cu-next="${x.active===false?'1':'0'}" data-gi-live>${x.active===false?'Aprobar':'Desactivar'}</button> `+
        `<button type="button" class="arcButton secondary" data-cu-delete="${esc(x.id)}" data-gi-ignore>${t('Eliminar definitivamente','Supprimer définitivement','Delete permanently')}</button>`;
      return `<tr><td><b>${x.full_name?esc(x.full_name):'<span data-gi-live data-gi=c4dc040a07c5>Sin nombre</span>'}</b><br><span class="cuId">${esc(x.id)}</span></td><td>${esc(x.email||'—')}</td><td><span class="cuBadge" data-role="${builtIn(x)?esc(key(x)):'custom'}"${builtIn(x)?' data-gi-live':''}>${esc(label(x))}</span></td><td class="${x.active===false?'cuInactive':'cuActive'}"><span class="cuState" data-gi-live>${x.active===false?'Pendiente / desactivado':'Activo'}</span></td><td>${x.created_at?esc(new Date(x.created_at).toLocaleString(locale)):'—'}</td><td>${actions}</td></tr>`;
    }).join(''):'<tr><td colspan="6" data-gi=ed24da31a76e>No se encontraron usuarios en Supabase.</td></tr>');
    wireActions(rows);
    const pending=rows.filter(x=>x.active===false&&!['cliente','client'].includes(x.role)).length, banner=document.getElementById('cuPending');
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
function wireActions(rows){
  document.querySelectorAll('[data-cu-delete]').forEach(b=>b.onclick=()=>deleteAccount(rows.find(x=>x.id===b.dataset.cuDelete)));
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
function deleteError(e){
 const message=String(e?.message||e),messages={
  USER_EMAIL_CONFIRMATION_MISMATCH:t('El correo no coincide. Actualiza la lista si ha cambiado.','L’adresse e-mail ne correspond pas. Actualisez la liste si elle a changé.','The email does not match. Refresh the list if it has changed.'),
  CANNOT_DELETE_SELF:t('No puedes eliminar tu propia cuenta.','Vous ne pouvez pas supprimer votre propre compte.','You cannot delete your own account.'),
  LAST_ADMIN_REQUIRED:t('Debe quedar al menos un administrador activo.','Il doit rester au moins un administrateur actif.','At least one active administrator must remain.'),
  USER_DELETE_NOT_ALLOWED:t('Tu perfil no permite eliminar usuarios.','Votre profil ne permet pas de supprimer des utilisateurs.','Your profile cannot delete users.'),
  USER_NOT_FOUND:t('Esta cuenta ya no existe. Actualiza la lista.','Ce compte n’existe plus. Actualisez la liste.','This account no longer exists. Refresh the list.'),
  AUTH_OR_MFA_REQUIRED:t('Vuelve a iniciar sesión y verifica tu autenticación en dos pasos.','Reconnectez-vous et vérifiez votre authentification en deux étapes.','Sign in again and verify your two-step authentication.')
 };
 return Object.entries(messages).find(([code])=>message.includes(code))?.[1]||window.ArcErrors.message(e);
}
function deleteAccount(user){
 if(!user||user.id===selfId)return;
 const d=window.ArcUI.dialog({title:t('Eliminar la cuenta definitivamente','Supprimer définitivement le compte','Permanently delete the account'),saveLabel:t('Eliminar definitivamente','Supprimer définitivement','Delete permanently'),
  body:`<p><strong>${esc(user.full_name||user.email)}</strong><br>${esc(user.email||'')}</p><p>${t('Se eliminarán la cuenta de conexión y sus sesiones. Podrás crear una cuenta nueva con el mismo correo. El historial de documentos y operaciones de la empresa se conserva.','Le compte de connexion et ses sessions seront supprimés. Vous pourrez créer un nouveau compte avec la même adresse e-mail. L’historique des documents et opérations de l’entreprise est conservé.','The login account and its sessions will be deleted. You can create a new account with the same email. Company document and operation history is retained.')}</p>`+
   window.ArcUI.field({key:'confirmation_email',type:'email',label:t('Escribe el correo de esta cuenta para confirmar','Saisissez l’adresse e-mail du compte pour confirmer','Enter this account’s email to confirm'),required:true}),
  onSave:async el=>{
   const email=String(new FormData(el.querySelector('form')).get('confirmation_email')||'').trim().toLowerCase();
   if(email!==String(user.email||'').trim().toLowerCase())throw Error(deleteError({message:'USER_EMAIL_CONFIRMATION_MISMATCH'}));
   try{await window.ArchitectIdentity?.ensureMFA?.();await window.ArcData.rpc('gama_delete_user',{p_user_id:user.id,p_email:email})}
   catch(e){throw Error(deleteError(e))}
   await load();window.gamaToast?.(t('Cuenta eliminada. El correo está disponible para una nueva cuenta.','Compte supprimé. L’adresse e-mail est disponible pour un nouveau compte.','Account deleted. The email is available for a new account.'));
  }});
 d.dataset.identity='';d.dataset.giIgnore='';d.querySelector('[name=confirmation_email]').autocomplete='off';
}
async function mount(){await window.GamaCloudReady;await init();if(selfId&&window.gamaAccessAllowed?.('users')){patch();window.ArchitectIdentity?.mount(document.getElementById('users'));await load()}}
window.GamaCloudUsers={mount};
window.ArcRouter.onEnter('users',mount);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',wait,{once:true});else wait();
})();
