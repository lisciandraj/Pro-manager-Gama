const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {INITIAL_MFA:I,VERSION_TAG,promoteInitialMfa}=require('../scripts/promote-initial-mfa.cjs');
const repository='lisciandraj/Pro-manager-Gama',later='f'.repeat(40),normal='1'.repeat(40),development='2'.repeat(40);
const releaseJobs=['stock-adjustments','stock-concurrency','sri-connector','shared-interface','validate'];
const pagesJobs=['build','topbar-menus','business-modules'];
const error=status=>Object.assign(Error('fixture HTTP '+status),{status});
const successJobs=names=>names.map(name=>({name,status:'completed',conclusion:'success'}));
function fixture(){
 const association={number:291,head:{sha:I.candidate,ref:I.branch},base:{sha:I.base,ref:'production'}};
 const state={production:I.base,tag:null,mutations:[],dispatches:0,productionReads:0,queries:[],normalAncestor:true,
  comparison:{status:'ahead',ahead_by:1,behind_by:0,total_commits:1,commits:[{sha:I.candidate}],files:Object.entries(I.files).map(([filename,sha])=>({filename,sha,status:filename==='tests/environment-mfa.test.cjs'?'added':'modified'}))},
  candidate:{sha:I.candidate,tree:{sha:I.tree},parents:[{sha:I.base}]},
  merge:{sha:I.testedMerge,tree:{sha:I.tree},parents:[{sha:I.base},{sha:I.candidate}]},
  pull:{number:291,head:{sha:I.candidate,ref:I.branch,repo:{full_name:repository}},base:{ref:'production',sha:I.base,repo:{full_name:repository}}},
  runs:{},jobs:{},normalRelease:true,normalPages:true};
 for(const [id,workflow,names] of [[I.releaseRun,'validate-release.yml',releaseJobs],[I.pagesRun,'deploy-coco-pages.yml',pagesJobs]]){
  state.runs[id]={id,run_attempt:1,status:'completed',conclusion:'success',event:'pull_request',head_sha:I.candidate,head_commit:{id:I.candidate},head_branch:I.branch,repository:{full_name:repository},head_repository:{full_name:repository},path:'.github/workflows/'+workflow,pull_requests:[structuredClone(association)]};
  state.jobs[id]=successJobs(names);
 }
 const github={rest:{git:{
  getRef:async({ref})=>{
   if(ref==='heads/development')return {data:{object:{type:'commit',sha:development}}};
   if(ref==='heads/production'){
    state.productionReads++;state.onProductionRead?.(state);
    if(!state.production)throw error(404);
    return {data:{object:{type:'commit',sha:state.production}}};
   }
   if(!state.tag)throw error(404);return {data:{object:state.tag}};
  },
  getCommit:async({commit_sha})=>({data:commit_sha===I.candidate?state.candidate:state.merge}),
  createRef:async args=>{
   if(args.ref.startsWith('refs/tags/')){
    state.beforeTagCreate?.(state);
    if(state.tag)throw error(422);
    state.tag={type:'commit',sha:args.sha};
   }else{if(state.production)throw error(422);state.production=args.sha;}
   state.mutations.push({op:'create',...args});return {data:{}};
  },
  updateRef:async args=>{
   state.updateAttempts??=[];state.updateAttempts.push(args);state.beforeUpdate?.(state);
   if(args.force!==false||![I.base,args.sha].includes(state.production))throw error(422);
   state.production=args.sha;state.mutations.push({op:'update',...args});return {data:{}};
  }
 },repos:{compareCommitsWithBasehead:async({basehead})=>({data:basehead===I.base+'...'+I.candidate?state.comparison:{merge_base_commit:{sha:state.normalAncestor?normal:later}}})},
 pulls:{get:async()=>({data:state.pull})},actions:{
  getWorkflowRun:async({run_id})=>{if(!state.runs[run_id])throw error(404);return {data:state.runs[run_id]};},
  listJobsForWorkflowRun:async({run_id})=>({data:{jobs:state.jobs[run_id]||successJobs(state.normalPages?pagesJobs:pagesJobs.slice(1))}}),
  listWorkflowRuns:async args=>{
   state.queries.push(args);
   return {data:{workflow_runs:args.workflow_id==='validate-release.yml'?(state.normalRelease?[{event:'push',conclusion:'success'}]:[]):[{id:900,event:'push',conclusion:'failure'}]}};
  },
  createWorkflowDispatch:async args=>{if(state.dispatchFailure){state.dispatchFailure=false;throw error(503);}state.dispatches++;state.dispatchArgs=args;return {data:{}};}
 }}};
 github.paginate=async(fn,args)=>(await fn(args)).data.jobs;
 const summary={addHeading(){return this;},addTable(){return this;},async write(){}};
 const args={github,context:{repo:{owner:'lisciandraj',repo:'Pro-manager-Gama'},actor:'lisciandraj',eventName:'workflow_dispatch',ref:'refs/heads/development'},core:{summary},sha:I.candidate,approval:'AUTORISER PRODUCTION'};
 return {state,args};
}
const promote=f=>promoteInitialMfa(f.args);
const refUpdates=state=>state.mutations.filter(change=>change.ref==='heads/production'||change.ref==='refs/heads/production');

