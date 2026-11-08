/* Immutable first-installation boundary. Later application migrations belong to
 * separate reviewed releases; they must never alter the prepared installation.
 */
const fs=require('node:fs'),path=require('node:path');
const {productionMigration,digest}=require('./production-bootstrap-sql.cjs');
const sourceCount=362,lastFile='20261107195941_coco_environment_isolation.sql';
const installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e';
function loadSnapshot(directory){
 const files=fs.readdirSync(directory).filter(file=>/^\d{14}_[a-z0-9_]+\.sql$/.test(file)).sort();
 const initial=files.filter(file=>file<=lastFile),excluded=files.filter(file=>file>lastFile);
 if(initial.length!==sourceCount||initial.at(-1)!==lastFile)throw Error('First-installation snapshot source count changed; review the historical snapshot');
 const originals=initial.map(file=>{const original=fs.readFileSync(path.join(directory,file),'utf8');return {file,original,sha256:digest(original)};});
 if(digest(originals.map(source=>source.file+':'+source.sha256).join('\n'))!==installation)throw Error('Historical production bootstrap snapshot changed');
 const sources=originals.map(({file,original,sha256})=>{const sql=productionMigration(file,original);return {file,sha256,derived_sha256:digest(sql),sql};});
 return {sources,excluded};
}
module.exports={loadSnapshot,sourceCount,lastFile,installation};
