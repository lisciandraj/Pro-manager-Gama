/* GAMA V11 - Supabase Auth bridge
 * Uses Supabase Auth for the real multi-user session.
 * Existing local access control remains as a compatibility layer during migration.
 */
(function(){
  'use strict';
  function boot(){
    if(!window.GamaCloud){return setTimeout(boot,250);}
    window.GamaCloudReady.then(function(){
      var C=window.GamaCloud;
      function roleMap(role){return role==='administrador'?'admin':role==='comercial'?'commercial':role==='almacenero'?'magasinier':null;}
      function setCompat(session,profile){
        if(!session||!session.user||!profile)return false;
        var role=roleMap(profile.role); if(!role||profile.active===false)return false;
        localStorage.setItem('gama_session_v1',JSON.stringify({userId:session.user.id,role:role,username:session.user.email||'',name:profile.full_name||session.user.email||''}));
        return true;
      }
      function style(){if(document.getElementById('gamaCloudAuthStyle'))return;var s=document.createElement('style');s.id='gamaCloudAuthStyle';s.textContent='#gamaCloudLogin{position:fixed;inset:0;z-index:100000;background:#F5F7FA;display:grid;place-items:center;padding:20px}#gamaCloudLogin .box{width:min(430px,100%);background:#fff;border:1px solid #E2E8EC;border-radius:20px;padding:26px;box-shadow:0 15px 45px #18324a18}#gamaCloudLogin h1{margin:0 0 5px;color:#18324A}#gamaCloudLogin p{color:#71808a;font-size:13px}#gamaCloudLogin input{width:100%;padding:12px;margin:5px 0 10px;border:1px solid #D4E0E4;border-radius:9px;font-size:16px}#gamaCloudLogin button{width:100%;padding:12px;border:0;border-radius:9px;background:#087C8B;color:#fff;font-weight:800}#gamaCloudLogin .err{margin-top:10px;background:#FFF0EC;color:#C94F45;padding:10px;border-radius:8px;font-size:12px}';document.head.appendChild(s)}
      async function ensure(){
        var r=await C.getSession(); var sess=r&&r.data&&r.data.session;
        if(sess){var p=await C.getProfile();if(p&&p.data&&setCompat(sess,p.data)){var old=document.getElementById('gamaLogin');if(old)old.remove();return true;}}
        showLogin();return false;
      }
      function showLogin(){
        style(); if(document.getElementById('gamaCloudLogin'))return;
        var d=document.createElement('div');d.id='gamaCloudLogin';d.innerHTML='<div class="box"><div style="font-size:20px;font-weight:900;color:#087C8B;margin-bottom:18px">GAMA <span style="color:#F47A2A">Stock Manager</span></div><h1>Connexion</h1><p>Connectez-vous avec votre compte GAMA centralisé.</p><label>Email</label><input id="gamaCloudEmail" type="email" autocomplete="username" placeholder="email@exemple.com"><label>Mot de passe</label><input id="gamaCloudPass" type="password" autocomplete="current-password" placeholder="Mot de passe"><button id="gamaCloudLoginBtn">Se connecter</button><div id="gamaCloudErr" class="err" style="display:none"></div></div>';
        document.body.appendChild(d);
        var go=async function(){var email=document.getElementById('gamaCloudEmail').value.trim().toLowerCase(),pass=document.getElementById('gamaCloudPass').value,err=document.getElementById('gamaCloudErr');err.style.display='none';if(!email||!pass){err.textContent='Email et mot de passe requis.';err.style.display='block';return;}var res=await C.signIn(email,pass);if(res.error){err.textContent='Connexion impossible. Vérifiez vos identifiants.';err.style.display='block';return;}var p=await C.getProfile();if(!p.data||!p.data.active){await C.signOut();err.textContent='Compte non autorisé ou désactivé.';err.style.display='block';return;}setCompat(res.data.session,p.data);location.reload();};
        document.getElementById('gamaCloudLoginBtn').onclick=go;document.getElementById('gamaCloudPass').onkeydown=function(e){if(e.key==='Enter')go()};
      }
      ensure();
      window.addEventListener('gama:auth-change',function(e){if(e.detail&&e.detail.session){C.getProfile().then(function(p){setCompat(e.detail.session,p.data);});}});
    }).catch(function(err){console.warn('[GAMA] Cloud auth unavailable',err);});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
