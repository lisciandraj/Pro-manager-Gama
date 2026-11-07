const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
const {verify,hash}=require('../scripts/restore-application-export.cjs');
const phrase='Synthetic recovery phrase 2026';
const snapshot=()=>({format:'architect-application-export',version:1,scope:'business_data_and_files',created_at:'2026-11-07T12:00:00Z',tables:{'public.products':[{id:'fixture',name:'Sensitive synthetic customer product'}]},counts:{'public.products':1},columns:{'public.products':[{name:'id'},{name:'name'}]},coverage:{mode:'business-allowlist',full_backup:false,tables:['public.products'],excluded_tables:['private.offline_proof_keys'],excluded_columns:{}},identities:[],storage_objects:[],storage_buckets:[],files:[]});
function harness({rpc}={}){
 const nodes=Object.fromEntries(['backup','recoveryPassphrase','recoveryPassphraseRepeat','recoveryFile','recoveryExport','recoveryExcel','recoveryVerify','recoveryStatus'].map(id=>[id,{id,value:'',dataset:{},files:[],textContent:'',replaceChildren(){this.textContent=''}}]));
 const downloads=[],events={},blobs=new Map();let calls=0;
 const window={GamaI18n:{language:'fr'},ArcRouter:{onEnter(){}},ArcUI:{render(){}},GamaUI:{bindBack(){}},ArcData:{async rpc(){calls++;return rpc?rpc():snapshot()}},GamaCloud:{async db(){return {storage:{from(){throw Error('Fixture has no files')}}}}},ArchitectAccessControls:{async requireAction(){}},ArchitectIdentity:{async withStepUp(action,resource,callback){assert.equal(action,'backup_export');assert.equal(resource,'all');return callback()}},ArcErrors:{message:e=>e.message},addEventListener:(n,cb)=>{events[n]=cb}};
 const document={getElementById:id=>nodes[id],createElement:()=>({click(){downloads.push({name:this.download,blob:blobs.get(this.href)})}})};
 const context={window,document,localStorage:{getItem:()=>JSON.stringify({role:'administrador'})},crypto:webcrypto,TextEncoder,TextDecoder,Uint8Array,JSON,Blob,Date,Error,btoa,atob,URL:{createObjectURL(b){const id='blob:fixture-'+blobs.size;blobs.set(id,b);return id},revokeObjectURL(){}},setTimeout:()=>0};
 vm.runInNewContext(fs.readFileSync('src/features/recovery/recovery.js','utf8'),context);window.GamaRecovery.mount();
 const setPhrase=(value=phrase,repeat=value)=>{nodes.recoveryPassphrase.value=value;nodes.recoveryPassphraseRepeat.value=repeat};
 return {nodes,window,downloads,events,setPhrase,get calls(){return calls}};
}
test('encrypted browser export interoperates with recovery verifier and authenticates ciphertext',async()=>{
 const h=harness();h.setPhrase();await h.window.exportJSONBackup();assert.equal(h.downloads.length,1);assert.match(h.downloads[0].name,/\.encrypted\.json$/);
 const text=await h.downloads[0].blob.text(),encrypted=JSON.parse(text);assert.equal(encrypted.format,'architect-encrypted-export');assert.equal(encrypted.version,1);assert.ok(!text.includes('Sensitive synthetic'));assert.equal(h.nodes.recoveryPassphrase.value,'');assert.equal(h.nodes.recoveryPassphraseRepeat.value,'');
 assert.equal(verify(encrypted,{passphrase:phrase}).tables['public.products'][0].name,'Sensitive synthetic customer product');
 assert.throws(()=>verify(encrypted,{passphrase:'Wrong synthetic phrase'}),/EXPORT_DECRYPTION_FAILED/);
 const changed=Buffer.from(encrypted.ciphertext,'base64');changed[0]^=1;assert.throws(()=>verify({...encrypted,ciphertext:changed.toString('base64')},{passphrase:phrase}),/EXPORT_DECRYPTION_FAILED/);
 assert.throws(()=>verify({...encrypted,kdf:{...encrypted.kdf,iterations:1}},{passphrase:phrase}),/INVALID_EXPORT_ENCRYPTION/);
 h.setPhrase();await h.window.exportJSONBackup();const next=JSON.parse(await h.downloads[1].blob.text());assert.notEqual(next.iv,encrypted.iv);assert.notEqual(next.kdf.salt,encrypted.kdf.salt);
 h.nodes.recoveryFile.files=[{size:text.length,text:async()=>text}];h.setPhrase();await h.nodes.recoveryVerify.onclick();assert.match(h.nodes.recoveryStatus.textContent,/Intégrité vérifiée/);
 h.nodes.recoveryFile.files=[{size:text.length,text:async()=>text}];h.setPhrase('Wrong synthetic phrase');await h.nodes.recoveryVerify.onclick();assert.match(h.nodes.recoveryStatus.textContent,/Phrase incorrecte ou fichier modifié/);
});
test('exports require matching passphrase before fetching data; legacy exports remain read-only verifiable',async()=>{
 const h=harness();h.setPhrase(phrase,'different');await h.window.exportJSONBackup();assert.equal(h.calls,0);assert.equal(h.downloads.length,0);
 const data=snapshot();data.scope='application_data_and_files';delete data.coverage;const payload=JSON.stringify(data),plain=JSON.stringify({format:'architect-verified-export',payload,sha256:hash(payload)});
 h.nodes.recoveryFile.files=[{size:plain.length,text:async()=>plain}];await h.nodes.recoveryVerify.onclick();assert.match(h.nodes.recoveryStatus.textContent,/Intégrité vérifiée/);
});
test('a session change cancels late data and removes the passphrase without downloading',async()=>{
 let resolve;const pending=new Promise(r=>{resolve=r}),h=harness({rpc:()=>pending});h.setPhrase();const exporting=h.window.exportJSONBackup();await new Promise(setImmediate);
 h.events['gama:auth-change']({detail:{event:'SIGNED_OUT'}});resolve(snapshot());await exporting;assert.equal(h.downloads.length,0);assert.equal(h.nodes.recoveryPassphrase.value,'');assert.match(h.nodes.recoveryStatus.textContent,/connexion a changé/);
});
