import {test} from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtemp,readFile,readdir,stat,writeFile,mkdir,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {checkConfiguration,checkService} from '../scripts/check-tms-road-service.mjs';

const execute=promisify(execFile),token='a'.repeat(64),version='test-graph';
const checker=path.resolve('scripts/check-tms-road-service.mjs'),prepare=path.resolve('services/tms-routing/deploy/prepare.py');
const points=Array.from({length:100},(_,i)=>[-78.52+(i%12)*.002,-.22+Math.floor(i/12)*.002]);
async function provider(t,{open=false,badVersion=false,malformed=false}={}){
 const server=http.createServer((req,res)=>{
  const u=new URL(req.url,'http://localhost');
  if(!open&&(req.headers.authorization!=='Bearer '+token||!u.pathname.startsWith('/table/'))){res.writeHead(401);res.end();return}
  if(!u.pathname.startsWith('/table/')){res.writeHead(200);res.end('{}');return}
  const pts=u.pathname.split('/').at(-1).split(';').map(p=>p.split(',').map(Number));
  const sources=(u.searchParams.get('sources')||'0').split(';').map(Number),destinations=(u.searchParams.get('destinations')||'1').split(';').map(Number);
  const cost=(i,j)=>i===j?0:100+Math.abs(pts[i][0]-pts[j][0])*10000+(pts[i][1]<pts[j][1]?10:0);
  res.writeHead(200,{'content-type':'application/json','x-coco-road-version':badVersion?'old':version});
  res.end(JSON.stringify(malformed?{message:'upstream coordinate and private secret'}:{code:'Ok',sources:sources.map(()=>({distance:0})),destinations:destinations.map(()=>({distance:0})),distances:sources.map(i=>destinations.map(j=>cost(i,j))),durations:sources.map(i=>destinations.map(j=>cost(i,j)/10))}));
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.closeAllConnections();server.close()});
 return {TMS_OSRM_URL:'http://127.0.0.1:'+server.address().port,TMS_OSRM_TOKEN:token,TMS_ROAD_DATA_VERSION:version};
}

test('road-service checks cannot send coordinates to an HTTP external or demo server',()=>{
 for(const base of ['http://roads.example.invalid','https://router.project-osrm.org','https://routing.openstreetmap.de/routed-car'])assert.throws(()=>checkConfiguration({TMS_OSRM_URL:base}));
 assert.throws(()=>checkConfiguration({TMS_OSRM_URL:'http://192.168.1.5:5000'},true,true),/LOOPBACK_REQUIRED/);
 assert.throws(()=>checkConfiguration({TMS_OSRM_URL:'https://roads.example.invalid'},false,true),/RAW_OSRM_REQUIRES_LOOPBACK/);
 assert.equal(checkConfiguration({TMS_OSRM_URL:'http://127.0.0.1:5000'},true,true).base,'http://127.0.0.1:5000');
});

test('private service readiness checks cover auth, version and 20/50/100 matrices',async t=>{
 const env=await provider(t);const result=await checkService({env,loopback:true,points,sizes:[20,50,100]});
 assert.equal(result.ok,true);assert.equal(result.version,version);
 assert.deepEqual(result.results.map(r=>[r.locations,r.cells,r.requests,r.unreachable]),[[20,400,1,0],[50,2500,4,0],[100,10000,9,0]]);
 assert.ok(!JSON.stringify(result).includes(token));assert.ok(!JSON.stringify(result).includes('-78.52'));
});

test('an open proxy or stale graph fails readiness before publishing routing configuration',async t=>{
 const open=await provider(t,{open:true});await assert.rejects(checkService({env:open,loopback:true,points:points.slice(0,2)}),/ROAD_PROXY_NOT_CLOSED/);
 const stale=await provider(t,{badVersion:true});await assert.rejects(checkService({env:stale,loopback:true,points:points.slice(0,2)}),/ROAD_VERSION_MISMATCH/);
});

test('readiness CLI sanitizes upstream errors instead of printing tokens or coordinate URLs',async t=>{
 const env=await provider(t,{malformed:true});
 await assert.rejects(execute(process.execPath,[checker,'--loopback'],{env:{...process.env,...env}}),error=>{
  assert.equal(error.code,1);assert.deepEqual(JSON.parse(error.stderr),{ok:false,error:'ROAD_SERVICE_CHECK_FAILED'});
  assert.ok(!error.stderr.includes(token));assert.ok(!error.stderr.includes('-78.'));assert.equal(error.stdout,'');return true;
 });
});

test('deployment initialization creates private credentials and refuses host injection or replacement',async t=>{
 const dir=await mkdtemp(path.join(tmpdir(),'coco-road-init-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const args=['--state-dir',dir,'init','--host','roads.example.invalid','--email','ops@example.invalid'];
 const result=await execute('python3',[prepare,...args]);assert.equal(JSON.parse(result.stdout).initialized,true);
 const file=path.join(dir,'server.env'),first=await readFile(file),mode=(await stat(file)).mode&0o777;
 assert.equal(mode,0o600);assert.match(first.toString(),/TMS_OSRM_TOKEN=[a-f0-9]{64}\n/);assert.ok(!result.stdout.includes('TMS_OSRM_TOKEN='));
 await assert.rejects(execute('python3',[prepare,...args]));assert.equal(createHash('sha256').update(await readFile(file)).digest('hex'),createHash('sha256').update(first).digest('hex'));
 for(const host of ['https://roads.example.invalid','roads.example.invalid:5000','evil\nTOKEN=leak','127.0.0.1','x.invalid}'])await assert.rejects(execute('python3',[prepare,'--state-dir',path.join(dir,'invalid'),'init','--host',host,'--email','ops@example.invalid']));
});

test('failed graph preprocessing preserves the previous live configuration and sanitizes subprocess output',async t=>{
 const dir=await mkdtemp(path.join(tmpdir(),'coco-road-prepare-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 await execute('python3',[prepare,'--state-dir',dir,'init','--host','roads.example.invalid','--email','ops@example.invalid']);
 const before=createHash('sha256').update(await readFile(path.join(dir,'server.env'))).digest('hex');
 const bin=path.join(dir,'bin');await mkdir(bin);await writeFile(path.join(bin,'docker'),'#!/bin/sh\nprintf "private-token-and-coordinate-url" >&2\nexit 23\n',{mode:0o700});
 const input=path.join(dir,'network.osm');await writeFile(input,'<osm version="0.6"/>');
 await assert.rejects(execute('python3',[prepare,'--state-dir',dir,'prepare','--input',input],{env:{...process.env,PATH:bin+path.delimiter+process.env.PATH}}),error=>{
  assert.equal(error.code,1);assert.deepEqual(JSON.parse(error.stdout),{ok:false,error:'ROUTING_PREPARATION_FAILED'});assert.equal(error.stderr,'');return true;
 });
 assert.equal(createHash('sha256').update(await readFile(path.join(dir,'server.env'))).digest('hex'),before);
 assert.deepEqual(await readdir(path.join(dir,'datasets')),[]);
});
