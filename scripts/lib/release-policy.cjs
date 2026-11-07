const REQUIRED_RELEASE_JOBS=Object.freeze(['build','topbar-menus','business-modules','release-validation','secret-scan']);
function authorizePromotion({event,ref,commit,artifactCommit,checks}){
 if(!['push','workflow_dispatch'].includes(event)||ref!=='refs/heads/main')throw Error('RELEASE_MAIN_ONLY');
 if(!/^[a-f0-9]{40}$/.test(commit||'')||artifactCommit!==commit)throw Error('RELEASE_REVISION_MISMATCH');
 for(const job of REQUIRED_RELEASE_JOBS)if(checks?.[job]?.result!=='success')throw Error('RELEASE_CHECK_REQUIRED:'+job);
 return true;
}
module.exports={REQUIRED_RELEASE_JOBS,authorizePromotion};
