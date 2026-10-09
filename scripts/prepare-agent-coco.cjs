/* One-time, idempotent source integration. Run on the feature branch, then build. */
'use strict';
const fs=require('node:fs'),cp=require('node:child_process');
function patch(file,marker,changes){let source=fs.readFileSync(file,'utf8');if(source.includes(marker))return;for(const [before,after] of changes){if(source.split(before).length!==2)throw Error('Source drift: '+file+' / '+before.slice(0,60));source=source.replace(before,after)}fs.writeFileSync(file,source)}
const manifestFile='config/runtime-assets.json',manifest=JSON.parse(fs.readFileSync(manifestFile,'utf8'));
if(!manifest.scripts.some(s=>s.output==='coco-agent-stock.js')){manifest.scripts.push({source:'src/features/intelligence/agent-coco-stock.js',output:'coco-agent-stock.js'});fs.writeFileSync(manifestFile,JSON.stringify(manifest,null,2)+'\n')}
patch('src/features/intelligence/assistant-ia.js','agentStockActions',[
 ['<div class="ai-tools" role="tablist" aria-label="Agent Coco">','<div class="ai-tools"><button id="agentStockActions" class="arcButton" type="button">${tr(\'Stock et connexion\',\'Stock y conexión\',\'Stock and connection\')}</button></div><div class="ai-tools" role="tablist" aria-label="Agent Coco">'],
 ["GamaUI.bindBack(s);window.showTab(ID);","GamaUI.bindBack(s);window.showTab(ID);\n $('agentStockActions').onclick=()=>window.CocoAgentOpen().catch(e=>notice(e.message));"]
]);
const bootstrap=`
// Agent Coco is loaded only when used. OAuth consent waits for a real ERP login.
window.CocoAgentOpen=async()=>{await window.ArcLoadScript('coco-agent-stock.js');return window.CocoAgent.open()};
const agentAuthorizationId=new URLSearchParams(location.search).get('authorization_id');
if(agentAuthorizationId&&/^[A-Za-z0-9_-]{1,200}$/.test(agentAuthorizationId)){
 let started=false;
 const consent=async()=>{if(started||!isAdmin())return;await window.GamaCloudReady;const session=await window.GamaCloud.getSession();if(!session.data?.session)return;started=true;try{await window.ArcLoadScript('coco-agent-stock.js');await window.CocoAgent.consent(agentAuthorizationId)}catch(e){started=false;window.gamaToast?.(e.message)}};
 const schedule=()=>setTimeout(()=>consent().catch(e=>window.gamaToast?.(e.message)),0);
 window.addEventListener('gama:profile-ready',schedule);schedule();
}
`;
patch('src/ui/settings.js','agentAuthorizationId',[
 [" {id:'security',label:'Seguridad de mi cuenta'"," {id:'agent-coco',label:'Agent Coco',icon:'checklist',pane:'agentCoco',admin:true,module:'assistant-ia'},\n {id:'security',label:'Seguridad de mi cuenta'"],
 ["const PANES={","const PANES={\n agentCoco:host=>{const b=document.createElement('button');b.className='arcButton';b.type='button';b.textContent='Agent Coco';b.onclick=()=>window.CocoAgentOpen().catch(e=>window.gamaToast?.(e.message));host.replaceChildren(b)},"],
 ["const HOSTS={sri:","const HOSTS={agentCoco:'cfgAgentCoco',sri:"],
 ["let busy=false;","let busy=false;\n"+bootstrap]
]);
const config='supabase/config.toml';let conf=fs.readFileSync(config,'utf8');
if(!conf.includes('[functions.coco-agent-mcp]')){conf+='\n# Public OAuth discovery only; every MCP POST validates the user token in handler.mjs.\n[functions.coco-agent-mcp]\nverify_jwt = false\n';fs.writeFileSync(config,conf)}
const sqlFile='supabase/sql/agent-coco.sql';let sql=fs.readFileSync(sqlFile,'utf8');
sql=sql.replace('from public.stock_lot_balances where lot_id=private.coco_agent.lot_id and location_id=lid;','from public.stock_lot_balances b where b.lot_id=(p_data->>\'lot_id\')::uuid and b.location_id=lid;');
fs.writeFileSync(sqlFile,sql);
const migrations='supabase/migrations';let file=fs.readdirSync(migrations).find(n=>n.endsWith('_agent_coco_gateway.sql'));
if(!file){
 const before=new Set(fs.readdirSync(migrations));
 for(const args of [['--help'],['migration','--help'],['migration','new','--help'],['migration','new','agent_coco_gateway']])cp.execFileSync('npx',['--yes','supabase@2.120.0',...args],{stdio:'inherit'});
 file=fs.readdirSync(migrations).find(n=>!before.has(n)&&n.endsWith('_agent_coco_gateway.sql'));
 if(!file)throw Error('Supabase CLI did not create the migration');fs.writeFileSync(migrations+'/'+file,sql);
}else if(fs.readFileSync(migrations+'/'+file,'utf8')!==sql){throw Error('Do not overwrite a versioned migration; create a follow-up migration instead')}
console.log('Agent Coco canonical sources and migration are prepared. Run npm run build and the tests.');
