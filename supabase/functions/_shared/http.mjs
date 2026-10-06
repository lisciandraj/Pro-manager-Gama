/** Byte limits apply while streaming, before decoding or allocating the JSON object. */
export class BodyError extends Error {
 constructor(code,status){super(code);this.status=status;}
}
export async function readJsonBody(request,maxBytes,{objectOnly=true}={}){
 if(Number(request.headers.get('content-length'))>maxBytes)throw new BodyError('PAYLOAD_TOO_LARGE',413);
 const reader=request.body?.getReader();if(!reader)throw new BodyError('INVALID_JSON',400);
 let timer,size=0;
 const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new BodyError('PAYLOAD_TIMEOUT',408)),10000)});
 try{
  const chunks=[];
  for(;;){const {done,value}=await Promise.race([reader.read(),timeout]);if(done)break;
   size+=value.byteLength;if(size>maxBytes)throw new BodyError('PAYLOAD_TOO_LARGE',413);chunks.push(value)}
  const bytes=new Uint8Array(size);let offset=0;
  for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength}
  let data;try{data=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes))}catch{throw new BodyError('INVALID_JSON',400)}
  if(objectOnly&&(!data||typeof data!=='object'||Array.isArray(data)))throw new BodyError('INVALID_JSON',400);
  return data;
 }catch(error){reader.cancel().catch(()=>{});throw error}
 finally{clearTimeout(timer);reader.releaseLock()}
}