test('exact initial MFA approval tags first, advances production without force and dispatches existing Pages',async()=>{
 const f=fixture(),result=await promote(f);
 assert.equal(result.sha,I.candidate);assert.equal(result.alreadyPromoted,false);
 assert.equal(f.state.production,I.candidate);assert.equal(f.state.tag.sha,I.candidate);
 assert.deepEqual(f.state.mutations.map(change=>[change.op,change.ref]),[['create','refs/tags/'+VERSION_TAG],['update','heads/production']]);
 assert.equal(refUpdates(f.state)[0].force,false);
 assert.deepEqual(f.state.dispatchArgs,{owner:'lisciandraj',repo:'Pro-manager-Gama',workflow_id:'deploy-coco-pages.yml',ref:'development'});
});

test('a dispatch failure can be retried without moving the immutable tag or production again',async()=>{
 const f=fixture();f.state.dispatchFailure=true;
 await assert.rejects(promote(f),/503/);
 const before=structuredClone(f.state.mutations);
 f.state.pull.base.sha=I.candidate;f.state.pull.merge_commit_sha=later;
 const result=await promote(f);
 assert.equal(result.alreadyPromoted,true);assert.deepEqual(f.state.mutations,before);assert.equal(f.state.dispatches,1);
});

test('bootstrap rejects unauthorized actors, missing typed approval and a nonmanual development context before API mutation',async t=>{
 for(const [label,change] of [
  ['actor',f=>f.args.context.actor='someone-else'],['approval',f=>f.args.approval='oui'],
  ['event',f=>f.args.context.eventName='push'],['branch',f=>f.args.context.ref='refs/heads/main'],
  ['arbitrary SHA',f=>f.args.sha=later]
 ])await t.test(label,async()=>{const f=fixture();change(f);await assert.rejects(promote(f));assert.deepEqual(f.state.mutations,[]);assert.equal(f.state.dispatches,0);});
});

test('candidate identity, sole parent, exact tree and all seven file blobs are mandatory',async t=>{
 for(const [label,change] of [
  ['wrong commit',s=>s.candidate.sha=later],['wrong parent',s=>s.candidate.parents[0].sha=later],
  ['extra parent',s=>s.candidate.parents.push({sha:later})],['wrong tree',s=>s.candidate.tree.sha=later],
  ['extra commit',s=>s.comparison.total_commits=2],['wrong path',s=>s.comparison.files[0].filename='src/features/contacts/contacts.js'],
  ['wrong blob',s=>s.comparison.files[0].sha=later],['missing file',s=>s.comparison.files.pop()],
  ['rename',s=>s.comparison.files[0].status='renamed'],['duplicate path',s=>s.comparison.files[0]=s.comparison.files[1]],
  ['wrong tested tree',s=>s.merge.tree.sha=later],['wrong tested merge parents',s=>s.merge.parents.reverse()]
 ])await t.test(label,async()=>{const f=fixture();change(f.state);await assert.rejects(promote(f));assert.deepEqual(f.state.mutations,[]);});
});

test('the fixed PR and successful CI evidence must identify the exact same-repository candidate and tested base',async t=>{
 for(const [label,change] of [
  ['wrong PR',s=>s.pull.number=292],['fork PR',s=>s.pull.head.repo.full_name='someone/fork'],
  ['changed PR head',s=>s.pull.head.sha=later],['missing release',s=>delete s.runs[I.releaseRun]],
  ['missing Pages',s=>delete s.runs[I.pagesRun]],['failed release',s=>s.runs[I.releaseRun].conclusion='failure'],
  ['failed Pages',s=>s.runs[I.pagesRun].conclusion='failure'],['CI pending',s=>s.runs[I.releaseRun].status='in_progress'],
  ['wrong CI head',s=>s.runs[I.releaseRun].head_sha=later],['fork CI',s=>s.runs[I.releaseRun].head_repository.full_name='someone/fork'],
  ['wrong workflow',s=>s.runs[I.releaseRun].path='.github/workflows/other.yml'],
  ['different attempt',s=>s.runs[I.releaseRun].run_attempt=2],['push instead of PR',s=>s.runs[I.releaseRun].event='push'],
  ['unrelated PR',s=>s.runs[I.releaseRun].pull_requests[0].number=290],
  ['wrong tested base',s=>s.runs[I.pagesRun].pull_requests[0].base.sha=later]
 ])await t.test(label,async()=>{const f=fixture();change(f.state);await assert.rejects(promote(f));assert.deepEqual(f.state.mutations,[]);});
});

