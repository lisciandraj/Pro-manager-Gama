const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');

test('Contacts SQL archive matches the installed migration fingerprint without executing SQL',()=>{
 const dir=path.join(__dirname,'../supabase/sql/applied');
 const meta=JSON.parse(fs.readFileSync(path.join(dir,'20261015202048_coco_contacts_hub.json'),'utf8'));
 assert.equal(meta.version,'20261015202048');
 assert.equal(meta.file,'20261015202048_coco_contacts_hub.sql');
 const bytes=fs.readFileSync(path.join(dir,meta.file));
 const hash=algorithm=>crypto.createHash(algorithm).update(bytes).digest('hex');
 assert.equal(bytes.length,32518);
 assert.equal(bytes.length,meta.bytes);
 assert.equal([...bytes.toString('utf8')].length,meta.characters);
 assert.equal(bytes.at(-1)===10,meta.terminal_newline);
 assert.equal(hash('md5'),meta.md5);
 assert.equal(hash('sha256'),'7a13117770a7f57932f6e4c1d3dbde342c6c3d7e062175270d218e240dcb6d79');
 assert.equal(hash('sha256'),meta.sha256);
 const gitHash=crypto.createHash('sha1').update(Buffer.from(`blob ${bytes.length}\0`)).update(bytes).digest('hex');
 assert.equal(gitHash,meta.git_blob_sha1);
});
