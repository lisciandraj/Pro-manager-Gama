const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const sessionId=/^cs_(test|live)_[A-Za-z0-9_]{5,200}$/;
const paymentId=/^pi_[A-Za-z0-9_]{3,200}$/;
export async function verifyStripeSignature(bytes,header,secret,now=Date.now()){
 if(!secret||!header||header.length>2048)return false;
 const pieces=header.split(',').map(p=>p.trim().split('=')),timestamps=pieces.filter(([k])=>k==='t'),digests=pieces.filter(([k])=>k==='v1').map(([,v])=>v);
 if(timestamps.length!==1||!/^\d{1,12}$/.test(timestamps[0][1]||'')||digests.length<1||digests.length>8)return false;
 const timestamp=Number(timestamps[0][1]);if(Math.abs(now/1000-timestamp)>300)return false;
 const prefix=new TextEncoder().encode(timestamps[0][1]+'.'),message=new Uint8Array(prefix.length+bytes.length);message.set(prefix);message.set(bytes,prefix.length);
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['verify']);
 for(const digest of digests){if(!/^[0-9a-f]{64}$/i.test(digest||''))continue;const sig=Uint8Array.from(digest.match(/../g),h=>parseInt(h,16));if(await crypto.subtle.verify('HMAC',key,sig,message))return true}return false;
}
export function validateSession(session,intent){
 if(!sessionId.test(session?.id||'')||session.mode!=='payment'||session.client_reference_id!==intent.id||session.metadata?.coco_intent_id!==intent.id||session.amount_total!==intent.amount_cents||session.currency!==intent.currency.toLowerCase()||session.livemode!==intent.livemode)throw Error('CHECKOUT_SESSION_MISMATCH');
 if(typeof session.url!=='string'||session.url.length>2048)throw Error('CHECKOUT_SESSION_UNAVAILABLE');const url=new URL(session.url);if(url.protocol!=='https:'||url.hostname!=='checkout.stripe.com'||url.username||url.password)throw Error('CHECKOUT_SESSION_MISMATCH');return session;
}
export function projectEvent(event){
 if(!/^evt_[A-Za-z0-9_]{1,180}$/.test(event?.id||'')||!Number.isSafeInteger(event.created)||typeof event.livemode!=='boolean')throw Error('CHECKOUT_EVENT_INVALID');
 const allowed=['checkout.session.completed','checkout.session.async_payment_succeeded','checkout.session.async_payment_failed','checkout.session.expired','charge.refunded','charge.dispute.created','charge.dispute.closed'];
 if(!allowed.includes(event.type))return null;const object=event.data?.object;if(!object||typeof object.livemode==='boolean'&&object.livemode!==event.livemode)throw Error('CHECKOUT_EVENT_INVALID');
 const checkout=event.type.startsWith('checkout.session.'),pid=typeof object.payment_intent==='string'?object.payment_intent:object.payment_intent?.id;
 const rawIntent=object.metadata?.coco_intent_id,intent=uuid.test(rawIntent||'')?rawIntent:null;
 if(!intent&&!paymentId.test(pid||''))return null;
 const amount=checkout?object.amount_total:event.type==='charge.refunded'?object.amount_refunded:object.amount;
 if(!Number.isSafeInteger(amount)||amount<0||amount>99999999||typeof object.currency!=='string'||!/^[a-z]{3}$/.test(object.currency))throw Error('CHECKOUT_EVENT_INVALID');
 if(checkout&&!sessionId.test(object.id||''))throw Error('CHECKOUT_EVENT_INVALID');
 if(checkout&&object.payment_status==='paid'&&!paymentId.test(pid||''))throw Error('CHECKOUT_EVENT_INVALID');
 return {event_id:event.id,event_type:event.type,intent_id:intent,object_id:String(object.id||'').slice(0,200),session_id:checkout?object.id:null,payment_intent:paymentId.test(pid||'')?pid:null,amount_cents:amount,currency:object.currency,livemode:event.livemode,occurred_at:event.created,payment_status:checkout?object.payment_status:null};
}
export function stripeForm(intent,publicUrl,language){
 const base=new URL(publicUrl);if(base.username||base.password||base.hash||!['https:','http:'].includes(base.protocol)||base.protocol==='http:'&&!['localhost','127.0.0.1'].includes(base.hostname))throw Error('CHECKOUT_RETURN_URL_INVALID');
 const success=new URL(base),cancel=new URL(base);if(['es','fr','en'].includes(language)){success.searchParams.set('lang',language);cancel.searchParams.set('lang',language)}success.searchParams.set('payment_return',intent.id);success.searchParams.set('payment','success');cancel.searchParams.set('payment_return',intent.id);cancel.searchParams.set('payment','cancel');
 return new URLSearchParams({mode:'payment','payment_method_types[0]':'card',client_reference_id:intent.id,'metadata[coco_intent_id]':intent.id,'payment_intent_data[metadata][coco_intent_id]':intent.id,
  'line_items[0][quantity]':'1','line_items[0][price_data][currency]':intent.currency.toLowerCase(),'line_items[0][price_data][unit_amount]':String(intent.amount_cents),'line_items[0][price_data][product_data][name]':intent.label,
  success_url:success.href,cancel_url:cancel.href,expires_at:String(intent.expires_at),locale:['es','fr','en'].includes(language)?language:'auto'});
}
export {uuid,sessionId};