test('each of the five release and three Pages validation jobs must succeed',async t=>{
 for(const [id,names] of [[I.releaseRun,releaseJobs],[I.pagesRun,pagesJobs]])for(const name of names)await t.test(name,async()=>{
  const f=fixture();f.state.jobs[id].find(job=>job.name===name).conclusion='failure';
  await assert.rejects(promote(f),/Every existing/);assert.deepEqual(f.state.mutations,[]);
 });
});

test('missing or later production refs are rejected even when a correct candidate version tag exists',async t=>{
 for(const current of [null,later])await t.test(String(current),async()=>{
  const f=fixture();f.state.production=current;f.state.tag={type:'commit',sha:I.candidate};
  await assert.rejects(promote(f),/must not be rolled back/);assert.deepEqual(f.state.mutations,[]);assert.equal(f.state.production,current);
 });
});

test('a later production ref observed after tag creation remains untouched',async()=>{
 const f=fixture();f.state.onProductionRead=s=>{if(s.productionReads===3)s.production=later;};
 await assert.rejects(promote(f),/must not be rolled back/);
 assert.equal(f.state.tag.sha,I.candidate);assert.equal(f.state.production,later);assert.deepEqual(refUpdates(f.state),[]);assert.equal(f.state.dispatches,0);
});

test('a concurrent later ref is never overwritten when the non-force API rejects the update',async()=>{
 const f=fixture();f.state.beforeUpdate=s=>s.production=later;
 await assert.rejects(promote(f),/422/);assert.equal(f.state.production,later);
 assert.deepEqual(refUpdates(f.state),[]);assert.equal(f.state.updateAttempts.length,1);assert.equal(f.state.updateAttempts[0].force,false);
});

test('conflicting immutable tags fail before changing production, including a tag-creation race',async t=>{
 for(const race of [false,true])await t.test('race='+race,async()=>{
  const f=fixture(),conflict={type:'commit',sha:later};
  if(race)f.state.beforeTagCreate=s=>s.tag=conflict;else f.state.tag=conflict;
  await assert.rejects(promote(f),/tag conflicts/);assert.equal(f.state.production,I.base);assert.deepEqual(refUpdates(f.state),[]);assert.deepEqual(f.state.tag,conflict);
 });
});

test('an exact tag left by an interrupted ref update is reused without retagging',async()=>{
 const f=fixture();f.state.tag={type:'commit',sha:I.candidate};
 await promote(f);assert.deepEqual(f.state.mutations.map(change=>change.op),['update']);assert.equal(f.state.production,I.candidate);
});

const workflow=fs.readFileSync(path.join(__dirname,'../.github/workflows/promote-coco-production.yml'),'utf8');
const script=workflow.split('          script: |\n')[1].trimEnd().split('\n').map(line=>line.slice(12)).join('\n');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
async function executeWorkflow(f,mode='development'){
 return new AsyncFunction('github','context','core','require','process',script)(f.args.github,f.args.context,f.args.core,require,{env:{RELEASE_COMMIT:mode==='initial-mfa-bootstrap'?I.candidate:normal,RELEASE_APPROVAL:f.args.approval,RELEASE_MODE:mode,GITHUB_WORKSPACE:path.join(__dirname,'..')}});
}
test('manual bootstrap input is wired to the fixed helper, using the trusted development checkout',async()=>{
 const f=fixture();await executeWorkflow(f,'initial-mfa-bootstrap');assert.equal(f.state.production,I.candidate);
 assert.match(workflow,/ref: \$\{\{ github\.sha \}\}/);assert.match(workflow,/if: github\.ref == 'refs\/heads\/development'/);
});

test('normal mode still accepts a fully tested development ancestor while newer unapproved work stays in development',async()=>{
 const f=fixture();await executeWorkflow(f);
 assert.equal(f.state.production,normal);assert.equal(refUpdates(f.state)[0].force,false);assert.equal(f.state.dispatches,1);
 assert.equal(f.state.queries.length,2);
 for(const query of f.state.queries){assert.equal(query.head_sha,normal);assert.equal(query.branch,'development');assert.equal(query.status,'completed');}
});

test('normal owner, typed approval, ancestry, release CI, Pages gates and immutable tag rejection remain enforced',async t=>{
 for(const [label,change] of [
  ['actor',f=>f.args.context.actor='someone-else'],['approval',f=>f.args.approval='oui'],
  ['unrelated commit',f=>f.state.normalAncestor=false],['release CI',f=>f.state.normalRelease=false],
  ['Pages gate',f=>f.state.normalPages=false],['tag conflict',f=>f.state.tag={type:'commit',sha:later}]
 ])await t.test(label,async()=>{const f=fixture();change(f);await assert.rejects(executeWorkflow(f));assert.deepEqual(refUpdates(f.state),[]);assert.equal(f.state.dispatches,0);});
});

test('an unknown promotion mode cannot fall back to normal promotion',async()=>{
 const f=fixture();await assert.rejects(executeWorkflow(f,'arbitrary-backport'),/Unknown/);assert.deepEqual(f.state.mutations,[]);
});
