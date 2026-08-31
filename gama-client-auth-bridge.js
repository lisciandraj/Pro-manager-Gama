/* GAMA DEV — client authentication bridge for Catalogue client */
(function(){'use strict';
function boot(){
  if(!window.GamaCloud||!window.GamaCloudReady)return setTimeout(boot,100);
  window.GamaCloudReady.then(function(C){
    async function activateClient(){
      try{
        const sr=await C.getSession(), s=sr?.data?.session;
        if(!s)return false;
        const pr=await C.getProfile();
        if(pr?.data?.role!=='client'||pr.data.active===false)return false;
        localStorage.setItem('gama_session_v1',JSON.stringify({userId:s.user.id,role:'client',username:s.user.email||'',name:pr.data.full_name||s.user.email||'Client'}));
        document.getElementById('gamaCloudLogin')?.remove();
        document.getElementById('gamaLogin')?.remove();
        window.dispatchEvent(new CustomEvent('gama:client-authenticated',{detail:{userId:s.user.id}}));
        return true;
      }catch(e){console.warn('[GAMA DEV client auth]',e);return false}
    }
    document.addEventListener('click',async function(e){
      const b=e.target?.closest?.('#gamaCloudLoginBtn');
      if(!b)return;
      e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
      const email=document.getElementById('gamaCloudEmail')?.value.trim().toLowerCase();
      const pass=document.getElementById('gamaCloudPass')?.value||'';
      const er=document.getElementById('gamaCloudErr');
      if(!email||!pass){if(er){er.textContent='Correo electrónico y contraseña son obligatorios.';er.style.display='block'}return}
      const r=await C.signIn(email,pass);
      if(r.error){if(er){er.textContent='No se puede iniciar sesión. Compruebe sus credenciales.';er.style.display='block'}return}
      const ok=await activateClient();
      if(ok){location.reload();return}
      await C.signOut();
      if(er){er.textContent='Cuenta no autorizada o desactivada.';er.style.display='block'}
    },true);
    activateClient();
    window.addEventListener('gama:auth-change',activateClient);
  });
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
