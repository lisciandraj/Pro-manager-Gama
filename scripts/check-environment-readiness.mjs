/* Public, read-only deployment gate. Never use a user session or privileged key. */
import fs from 'node:fs';
import path from 'node:path';
import {createPublicKey} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import packager from './package-environments.cjs';

const {publicBackend,sharedIdentityBackend}=packager;

async function checkIdentity(issuer,fetchImpl){
 const jwksUrl=issuer+'/.well-known/jwks.json';
 const read=async url=>{
  const response=await fetchImpl(url,{credentials:'omit',redirect:'error',cache:'no-store',signal:AbortSignal.timeout(15000)});
  if(!response.ok)throw Error('Identity discovery returned HTTP '+response.status);
  return response.json();
 };
 const discovery=await read(issuer+'/.well-known/openid-configuration');
 if(discovery?.issuer!==issuer||discovery.jwks_uri!==jwksUrl)throw Error('Identity discovery does not match the approved issuer');
 const jwks=await read(jwksUrl);
 if(!Array.isArray(jwks?.keys)||!jwks.keys.some(key=>{
  if(typeof key?.kid!=='string'||!key.kid||!['EC','RSA'].includes(key.kty))return false;
  try{createPublicKey({key,format:'jwk'});return true}catch{return false}
 }))throw Error('Identity issuer must expose an asymmetric signing key');
}

export async function checkEnvironmentReadiness({configuration,productionConfiguration,fetchImpl=globalThis.fetch}){
 const backends={
  development:publicBackend(configuration?.development,'development'),
  production:publicBackend(productionConfiguration?.production,'production')
 };
 // The packager can prepare an intentionally unconfigured production snapshot;
 // publishing it requires both servers to have completed their own setup.
 for(const [name,backend] of Object.entries(backends)){
  if(!backend.supabaseUrl)throw Error(name+' backend is required before publication');
 }
 if(backends.production.supabaseUrl===backends.development.supabaseUrl)throw Error('Production and development must use separate databases');
 const identity=sharedIdentityBackend(configuration,productionConfiguration);
 const results={};
 for(const name of ['production','development']){
  const backend=backends[name];let response,status;
  try{
   response=await fetchImpl(backend.supabaseUrl+'/rest/v1/rpc/coco_environment_status',{
    method:'POST',headers:{apikey:backend.publishableKey,'Content-Type':'application/json',Accept:'application/json'},
    body:'{}',credentials:'omit',redirect:'error',cache:'no-store',signal:AbortSignal.timeout(15000)
   });
  }catch{throw Error(name+' environment readiness RPC could not be reached');}
  if(!response.ok)throw Error(name+' environment readiness RPC returned HTTP '+response.status);
  try{status=await response.json();}catch{throw Error(name+' environment readiness RPC returned invalid JSON');}
  const allowed=name==='production';
  if(!status||typeof status!=='object'||Array.isArray(status)||status.environment!==name||status.allowed!==allowed||status.admin!==false){
   throw Error(name+' environment is not ready: expected its own marker, anonymous access '+allowed+' and no administrator session');
  }
  if(identity&&status.identity_issuer!==identity.supabaseUrl+'/auth/v1')throw Error(name+' environment has not verified the approved identity issuer');
  results[name]={environment:status.environment,allowed:status.allowed,admin:status.admin};
 }
 if(identity)await checkIdentity(identity.supabaseUrl+'/auth/v1',fetchImpl);
 return results;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const [developmentFile,productionFile,...extra]=process.argv.slice(2);
  if(!developmentFile||!productionFile||extra.length)throw Error('Usage: node scripts/check-environment-readiness.mjs <development-config.json> <frozen-production-config.json>');
  const configuration=JSON.parse(fs.readFileSync(developmentFile,'utf8'));
  const productionConfiguration=JSON.parse(fs.readFileSync(productionFile,'utf8'));
  console.log(JSON.stringify(await checkEnvironmentReadiness({configuration,productionConfiguration})));
 }catch(error){console.error('Publication blocked: '+error.message);process.exitCode=1;}
}
