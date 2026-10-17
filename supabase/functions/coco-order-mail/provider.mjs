/* Official Gmail / Microsoft Graph adapters. No arbitrary URL or sender input. */
export const GOOGLE_SCOPES='https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.readonly';
export const MICROSOFT_SCOPES='offline_access User.Read Mail.ReadWrite Mail.Send';
const encoder=new TextEncoder();
export const b64=bytes=>{let s='';for(let i=0;i<bytes.length;i+=32768)s+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(s)};
export const unb64=s=>Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
export const b64url=bytes=>b64(bytes).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
export const text64=s=>b64(encoder.encode(s));
export const sha=async s=>b64url(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(s))));
export class MailError extends Error{constructor(code,status=400){super(code);this.status=status}}
export function validateAttachments(input=[],provider){
 if(!Array.isArray(input)||input.length>5)throw new MailError('INVALID_ATTACHMENTS');let total=0;
 return input.map(a=>{const name=String(a.name||'').replace(/[\r\n\\/"\u0000-\u001f]/g,'_');
  if(!name||name.length>150||!/^[-\w.+]+\/[-\w.+]+$/.test(a.type||'')||typeof a.content!=='string'||!/^[A-Za-z0-9+/]*={0,2}$/.test(a.content))throw new MailError('INVALID_ATTACHMENTS');
  let size;try{size=unb64(a.content).length}catch{throw new MailError('INVALID_ATTACHMENTS')}
  if(provider==='microsoft'&&size>=3000000)throw new MailError('OUTLOOK_ATTACHMENT_TOO_LARGE');
  total+=size;if(total>5*1024*1024)throw new MailError('ATTACHMENTS_TOO_LARGE');return {name,type:a.type,content:a.content,size};
 });
}
function header(value){if(/[\r\n]/.test(value))throw new MailError('INVALID_MESSAGE');return value}
const encodedHeader=s=>Array.from(s).reduce((a,c)=>{if(!a.length||encoder.encode(a[a.length-1]+c).length>42)a.push(c);else a[a.length-1]+=c;return a},[]).map(x=>'=?UTF-8?B?'+text64(x)+'?=').join('\r\n ');
const wrap64=s=>s.match(/.{1,76}/g)?.join('\r\n')||'';
export function mime(entry,attachments){
 const boundary='coco_'+entry.id.replace(/-/g,''),internet='<'+entry.id+'@coco-erp.invalid>';
 const headers=[`From: ${header(entry.from_email)}`,`To: ${header(entry.to_email)}`,`Subject: ${encodedHeader(header(entry.subject))}`,`Message-ID: ${internet}`,'MIME-Version: 1.0'];
 if(entry.reply?.internet_id){const id=header(entry.reply.internet_id);if(!/^<[^<>\s]+>$/.test(id))throw new MailError('INVALID_REPLY');headers.push('In-Reply-To: '+id,'References: '+id)}
 const body=['Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',wrap64(text64(entry.body))].join('\r\n');
 if(!attachments.length)return {raw:headers.concat(body).join('\r\n'),internet};
 headers.push('Content-Type: multipart/mixed; boundary="'+boundary+'"','');
 const parts=[body,...attachments.map(a=>[`Content-Type: ${a.type}`,`Content-Disposition: attachment; filename="${a.name.replace(/[^\x20-\x7e]/g,'_')}"; filename*=UTF-8''${encodeURIComponent(a.name)}`,'Content-Transfer-Encoding: base64','',wrap64(a.content)].join('\r\n'))];
 return {raw:headers.join('\r\n')+'\r\n--'+boundary+'\r\n'+parts.join('\r\n--'+boundary+'\r\n')+'\r\n--'+boundary+'--\r\n',internet};
}
export function createProvider(fetcher){
 async function request(url,token,{method='GET',body,headers={}}={}){
  let r;try{r=await fetcher(url,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json',Prefer:'IdType="ImmutableId", outlook.body-content-type="text"',...headers},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000),redirect:'error'})}catch{throw new MailError('PROVIDER_UNCERTAIN',503)}
  if(!r.ok)throw new MailError(r.status===401?'MAILBOX_RECONNECT':r.status===429?'MAIL_RATE_LIMIT':r.status>=500?'PROVIDER_UNCERTAIN':'MAIL_PROVIDER_REJECTED',r.status>=500?503:400);
  return r.status===202||r.status===204?null:r.json();
 }
 const gmail='https://gmail.googleapis.com/gmail/v1/users/me';
 const graph='https://graph.microsoft.com/v1.0/me';
 async function send(account,entry,attachments,save){
  if(account.provider==='google'){
   const message=mime(entry,attachments);await save({internet_id:message.internet});
   const data=await request(gmail+'/messages/send',account.access_token,{method:'POST',body:{raw:b64url(encoder.encode(message.raw)),...(entry.reply?.thread_id?{threadId:entry.reply.thread_id}:{})}});
   if(!data?.id||!data.threadId)throw new MailError('PROVIDER_UNCERTAIN',503);
   return {status:'sent',provider_id:data.id,thread_id:data.threadId,internet_id:message.internet};
  }
  const content={subject:entry.subject,body:{contentType:'Text',content:entry.body},toRecipients:[{emailAddress:{address:entry.to_email}}],ccRecipients:[],bccRecipients:[],attachments:attachments.map(a=>({'@odata.type':'#microsoft.graph.fileAttachment',name:a.name,contentType:a.type,contentBytes:a.content}))};
  let draft;
  const {attachments:files,...update}=content;
  if(entry.reply?.provider_id){
   draft=await request(graph+'/messages/'+encodeURIComponent(entry.reply.provider_id)+'/createReply',account.access_token,{method:'POST',body:{}});
   draft=await request(graph+'/messages/'+encodeURIComponent(draft.id),account.access_token,{method:'PATCH',body:update});
  }else draft=await request(graph+'/messages',account.access_token,{method:'POST',body:{...update,internetMessageHeaders:[{name:'x-coco-request-id',value:entry.id}]}});
  if(!draft?.id||!draft.conversationId)throw new MailError('PROVIDER_UNCERTAIN',503);
  const refs={provider_id:draft.id,thread_id:draft.conversationId,internet_id:draft.internetMessageId};await save(refs);
  for(const file of files)await request(graph+'/messages/'+encodeURIComponent(draft.id)+'/attachments',account.access_token,{method:'POST',body:file});
  await request(graph+'/messages/'+encodeURIComponent(draft.id)+'/send',account.access_token,{method:'POST'});
  // 202 is acceptance for processing, never delivery or read confirmation.
  return {...refs,status:'accepted'};
 }
 async function thread(account,id){
  if(account.provider==='google'){
   const d=await request(gmail+'/threads/'+encodeURIComponent(id)+'?format=full',account.access_token);
   return (d.messages||[]).filter(m=>!m.labelIds?.includes('DRAFT')).map(gmailMessage);
  }
  let next=graph+'/messages?'+new URLSearchParams({$filter:"conversationId eq '"+id.replace(/'/g,"''")+"'",$select:'id,conversationId,internetMessageId,subject,body,from,toRecipients,receivedDateTime,sentDateTime,isDraft,hasAttachments',$top:'100'});const rows=[];
  for(let n=0;next&&n<10;n++){
   const u=new URL(next);if(u.origin!=='https://graph.microsoft.com'||!u.pathname.startsWith('/v1.0/me/messages'))throw new MailError('INVALID_PROVIDER_PAGE');
   const d=await request(next,account.access_token);rows.push(...(d.value||[]).filter(m=>!m.isDraft).map(m=>({provider_id:m.id,thread_id:m.conversationId,internet_id:m.internetMessageId,subject:m.subject||'',body:m.body?.contentType?.toLowerCase()==='text'?String(m.body.content).slice(0,100000):plain(m.body?.content||''),from_email:m.from?.emailAddress?.address||'',sender:m.from?.emailAddress?.name||m.from?.emailAddress?.address||'',to_email:(m.toRecipients||[]).map(r=>r.emailAddress.address).join(', '),created_at:m.sentDateTime||m.receivedDateTime,attachments:m.hasAttachments?[{name:'ATTACHMENTS_IN_MAILBOX'}]:[]})));next=d['@odata.nextLink'];
  }
  if(next)throw new MailError('THREAD_TOO_LARGE');return rows;
 }
 async function recover(account,entry){
  if(account.provider!=='google'||!/^<[a-f0-9-]+@coco-erp\.invalid>$/.test(entry.internet_id||''))return null;
  const found=await request(gmail+'/messages?'+new URLSearchParams({q:'in:sent rfc822msgid:'+entry.internet_id,maxResults:'2'}),account.access_token);
  if(found.messages?.length!==1)return null;
  const message=await request(gmail+'/messages/'+encodeURIComponent(found.messages[0].id)+'?format=metadata',account.access_token);
  if(!message.labelIds?.includes('SENT'))return null;
  const id=message.payload?.headers?.find(h=>h.name.toLowerCase()==='message-id')?.value;
  if(id!==entry.internet_id)return null;
  return {status:'sent',provider_id:message.id,thread_id:message.threadId,internet_id:id};
 }
 async function identity(provider,token){const d=await request(provider==='google'?gmail+'/profile':graph+'?$select=mail,userPrincipalName',token);return provider==='google'?d.emailAddress:d.mail||d.userPrincipalName}
 return {send,thread,identity,recover};
}
function plain(value){return String(value).replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi,'').replace(/<br\s*\/?>|<\/p>|<\/div>/gi,'\n').replace(/<[^>]*>/g,'').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').slice(0,100000)}
export function gmailMessage(m){
 const headers=m.payload?.headers||[],get=name=>headers.find(h=>h.name.toLowerCase()===name.toLowerCase())?.value||'';
 const parts=[],files=[];function walk(p){if(!p)return;if(p.filename){files.push({name:p.filename,size:p.body?.size||0});return}if(p.body?.data)try{parts.push({type:p.mimeType,body:new TextDecoder().decode(unb64(p.body.data))})}catch{}for(const x of p.parts||[])walk(x)}walk(m.payload);
 const from=get('From'),address=from.match(/<([^<>]+)>/)?.[1]||from;
 return {provider_id:m.id,thread_id:m.threadId,internet_id:get('Message-ID'),subject:get('Subject'),body:parts.filter(p=>p.type==='text/plain').map(p=>p.body).join('\n')||plain(parts.filter(p=>p.type==='text/html').map(p=>p.body).join('\n')),from_email:address.trim().toLowerCase(),sender:from,to_email:get('To'),created_at:new Date(Number(m.internalDate)).toISOString(),attachments:files};
}
