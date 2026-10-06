/** Compatibility endpoint: legacy browser certificates and emissions are retired. */
export function retiredSri(request){
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',
  'Access-Control-Allow-Origin':'https://lisciandraj.github.io','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info',
  'Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 return new Response(JSON.stringify({error:'SRI_LEGACY_ENDPOINT_RETIRED',replacement:'gama-sri'}),{status:410,headers});
}
