import * as Y from 'yjs';
export const MAX_STATE=280000,MAX_TEXT=200000;
export function decode(value){
 if(typeof value!=='string'||value.length>400000||!/^[A-Za-z0-9+/\s]*={0,2}$/.test(value))throw Error('WORKHUB_DOCUMENT_INVALID_STATE');
 let bytes;try{bytes=Uint8Array.from(atob(value.replace(/\s/g,'')),c=>c.charCodeAt(0));}catch{throw Error('WORKHUB_DOCUMENT_INVALID_STATE');}
 if(bytes.length>MAX_STATE)throw Error('WORKHUB_DOCUMENT_TOO_LARGE');return bytes;
}
export function encode(bytes){let s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);}
export function mergeDocument(previous,incoming){
 const doc=new Y.Doc();doc.getText('body');
 try{
  try{if(previous)Y.applyUpdate(doc,decode(previous));Y.applyUpdate(doc,decode(incoming));}catch(e){if(e.message==='WORKHUB_DOCUMENT_TOO_LARGE')throw e;throw Error('WORKHUB_DOCUMENT_INVALID_STATE');}
  if(Object.keys(doc.toJSON()).some(key=>key!=='body'))throw Error('WORKHUB_DOCUMENT_INVALID_STATE');
  const text=doc.getText('body');
  if(text.toDelta().some(op=>typeof op.insert!=='string'||op.attributes&&Object.keys(op.attributes).length))throw Error('WORKHUB_DOCUMENT_INVALID_STATE');
  const body=text.toString(),state=Y.encodeStateAsUpdate(doc);
  if(body.length>100000||new TextEncoder().encode(body).length>MAX_TEXT||state.length>MAX_STATE)throw Error('WORKHUB_DOCUMENT_TOO_LARGE');
  return {body,state:encode(state)};
 }finally{doc.destroy();}
}
