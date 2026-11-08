/* Fixed initial code-only promotion. Never execute candidate code with this token. */
const INITIAL_MFA=Object.freeze({
 candidate:'8c465ace2b042161eed8f2c25e080c736ce836c0',
 base:'20272ccbd040a5a00b32d6632ba8ad9eb1b72481',
 tree:'c7e54e1619396066283022863dedd67f742f88ef',
 testedMerge:'a9a10c91093a2b7a6c0d568eb8b634d2c873f1fa',
 pull:291,branch:'release/coco-initial-mfa-8c465ace',
 releaseRun:42500077618,pagesRun:42500077596,attempt:1,
 files:Object.freeze({
  'architect-assets.js':'07c61fae4a8ee3812af16b613ece5d76292fb255',
  'architect-identity.js':'d3d2fffd66c7486258c6769c24a693365eabd4d3',
  'index.html':'18dc702a4ebb0724c38a6e96508425d0bdd470f5',
  'src/features/access/identity.js':'2d20d32837ad5c3963328062107401cb8dbd9f80',
  'sw.js':'6f8f0a367db8b81c9d53e735451c5c0e44b7ae6b',
  'tests/environment-mfa.test.cjs':'e5405f98b0c574a35d09b40476d6e0eb3d38dfa9',
  'tms-driver.html':'adb385b4354da69135e967a83c7f45a45768556e'
 })
});
const VERSION_TAG='production/initial-mfa-'+INITIAL_MFA.candidate;
const RELEASE_JOBS=['stock-adjustments','stock-concurrency','sri-connector','shared-interface','validate'];
const PAGES_JOBS=['build','topbar-menus','business-modules'];

