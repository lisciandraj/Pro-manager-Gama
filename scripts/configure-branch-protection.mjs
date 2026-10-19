import fs from 'node:fs/promises';
const desired=JSON.parse(await fs.readFile(new URL('../config/main-branch-protection.json',import.meta.url)));
if(!process.argv.includes('--apply')){console.log(JSON.stringify(desired,null,2));process.exit(0)}
if(!process.env.GH_TOKEN)throw Error('Repository administration token required in GH_TOKEN; never pass it as an argument.');
const url='https://api.github.com/repos/lisciandraj/Pro-manager-Gama/branches/main/protection';
const headers={Authorization:'Bearer '+process.env.GH_TOKEN,Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2026-03-10'};
const old=await fetch(url,{headers,signal:AbortSignal.timeout(15000)});
if(!old.ok&&old.status!==404)throw Error('Unable to read existing protection: HTTP '+old.status);
await fs.writeFile('main-protection-before.json',JSON.stringify(old.status===404?null:await old.json(),null,2),{mode:0o600,flag:'wx'});
const result=await fetch(url,{method:'PUT',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify(desired),signal:AbortSignal.timeout(15000)});
if(!result.ok)throw Error('Protection update failed: HTTP '+result.status);
console.log('main protection applied. Verify a failing pull request is blocked; preserve main-protection-before.json for controlled rollback.');
