// Identical canonical resource contract to ArchitectIdentity.identityEdgeResource.
export async function identityEdgeResource(operation,email,role,customerId=''){
 const bytes=new TextEncoder().encode(JSON.stringify([operation,email.trim().toLowerCase(),role,customerId]));
 const hash=await crypto.subtle.digest('SHA-256',bytes);
 return 'identity-edge:'+Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('');
}
