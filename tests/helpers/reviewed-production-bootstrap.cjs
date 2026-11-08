// The production bootstrap is deliberately frozen at its separately reviewed
// source set. Exercise the real compilers against that immutable migration
// inventory, while testing current development additions fail closed separately.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),{createRequire}=require('node:module'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),directory=path.join(root,'supabase/migrations'),last='20261107195941_coco_environment_isolation.sql';
const reviewed=fs.readdirSync(directory).filter(f=>/^\d{14}_[a-z0-9_]+\.sql$/.test(f)&&f<=last).sort();
assert.equal(reviewed.length,362,'Changing the reviewed production source set requires its own review');assert.equal(reviewed.at(-1),last);
const snapshotFs={...fs,readdirSync:(dir,...options)=>path.resolve(dir)===directory?[...reviewed]:fs.readdirSync(dir,...options)};
function compiler(file){
 const filename=path.join(root,'scripts',file),localRequire=createRequire(filename),module={exports:{}};
 const entry=vm.runInThisContext('(function(exports,require,module,__filename,__dirname){\n'+fs.readFileSync(filename,'utf8')+'\n})',{filename});
 entry(module.exports,name=>name==='node:fs'?snapshotFs:localRequire(name),module,filename,path.dirname(filename));return module.exports.prepare;
}
module.exports={prepare:compiler('prepare-production-verification.cjs'),prepareBootstrap:compiler('bootstrap-production.cjs'),reviewedCount:reviewed.length,last};
