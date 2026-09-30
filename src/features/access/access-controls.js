(function(){
'use strict';
const U=window.ArcUI,E=U.esc,F=U.field;
const t=(es,fr,en)=>({es,fr,en}[window.GamaI18n?.language]||es);
const dlg=o=>{const d=U.dialog(o);d.dataset.accessControls='';d.dataset.giIgnore='';return d};
const all=async(table,options={})=>{const r=await window.ArcData.all(table,options);if(r.error)throw r.error;return r.data};
const error=e=>window.gamaToast?.(window.ArcErrors.message(e));
let epoch=0;
async function requireAction(module,action){
 if(!await window.ArcData.rpc('gama_action_allowed',{p_module:module,p_action:action}))throw Error(t('Acción no autorizada por tu perfil.','Action non autorisée par votre profil.','Your profile does not allow this action.'));
}
async function reviews(){
 const token=epoch,[current,history]=await Promise.all([window.ArcData.rpc('gama_access_review',{p_action:'snapshot',p_data:{}}),all('erp_access_reviews',{order:'reviewed_at',ascending:false})]);
 if(token!==epoch)return;
 const detail=s=>`<h3>${t('Usuarios','Utilisateurs','Users')}</h3>${U.table({columns:[{key:'name',label:t('Nombre','Nom','Name')},{key:'role',label:t('Rol','Rôle','Role')},{key:'active',label:t('Activo','Actif','Active'),value:r=>r.active?'✓':'—'}],items:s.profiles||[]})}<details><summary>${t('Módulos y restricciones','Modules et restrictions','Modules and restrictions')}</summary><pre style="white-space:pre-wrap">${E(JSON.stringify({modules:s.modules,rights:s.rights,actions:s.actions},null,2))}</pre></details>`;
 const d=dlg({title:t('Revisión de accesos','Revue des accès','Access review'),saveLabel:t('Registrar la revisión','Enregistrer la revue','Record review'),body:detail(current)+F({key:'next_review',label:t('Próxima revisión','Prochaine revue','Next review'),type:'date',required:true})+F({key:'note',label:t('Conclusión y acciones','Conclusion et actions','Conclusion and actions'),type:'textarea',required:true})+`<h3>${t('Historial de revisiones','Historique des revues','Review history')}</h3>${history.map(r=>`<details><summary>${E(r.reviewed_at.slice(0,10))} · ${E(r.note)} · ${E(r.next_review)}</summary>${detail(r.snapshot)}</details>`).join('')}`,onSave:async el=>{const data=Object.fromEntries(new FormData(el.querySelector('form')));await window.ArcData.rpc('gama_access_review',{p_action:'confirm',p_data:{...data,expected:current}})}});
 return d;
}
async function closing(month,close){
 const c=await window.ArcData.rpc('gama_closing_review',{p_month:month});
 const labels={draft_entries:t('Asientos en borrador','Écritures en brouillon','Draft entries'),unposted_invoices:t('Facturas sin contabilizar','Factures non comptabilisées','Unposted invoices'),unposted_payments:t('Cobros sin contabilizar','Encaissements non comptabilisés','Unposted payments'),unmatched_bank:t('Líneas bancarias sin conciliar','Lignes bancaires non rapprochées','Unmatched bank lines'),unmatched_bills:t('Facturas proveedor sin cotejar','Factures fournisseurs non rapprochées','Unmatched supplier bills'),unassigned_payments:t('Cobros sin cuenta asignada','Encaissements sans compte affecté','Payments without an account')};
 const blocked=c.draft_entries+c.unposted_invoices+c.unposted_payments>0;
 const d=dlg({title:t('Control de cierre','Contrôle de clôture','Closing review'),saveLabel:blocked?t('Cerrar','Fermer','Close'):t('Confirmar el cierre','Confirmer la clôture','Confirm close'),body:`<p>${E(c.from)} → ${E(c.to)}</p>${U.table({columns:[{key:'label',label:t('Control','Contrôle','Check')},{key:'count',label:t('Pendientes','En attente','Pending')}],items:Object.entries(labels).map(([k,label])=>({label,count:c[k]}))})}<p>${blocked?t('Contabiliza las operaciones pendientes antes de cerrar.','Comptabilisez les opérations en attente avant de clôturer.','Post pending transactions before closing.'):t('Revisa las diferencias señaladas. La clausura bloquea nuevas escrituras en este periodo.','Vérifiez les écarts signalés. La clôture bloque les nouvelles écritures sur cette période.','Review the reported differences. Closing blocks new entries in this period.')}</p>`,onSave:async()=>{if(!blocked)await close()}});return d;
}
window.ArchitectAccessControls={reviews:()=>reviews().catch(error),requireAction,closing};
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;document.querySelectorAll('[data-access-controls]').forEach(d=>d.close())});
})();
