/* GAMA V15 — Usuarios y accesos conectados al cloud central */
(function(){
'use strict';
const ROLE={administrador:'Administrador',comercial:'Comercial',almacenero:'Almacenero'};
const esc=v=>String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));
const wait=()=>{if(!window.GamaCloud||!window.GamaCloudReady)return setTimeout(wait,250);window.GamaCloudReady.then(init).catch(e=>console.warn('[GAMA Cloud Users]',e))};
let realtime=null;
async function init(){
  if(!window.GamaCloud)return;
  const session=(await window.GamaCloud.getSession()).data?.session;
  if(!session)return;
  const profile=await window.GamaCloud.getProfile();
  if(!profile.data||profile.data.role!=='administrador')return;
  patch();
  load();
  if(!realtime){try{realtime=await window.GamaCloud.subscribe('profiles',()=>load())}catch(e){console.warn('[GAMA] profiles realtime unavailable',e)}}
  window.addEventListener('gama:auth-change',()=>setTimeout(load,100));
}
function patch(){
  let s=document.getElementById('users');
  if(!s){s=document.createElement('section');s.id='users';(document.querySelector('.wrap')||document.body).appendChild(s)}
  s.innerHTML=`<div class="card cloudUsersV15"><div class="cuHead"><div><div class="cuKicker">GAMA CLOUD</div><h2>👥 Usuarios y accesos</h2><p>Comptes centralisés dans Supabase • synchronisation temps réel.</p></div><div class="cuOnline"><i></i> Cloud connecté</div></div><div class="cuInfo"><b>Source unique :</b> cette liste provient directement de <b>Supabase / profiles</b>. Les utilisateurs créés depuis « Comptes cloud » apparaissent automatiquement ici sur tous les appareils.</div><div class="cuBar"><h3>Utilisateurs cloud</h3><button class="secondary" id="cuRefresh">↻ Actualiser</button></div><div id="cuStatus" class="cuStatus">Chargement des utilisateurs…</div><div class="cuTable"><table><thead><tr><th>Nom</th><th>Rôle</th><th>État</th><th>Créé le</th><th>ID cloud</th></tr></thead><tbody id="cuRows"></tbody></table></div><div class="cuFoot"><span id="cuCount">0 utilisateur</span><span>● Synchronisation temps réel active</span></div></div>`;
  document.getElementById('cuRefresh').onclick=load;
  if(!document.getElementById('cuStyle')){const st=document.createElement('style');st.id='cuStyle';st.textContent=`.cloudUsersV15{border-radius:16px}.cuHead,.cuBar,.cuFoot{display:flex;justify-content:space-between;align-items:center;gap:12px}.cuKicker{font-size:10px;font-weight:900;letter-spacing:1.3px;color:#087C8B}.cuHead h2{margin:4px 0;font-size:26px;color:#18324A}.cuHead p{margin:3px 0;color:#71808A;font-size:12px}.cuOnline{padding:8px 11px;border-radius:999px;background:#E7F6F0;color:#138A69;font-size:11px;font-weight:800;white-space:nowrap}.cuOnline i{display:inline-block;width:7px;height:7px;border-radius:50%;background:#138A69;margin-right:5px}.cuInfo{margin:14px 0;padding:11px 13px;border-left:4px solid #087C8B;background:#F0F8F9;border-radius:8px;font-size:12px;color:#50616C}.cuBar{margin-top:16px}.cuBar h3{margin:0}.cuStatus{margin:10px 0;color:#71808A;font-size:12px}.cuTable{overflow:auto;border:1px solid #E4EBEE;border-radius:12px}.cuTable table{width:100%;min-width:700px;border-collapse:collapse;display:table;white-space:normal}.cuTable th,.cuTable td{padding:11px 12px;text-align:left;border-bottom:1px solid #EDF1F2;font-size:12px}.cuTable th{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:#71808A;background:#F8FAFB}.cuTable tr:last-child td{border-bottom:0}.cuBadge{display:inline-block;padding:5px 8px;border-radius:999px;background:#E8F5F6;color:#087C8B;font-weight:800}.cuActive{color:#138A69;font-weight:800}.cuInactive{color:#C94F45;font-weight:800}.cuId{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:10px;color:#7B8992}.cuFoot{margin-top:9px;color:#71808A;font-size:11px}.cuFoot span:last-child{color:#138A69}@media(max-width:700px){.cuHead{align-items:flex-start;flex-direction:column}.cuHead h2{font-size:22px}.cuOnline{align-self:flex-start}.cuBar{align-items:flex-start}.cuFoot{align-items:flex-start;flex-direction:column}}`;document.head.appendChild(st)}
}
async function load(){
 const s=document.getElementById('users');if(!s)return;
 const status=document.getElementById('cuStatus');
 try{
  status.textContent='Synchronisation avec le cloud…';
  const r=await window.GamaCloud.list('profiles',{order:'created_at',ascending:false});
  if(r.error)throw r.error;
  const rows=r.data||[];
  const body=document.getElementById('cuRows');
  body.innerHTML=rows.length?rows.map(x=>`<tr><td><b>${esc(x.full_name||'Sans nom')}</b></td><td><span class="cuBadge">${esc(ROLE[x.role]||x.role||'Utilisateur')}</span></td><td class="${x.active===false?'cuInactive':'cuActive'}">${x.active===false?'● Désactivé':'● Actif'}</td><td>${x.created_at?new Date(x.created_at).toLocaleString('fr-FR'): '—'}</td><td class="cuId">${esc(x.id)}</td></tr>`).join(''):'<tr><td colspan="5">Aucun utilisateur trouvé dans le cloud.</td></tr>';
  document.getElementById('cuCount').textContent=`${rows.length} utilisateur${rows.length>1?'s':''}`;
  status.textContent=`Dernière synchronisation : ${new Date().toLocaleTimeString('fr-FR')}`;
 }catch(e){console.error('[GAMA Cloud Users]',e);status.textContent='Impossible de charger la liste cloud : '+(e.message||e);document.getElementById('cuRows').innerHTML='<tr><td colspan="5" class="cuInactive">Vérifiez votre connexion et les droits RLS Supabase.</td></tr>'}
}
const observer=new MutationObserver(()=>{const s=document.getElementById('users');if(s&&!s.querySelector('.cloudUsersV15')){const old=s.innerHTML;s.dataset.replaced='1';patch();load()}});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',wait,{once:true});else wait();
})();
