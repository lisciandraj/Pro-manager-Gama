(function(){
'use strict';
const U=window.ArcUI,E=U.esc,F=U.field;
const t=(es,fr,en)=>({es,fr,en}[window.GamaI18n?.language]||es);
const actions=()=>[['create',t('Crear','Créer','Create')],['edit',t('Modificar','Modifier','Edit')],['delete',t('Eliminar','Supprimer','Delete')],['validate',t('Validar','Valider','Approve')],['export',t('Exportar','Exporter','Export')]];
const dlg=o=>{const d=U.dialog(o);d.dataset.accessControls='';d.dataset.giIgnore='';return d};
const all=async(table,options={})=>{const r=await window.ArcData.all(table,options);if(r.error)throw r.error;return r.data};
const error=e=>window.gamaToast?.(window.ArcErrors.message(e));
let epoch=0;
async function requireAction(module,action){
 if(!await window.ArcData.rpc('gama_action_allowed',{p_module:module,p_action:action}))throw Error(t('Acción no autorizada por tu perfil.','Action non autorisée par votre profil.','Your profile does not allow this action.'));
}
async function permissions(){
 const token=epoch,[roles,rows]=await Promise.all([all('role_module_access',{order:'role'}),all('erp_action_permissions',{order:'role'})]);
 if(token!==epoch)return;
 const modules=window.ArcModules.registry;
 const d=dlg({title:t('Derechos por acción','Droits par action','Action permissions'),body:`<p>${t('Estos límites se añaden a los permisos del rol y de cada módulo. No conceden acceso a datos adicionales. Los ámbitos de RR. HH., proyectos y contabilidad siguen aplicándose.','Ces restrictions complètent les droits du rôle et de chaque module. Elles ne donnent pas accès à des données supplémentaires. Les périmètres RH, projets et comptabilité continuent de s’appliquer.','These restrictions supplement role and module permissions. They do not grant additional data access. HR, project and accounting scopes still apply.')}</p>`+F({key:'role',id:'actionRole',label:t('Perfil','Profil','Profile'),type:'select',required:true,options:roles.map(r=>({id:r.role,name:r.display_name||r.role}))})+'<div data-action-grid></div>',onSave:async el=>{
  const role=el.querySelector('#actionRole').value;
  const changes=[...el.querySelectorAll('[data-action-module]')].map(tr=>({role,module:tr.dataset.actionModule,...Object.fromEntries([...tr.querySelectorAll('input')].map(i=>['allow_'+i.dataset.action,i.checked]))}));
  await window.ArcData.rpc('gama_save_action_permissions',{p_role:role,p_rows:changes,p_expected:rows.filter(r=>r.role===role)});
  window.dispatchEvent(new Event('gama:action-rights-change'));
 }});
 const render=()=>{
  const role=d.querySelector('#actionRole').value;
  const allowed=modules.filter(m=>window.GamaRoleAccess.base(role,m.id)&&window.GamaRoleAccess.enabled(role,m.id));
  U.render(d.querySelector('[data-action-grid]'),role?`<div style="overflow:auto"><table class="arcTable"><thead><tr><th>Module</th>${actions().map(([,label])=>'<th>'+E(label)+'</th>').join('')}</tr></thead><tbody>${allowed.map(m=>{const row=rows.find(r=>r.role===role&&r.module===m.id);return `<tr data-action-module="${E(m.id)}"><td>${E(window.GamaI18n?.t(m.label)||m.label)}</td>${actions().map(([key,label])=>`<td><input type=checkbox data-action="${key}" aria-label="${E(m.label+' · '+label)}" ${row?.['allow_'+key]!==false?'checked':''}></td>`).join('')}</tr>`}).join('')}</tbody></table></div>`:'');
 };
 d.querySelector('#actionRole').onchange=render;render();
}
async function reviews(){
 const token=epoch,[current,history]=await Promise.all([window.ArcData.rpc('gama_access_review',{p_action:'snapshot',p_data:{}}),all('erp_access_reviews',{order:'reviewed_at',ascending:false})]);
 if(token!==epoch)return;
 const detail=s=>`<h3>${t('Usuarios','Utilisateurs','Users')}</h3>${U.table({columns:[{key:'name',label:t('Nombre','Nom','Name')},{key:'role',label:t('Rol','Rôle','Role')},{key:'access_profile',label:t('Perfil','Profil','Profile')},{key:'active',label:t('Activo','Actif','Active'),value:r=>r.active?'✓':'—'}],items:s.profiles||[]})}<details><summary>${t('Módulos y restricciones','Modules et restrictions','Modules and restrictions')}</summary><pre style="white-space:pre-wrap">${E(JSON.stringify({modules:s.modules,rights:s.rights,actions:s.actions},null,2))}</pre></details>`;
 const d=dlg({title:t('Revisión de accesos','Revue des accès','Access review'),saveLabel:t('Registrar la revisión','Enregistrer la revue','Record review'),body:detail(current)+F({key:'next_review',label:t('Próxima revisión','Prochaine revue','Next review'),type:'date',required:true})+F({key:'note',label:t('Conclusión y acciones','Conclusion et actions','Conclusion and actions'),type:'textarea',required:true})+`<h3>${t('Historial de revisiones','Historique des revues','Review history')}</h3>${history.map(r=>`<details><summary>${E(r.reviewed_at.slice(0,10))} · ${E(r.note)} · ${E(r.next_review)}</summary>${detail(r.snapshot)}</details>`).join('')}`,onSave:async el=>{const data=Object.fromEntries(new FormData(el.querySelector('form')));await window.ArcData.rpc('gama_access_review',{p_action:'confirm',p_data:{...data,expected:current}})}});
 return d;
}
async function closing(month,close){
 const c=await window.ArcData.rpc('gama_closing_review',{p_month:month});
 const labels={draft_entries:t('Asientos en borrador','Écritures en brouillon','Draft entries'),unposted_invoices:t('Facturas sin contabilizar','Factures non comptabilisées','Unposted invoices'),unposted_payments:t('Cobros sin contabilizar','Encaissements non comptabilisés','Unposted payments'),unmatched_bank:t('Líneas bancarias sin conciliar','Lignes bancaires non rapprochées','Unmatched bank lines'),unmatched_bills:t('Facturas proveedor sin cotejar','Factures fournisseurs non rapprochées','Unmatched supplier bills'),unassigned_payments:t('Cobros sin cuenta asignada','Encaissements sans compte affecté','Payments without an account')};
 const blocked=c.draft_entries+c.unposted_invoices+c.unposted_payments>0;
 const d=dlg({title:t('Control de cierre','Contrôle de clôture','Closing review'),saveLabel:blocked?t('Cerrar','Fermer','Close'):t('Confirmar el cierre','Confirmer la clôture','Confirm close'),body:`<p>${E(c.from)} → ${E(c.to)}</p>${U.table({columns:[{key:'label',label:t('Control','Contrôle','Check')},{key:'count',label:t('Pendientes','En attente','Pending')}],items:Object.entries(labels).map(([k,label])=>({label,count:c[k]}))})}<p>${blocked?t('Contabiliza las operaciones pendientes antes de cerrar.','Comptabilisez les opérations en attente avant de clôturer.','Post pending transactions before closing.'):t('Revisa las diferencias señaladas. La clausura bloquea nuevas escrituras en este periodo.','Vérifiez les écarts signalés. La clôture bloque les nouvelles écritures sur cette période.','Review the reported differences. Closing blocks new entries in this period.')}</p>`,onSave:async()=>{if(!blocked)await close()}});return d;
}
window.ArchitectAccessControls={permissions:()=>permissions().catch(error),reviews:()=>reviews().catch(error),requireAction,closing};
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;document.querySelectorAll('[data-access-controls]').forEach(d=>d.close())});
})();
