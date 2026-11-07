/* A service-only SQL reservation is required before EACH paid provider call.
   Quotas, price ceilings and concurrency are shared by assistant, stock and OCR. */
const safeCode=code=>/^(AI_BUDGET_[A-Z_]+|AI_MODEL_NOT_BUDGETED)$/.test(code||'')?code:'AI_BUDGET_UNAVAILABLE';
export class ProviderBudgetError extends Error{constructor(code,status=503){super(code);this.status=status;}}
export function providerInputReservation(body,{document=false}={}){
 if(document)return 250000; // Conservative floor, not a PDF token-count guarantee.
 return Math.max(1000,new TextEncoder().encode(JSON.stringify(body)).byteLength);
}
export function createProviderBudget({root,service,fetcher}){
 async function rpc(action,data){
  let response;
  try{response=await fetcher(root+'/rest/v1/rpc/coco_ai_provider_budget',{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({p_action:action,p_data:data}),signal:AbortSignal.timeout(10000)});}catch{throw new ProviderBudgetError('AI_BUDGET_UNAVAILABLE');}
  const result=await response.json().catch(()=>null);
  if(!response.ok){const code=safeCode(result?.message);console.warn(JSON.stringify({event:'ai_provider_admission_denied',code}));throw new ProviderBudgetError(code,response.status===429||/LIMIT|CONCURRENCY/.test(result?.message||'')?429:503);}
  return result;
 }
 return async function withProviderBudget({operation,actorId,requestId,body,document=false},perform){
  const lease=await rpc('reserve',{operation,actor_id:actorId,request_id:requestId,model:body.model,input_tokens:providerInputReservation(body,{document}),output_tokens:body.max_output_tokens});
  if(!lease||typeof lease.id!=='string')throw new ProviderBudgetError('AI_BUDGET_UNAVAILABLE');
  let result,complete=false;
  try{result=await perform();complete=true;return result;}
  catch(error){if(error?.usage)result={usage:error.usage};throw error;}
  finally{
   // A timeout or ambiguous upstream failure remains charged at its reservation.
   // Failure to finalize never frees a lease early; the SQL expiry bounds it.
   try{await rpc('finish',{id:lease.id,success:complete,input_tokens:Number.isSafeInteger(result?.usage?.input_tokens)?result.usage.input_tokens:null,output_tokens:Number.isSafeInteger(result?.usage?.output_tokens)?result.usage.output_tokens:null});}catch{console.warn(JSON.stringify({event:'ai_provider_finalization_deferred',code:'AI_BUDGET_FINALIZATION_DEFERRED'}));/* Reservation remains charged until expiry. */}
  }
 };
}
