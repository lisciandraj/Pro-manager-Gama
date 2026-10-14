import {translate as t} from '../domain/format.js';

let sequence=0;
const forms=new WeakSet();
const errors=new WeakMap();
function message(control){
  const v=control.validity;
  if(v.customError)return control.validationMessage;
  if(v.valueMissing)return t('Completa este campo.');
  if(v.typeMismatch&&control.type==='email')return t('Introduce una dirección de correo válida.');
  if(v.rangeUnderflow)return t('El valor mínimo es')+' '+control.min+'.';
  if(v.rangeOverflow)return t('El valor máximo es')+' '+control.max+'.';
  if(v.tooShort)return t('El mínimo de caracteres es')+' '+control.minLength+'.';
  if(v.tooLong)return t('El máximo de caracteres es')+' '+control.maxLength+'.';
  return t('Revisa el formato o el valor de este campo.');
}
function show(control){
  let state=errors.get(control);
  if(!state){
    const id=control.id&&control.ownerDocument.getElementById(control.id+'-error');
    const node=id||document.createElement('small');
    if(!id){node.id='arc-validation-'+(++sequence);node.className='arcFieldError';control.after(node);}
    state={node,description:control.getAttribute('aria-describedby'),invalid:control.getAttribute('aria-invalid')};
    errors.set(control,state);
  }
  state.node.hidden=false;state.node.textContent=message(control);
  control.setAttribute('aria-invalid','true');
  control.setAttribute('aria-describedby',[...new Set([...(state.description||'').split(/\s+/).filter(Boolean),state.node.id])].join(' '));
}
function clear(control){
  const state=errors.get(control);if(!state||!control.validity.valid)return;
  state.node.hidden=true;state.node.textContent='';
  if(state.description==null)control.removeAttribute('aria-describedby');else control.setAttribute('aria-describedby',state.description);
  if(state.invalid==null)control.removeAttribute('aria-invalid');else control.setAttribute('aria-invalid',state.invalid);
}
/** Keep native constraints and submission handlers; add persistent field-level feedback. */
export function mountFieldValidation(root){
  const candidates=[...(root.matches?.('form')?[root]:[]),...root.querySelectorAll('form')];
  for(const form of candidates){
    if(forms.has(form))continue;forms.add(form);let first=null;
    form.addEventListener('invalid',event=>{
      const control=event.target;if(!control.matches('input,select,textarea'))return;
      event.preventDefault();show(control);
      if(first)return;first=control;
      queueMicrotask(()=>{const target=first;first=null;if(!target?.isConnected)return;
        for(let p=target.parentElement;p&&p!==form;p=p.parentElement)if(p.tagName==='DETAILS')p.open=true;
        target.focus();
      });
    },true);
    for(const type of ['input','change'])form.addEventListener(type,event=>{
      const control=event.target;if(!errors.has(control))return;
      if(control.validity.valid)clear(control);else show(control);
    });
  }
}
window.addEventListener('gama:language-change',()=>{
  for(const control of document.querySelectorAll('form [aria-invalid=true]'))if(errors.has(control))show(control);
});