async function promoteInitialMfa({github,context,core,sha,approval}){
 const {owner,repo}=context.repo,repository=owner+'/'+repo;
 if(context.actor!==owner)throw Error('Only the repository owner may authorize a production release.');
 if(context.eventName!=='workflow_dispatch'||context.ref!=='refs/heads/development')throw Error('Initial MFA approval must use the manual development workflow.');
 if(approval!=='AUTORISER PRODUCTION')throw Error('Explicit production approval is required.');
 if(sha!==INITIAL_MFA.candidate)throw Error('Initial MFA mode accepts only its fixed tested candidate.');
 const getRef=async ref=>{
  try{return (await github.rest.git.getRef({owner,repo,ref})).data.object;}
  catch(error){if(error.status===404)return null;throw error;}
 };
 const production=async()=>{
  const current=(await getRef('heads/production'))?.sha;
  if(current!==INITIAL_MFA.base&&current!==sha)throw Error('Initial MFA promotion requires the original production base or the exact candidate; production must not be rolled back.');
  return current;
 };
 const previous=await production();
 const candidate=(await github.rest.git.getCommit({owner,repo,commit_sha:sha})).data;
 if(candidate.sha!==sha||candidate.tree?.sha!==INITIAL_MFA.tree||candidate.parents?.length!==1||candidate.parents[0].sha!==INITIAL_MFA.base)throw Error('Initial MFA candidate parent or tree differs from the reviewed snapshot.');
 const comparison=(await github.rest.repos.compareCommitsWithBasehead({owner,repo,basehead:INITIAL_MFA.base+'...'+sha})).data;
 if(comparison.status!=='ahead'||comparison.ahead_by!==1||comparison.behind_by!==0||comparison.total_commits!==1||comparison.commits?.length!==1||comparison.commits[0].sha!==sha)throw Error('Initial MFA candidate must be the single reviewed commit after production.');
 const files=comparison.files||[];
 if(files.length!==Object.keys(INITIAL_MFA.files).length||new Set(files.map(file=>file.filename)).size!==files.length||files.some(file=>
  INITIAL_MFA.files[file.filename]!==file.sha||file.status!==(file.filename==='tests/environment-mfa.test.cjs'?'added':'modified')
 ))throw Error('Initial MFA changed paths or blobs differ from the seven reviewed files.');
 const tested=(await github.rest.git.getCommit({owner,repo,commit_sha:INITIAL_MFA.testedMerge})).data;
 if(tested.sha!==INITIAL_MFA.testedMerge||tested.tree?.sha!==INITIAL_MFA.tree||tested.parents?.length!==2||tested.parents[0].sha!==INITIAL_MFA.base||tested.parents[1].sha!==sha)throw Error('The tested pull-request merge does not contain the exact MFA tree.');
 const pull=(await github.rest.pulls.get({owner,repo,pull_number:INITIAL_MFA.pull})).data;
 if(pull.number!==INITIAL_MFA.pull||pull.head?.sha!==sha||pull.head?.ref!==INITIAL_MFA.branch||pull.head?.repo?.full_name!==repository||pull.base?.ref!=='production'||pull.base?.repo?.full_name!==repository)throw Error('The initial MFA pull request no longer identifies the reviewed same-repository candidate.');
 for(const [runId,workflow,jobs] of [[INITIAL_MFA.releaseRun,'validate-release.yml',RELEASE_JOBS],[INITIAL_MFA.pagesRun,'deploy-coco-pages.yml',PAGES_JOBS]]){
  const run=(await github.rest.actions.getWorkflowRun({owner,repo,run_id:runId})).data;
  if(run.id!==runId||run.run_attempt!==INITIAL_MFA.attempt||run.status!=='completed'||run.conclusion!=='success'||run.event!=='pull_request'||run.head_sha!==sha||run.head_commit?.id!==sha||run.head_branch!==INITIAL_MFA.branch||run.repository?.full_name!==repository||run.head_repository?.full_name!==repository||run.path!=='.github/workflows/'+workflow||!run.pull_requests?.some(pr=>pr.number===INITIAL_MFA.pull&&pr.head?.sha===sha&&pr.head?.ref===INITIAL_MFA.branch&&pr.base?.sha===INITIAL_MFA.base&&pr.base?.ref==='production'))throw Error('The fixed initial MFA validation run is missing, unsuccessful or bound to another source.');
  const completed=await github.paginate(github.rest.actions.listJobsForWorkflowRun,{owner,repo,run_id:runId,filter:'latest',per_page:100});
  if(!jobs.every(name=>completed.some(job=>job.name===name&&job.status==='completed'&&job.conclusion==='success')))throw Error('Every existing initial MFA release and Pages validation gate must pass.');
 }
 const tagRef='tags/'+VERSION_TAG;
 const assertTag=object=>{
  if(object&&(object.type!=='commit'||object.sha!==sha))throw Error('The immutable initial MFA version tag conflicts with the approved candidate.');
 };
 let tag=await getRef(tagRef);assertTag(tag);
 await production();
 // GitHub cannot transact two refs. Create the immutable receipt first; a
 // failed ref update leaves a safe receipt that an exact approved retry reuses.
 if(!tag){
  try{await github.rest.git.createRef({owner,repo,ref:'refs/'+tagRef,sha});}
  catch(error){if(error.status!==422)throw error;tag=await getRef(tagRef);assertTag(tag);if(!tag)throw error;}
 }
 const beforeUpdate=await production();
 if(beforeUpdate!==sha)await github.rest.git.updateRef({owner,repo,ref:'heads/production',sha,force:false});
 if(await production()!==sha)throw Error('Production advanced after promotion; leave the newer ref untouched and inspect it before retrying.');
 await core.summary.addHeading('Initial MFA production code approved').addTable([
  [{data:'Field',header:true},{data:'Value',header:true}],
  ['Approved by',context.actor],['Production commit',sha],['Previous commit',previous],['Immutable version',VERSION_TAG],['Database records copied','0']
 ]).write();
 await github.rest.actions.createWorkflowDispatch({owner,repo,workflow_id:'deploy-coco-pages.yml',ref:'development'});
 return {sha,previous,tag:VERSION_TAG,alreadyPromoted:beforeUpdate===sha};
}
module.exports={INITIAL_MFA,VERSION_TAG,promoteInitialMfa};
