const crypto=require('node:crypto');
/** Only trusted inline bootstrap scripts receive a content hash. Event attributes
 * remain forbidden; user-controlled HTML cannot acquire executable privileges. */
function secureHtml(html){
 const hashes=[];
 for(const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){
  if(/\bsrc\s*=/.test(match[1])||/\btype=["']application\/(?:json|ld\+json)["']/.test(match[1])||!match[2].trim())continue;
  hashes.push("'sha256-"+crypto.createHash('sha256').update(match[2]).digest('base64')+"'");
 }
 const csp="default-src 'self'; script-src 'self' "+hashes.join(' ')+"; script-src-attr 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https://mknsaibrewksgomuslev.supabase.co wss://mknsaibrewksgomuslev.supabase.co; frame-src 'self'; worker-src 'self' blob:; media-src 'self' blob:; form-action 'self' https://mail.google.com https://outlook.live.com; base-uri 'self'; object-src 'none'; upgrade-insecure-requests";
 const meta='<meta http-equiv="Content-Security-Policy" content="'+csp+'">';
 return /<meta\s+http-equiv=["']Content-Security-Policy/i.test(html)?html.replace(/<meta\s+http-equiv=["']Content-Security-Policy["'][^>]*>/i,meta):html.replace(/<head>/i,'<head>\n'+meta);
}
module.exports={secureHtml};
