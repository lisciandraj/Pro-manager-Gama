/* Retired endpoint: mailbox access belongs to the user's ChatGPT connector. */
export function createHandler(){return async request=>{
 const origin=request.headers.get('Origin');
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
 if(origin==='https://lisciandraj.github.io')Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'GET,POST,OPTIONS'});
 if(request.method==='OPTIONS')return new Response(null,{status:origin==='https://lisciandraj.github.io'?204:403,headers});
 return new Response(JSON.stringify({error:'MAIL_CONNECTOR_REMOVED',message:'Mailbox analysis is managed through ChatGPT. Review proposed actions in Coco ERP.'}),{status:410,headers});
};}
