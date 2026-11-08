const fs=require('node:fs');
function compareReleaseComponents(manifests,observed){
 const gaps=[];
 for(const manifest of manifests){
  if(!manifest||manifest.schema_version!==1||!/^[a-f0-9]{40}$/.test(manifest.source_commit||''))throw Error('RELEASE_MANIFEST_INVALID');
  if(manifest.source_dirty)gaps.push(manifest.component+': source checkout was dirty at build time');
  const hosted=observed?.web?.[manifest.component];
  if(!hosted||hosted.source_commit!==manifest.source_commit||hosted.observed!==true)gaps.push(manifest.component+': hosted source revision not observed or differs');
  for(const fn of manifest.components.edge_functions){
   const deployed=observed?.edge_functions?.find(entry=>entry.name===fn.name);
   if(!deployed||deployed.observed!==true||!Number.isInteger(deployed.version)||deployed.version<1||deployed.source_sha256!==fn.source_sha256)gaps.push('edge/'+fn.name+': deployed source/version not observed or differs');
  }
  for(const migration of manifest.components.migrations){
   const applied=observed?.migrations?.find(entry=>entry.file===migration.file);
   if(!applied||applied.observed!==true||applied.sha256!==migration.sha256)gaps.push('migration/'+migration.file+': applied source fingerprint not observed or differs');
  }
  if(!observed?.sri||observed.sri.observed!==true||observed.sri.source_sha256!==manifest.components.sri_source_sha256)gaps.push('sri: private service source fingerprint not observed or differs');
 }
 return [...new Set(gaps)];
}
if(require.main===module){
 const args=process.argv.slice(2);
 if(args.length<2)throw Error('Usage: node scripts/check-release-alignment.cjs <observations.json> <release-manifest.json> [more-manifests.json]');
 const observed=JSON.parse(fs.readFileSync(args[0],'utf8')),manifests=args.slice(1).map(file=>JSON.parse(fs.readFileSync(file,'utf8')));
 const gaps=compareReleaseComponents(manifests,observed);
 console.log(JSON.stringify({aligned:gaps.length===0,gaps},null,2));if(gaps.length)process.exitCode=1;
}
module.exports={compareReleaseComponents};
