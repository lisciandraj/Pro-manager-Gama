/* MIME draft with real binary attachments. No sender identity or sending is implied. */
(function(){'use strict';
const utf8=s=>new TextEncoder().encode(String(s));
function base64(bytes){let s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s)}
const lines=s=>String(s).replace(/\s/g,'').match(/.{1,76}/g)?.join('\r\n')||'';
function header(value){const chunks=[];let part='',size=0;for(const c of String(value)){const n=utf8(c).length;if(size+n>42){chunks.push(part);part='';size=0}part+=c;size+=n}if(part)chunks.push(part);return chunks.map(s=>'=?UTF-8?B?'+base64(utf8(s))+'?=').join('\r\n ')}
function filename(value){const encoded=encodeURIComponent(value).replace(/[!'()*]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());const units=encoded.match(/%[0-9A-F]{2}|./g)||[],parts=[];let part='';for(const c of units){if(part.length+c.length>45){parts.push(part);part=''}part+=c}parts.push(part);return parts.map((s,i)=>` filename*${i}*=${i===0?"UTF-8''":''}${s}${i<parts.length-1?';':''}`).join('\r\n')}
function build(draft,files){
 if(draft.channel!=='email'||!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(draft.address)||/[\r\n]/.test(draft.subject))throw Error('MARKETING_INVALID_DATA');
 if(!Array.isArray(files)||files.length>5||files.reduce((n,f)=>n+f.size,0)>15728640)throw Error('MARKETING_FILE_LIMIT');
 const boundary='coco_'+crypto.randomUUID().replace(/-/g,''),parts=[`To: ${draft.address}`,`Subject: ${header(draft.subject)}`,'X-Unsent: 1','MIME-Version: 1.0',`Content-Type: multipart/mixed; boundary="${boundary}"`,'',`--${boundary}`,'Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',lines(base64(utf8(draft.message)))];
 for(const f of files){
  if(!/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/i.test(f.mime_type)||!f.filename||/[\x00-\x1f\x7f/\\]/.test(f.filename))throw Error('MARKETING_FILE_FORMAT');
  const data=String(f.content_base64||'').replace(/\s/g,'');if(!/^[A-Za-z0-9+/]+={0,2}$/.test(data)||atob(data).length!==f.size||f.size<1||f.size>5242880)throw Error('MARKETING_FILE_FORMAT');
  parts.push(`--${boundary}`,`Content-Type: ${f.mime_type}`,'Content-Transfer-Encoding: base64','Content-Disposition: attachment;',filename(f.filename),'',lines(data));
 }
 parts.push(`--${boundary}--`,'');return parts.join('\r\n');
}
window.CocoMarketingMail={build};
})();
