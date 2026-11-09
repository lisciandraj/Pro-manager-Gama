/* Isolated scoped business-data recovery drill. No production connection/writes.
   Full Auth/Storage/runtime recovery uses the encrypted infrastructure backups. */
const fs=require('node:fs'),{createHash,pbkdf2Sync,createDecipheriv}=require('node:crypto'),{restore}=require('./restore-schema.cjs');
const hash=data=>createHash('sha256').update(data).digest('hex');
const ident=s=>'"'+String(s).replace(/"/g,'""')+'"';
const ENCRYPTED='architect-encrypted-export',ITERATIONS=600000,MAX_BYTES=128*1024*1024;
const bytes=(value,{size,max=MAX_BYTES}={})=>{if(typeof value!=='string'||value.length>Math.ceil(max/3)*4||value.length%4!==0)throw Error('INVALID_EXPORT_ENCODING');const padding=value.endsWith('==')?2:value.endsWith('=')?1:0;if(/[^A-Za-z0-9+/]/.test(value.slice(0,value.length-padding)))throw Error('INVALID_EXPORT_ENCODING');const result=Buffer.from(value,'base64');if(result.length>max||(size!==undefined&&result.length!==size))throw Error('INVALID_EXPORT_ENCODING');return result};
function decryptEnvelope(envelope,passphrase){
 if(envelope.format!==ENCRYPTED)return envelope;
 if(envelope.version!==1||envelope.algorithm!=='AES-GCM'||envelope.kdf?.name!=='PBKDF2'||envelope.kdf.hash!=='SHA-256'||envelope.kdf.iterations!==ITERATIONS)throw Error('INVALID_EXPORT_ENCRYPTION');
 if(typeof passphrase!=='string'||passphrase.length<12||passphrase.length>1024)throw Error('EXPORT_PASSPHRASE_REQUIRED');
 const salt=bytes(envelope.kdf.salt,{size:16,max:16}),iv=bytes(envelope.iv,{size:12,max:12}),ciphertext=bytes(envelope.ciphertext);if(ciphertext.length<16)throw Error('INVALID_EXPORT_ENCRYPTION');
 const key=pbkdf2Sync(passphrase,salt,ITERATIONS,32,'sha256');try{const decipher=createDecipheriv('aes-256-gcm',key,iv);decipher.setAAD(Buffer.from(ENCRYPTED+':1'));decipher.setAuthTag(ciphertext.subarray(-16));const value=Buffer.concat([decipher.update(ciphertext.subarray(0,-16)),decipher.final()]);return JSON.parse(value.toString('utf8'));}catch{throw Error('EXPORT_DECRYPTION_FAILED')}finally{key.fill(0)}
}
function verify(envelope,{passphrase}={}){
 envelope=decryptEnvelope(envelope,passphrase);
 if(envelope.format!=='architect-verified-export'||typeof envelope.payload!=='string'||envelope.payload.length>MAX_BYTES||hash(envelope.payload)!==envelope.sha256)throw Error('EXPORT_CHECKSUM_MISMATCH');
 const data=JSON.parse(envelope.payload);if(data.format!=='architect-application-export'||data.version!==1||!data.tables||!data.counts||!data.columns)throw Error('INVALID_EXPORT');
 for(const [name,rows] of Object.entries(data.tables))if(!Array.isArray(rows)||rows.length!==data.counts[name])throw Error('TABLE_COUNT_MISMATCH: '+name);
 if(data.scope==='business_data_and_files'){
  const c=data.coverage;if(c?.mode!=='business-allowlist'||c.full_backup!==false||!Array.isArray(c.tables)||new Set(c.tables).size!==c.tables.length||JSON.stringify([...c.tables].sort())!==JSON.stringify(Object.keys(data.tables).sort())||!Array.isArray(c.excluded_tables)||!c.excluded_columns)throw Error('INVALID_EXPORT_COVERAGE');
  for(const name of c.excluded_tables)if(Object.hasOwn(data.tables,name))throw Error('EXCLUDED_TABLE_PRESENT: '+name);
  if(!c.redacted_json_fields||typeof c.redacted_json_fields!=='object'||Array.isArray(c.redacted_json_fields))throw Error('INVALID_EXPORT_COVERAGE');
  for(const [path,fields] of Object.entries(c.redacted_json_fields)){
   const parts=path.split('.');if(parts.length!==3||!Array.isArray(fields))throw Error('INVALID_EXPORT_COVERAGE');
   for(const row of data.tables[parts.slice(0,2).join('.')]||[])for(const field of fields)if(row[parts[2]]&&Object.hasOwn(row[parts[2]],field))throw Error('EXPORT_REDACTED_FIELD_PRESENT: '+path);
  }

 }else if(data.scope!=='application_data_and_files')throw Error('INVALID_EXPORT_SCOPE');
 if(!Array.isArray(data.files)||!Array.isArray(data.storage_objects)||data.files.length!==data.storage_objects.length)throw Error('FILES_MISSING');
 const paths=new Set();for(const file of data.files){const path=file.bucket+'/'+file.path;if(paths.has(path)||!data.storage_objects.some(o=>o.bucket===file.bucket&&o.path===file.path))throw Error('FILE_MANIFEST_MISMATCH');paths.add(path);const content=bytes(file.base64);if(content.length!==file.bytes||hash(content)!==file.sha256)throw Error('FILE_HASH_MISMATCH');}
 return data;
}
async function drill(envelope,options={}){const started=Date.now(),data=verify(envelope,options);if(data.scope!=='business_data_and_files')throw Error('LEGACY_EXPORT_READ_ONLY');const db=await restore();try{
 const allowed=(await db.query('select private.recovery_business_export_columns() policy')).rows[0].policy;
 const meta=(await db.query("select table_schema,table_name,column_name,is_generated from information_schema.columns where table_schema in ('public','private') and table_name in (select table_name from information_schema.tables where table_type='BASE TABLE' and table_schema in ('public','private')) order by table_schema,table_name,ordinal_position")).rows;
 const schemaTables=new Map();for(const c of meta){const key=c.table_schema+'.'+c.table_name;if(!schemaTables.has(key))schemaTables.set(key,[]);if(c.is_generated==='NEVER')schemaTables.get(key).push(c.column_name);}
 const expected=Object.keys(allowed).filter(name=>schemaTables.has(name)).sort();
 const currentPolicyHash=(await db.query("select md5(jsonb_build_object('columns',private.recovery_business_export_columns(),'redactions',private.recovery_business_export_redactions())::text) h")).rows[0].h;
 if(data.coverage.policy_hash!==currentPolicyHash||JSON.stringify(Object.keys(data.tables).sort())!==JSON.stringify(expected))throw Error('EXPORT_POLICY_CHANGED');
 const tables=new Map();for(const name of Object.keys(data.tables)){
  if(!schemaTables.has(name)||!Object.hasOwn(allowed,name))throw Error('EXPORT_RESOURCE_NOT_ALLOWED: '+name);
  const declared=data.columns[name]?.map(c=>c.name);if(!Array.isArray(declared)||!declared.length||new Set(declared).size!==declared.length||declared.some(c=>!allowed[name].includes(c)))throw Error('EXPORT_COLUMN_NOT_ALLOWED: '+name);
  const cols=declared.filter(c=>schemaTables.get(name).includes(c));if(!cols.length)throw Error('EXPORT_SCHEMA_CHANGED: '+name);
  for(const row of data.tables[name])if(!row||typeof row!=='object'||Array.isArray(row)||Object.keys(row).some(c=>!declared.includes(c)))throw Error('EXPORT_COLUMN_NOT_ALLOWED: '+name);
  tables.set(name,cols);
 }
 // Only this explicit business scope is replaced. Secrets and infrastructure
 // remain the fresh instance's configuration, never empty/forged export rows.
 await db.exec("begin;set local session_replication_role='replica';");
 for(const name of tables.keys())await db.exec('delete from '+name.split('.').map(ident).join('.'));
 // Isolated Auth IDs preserve FKs only; no passwords, factors or sessions restored.
 for(const u of data.identities)await db.query('insert into auth.users(id,email) values($1,$2) on conflict(id) do update set email=excluded.email',[u.id,u.email]);
 for(const [name,cols] of tables){const table=name.split('.').map(ident).join('.');if(data.tables[name].length)await db.query(`insert into ${table}(${cols.map(ident).join(',')}) overriding system value select ${cols.map(c=>'r.'+ident(c)).join(',')} from jsonb_populate_recordset(null::${table},$1) r`,[JSON.stringify(data.tables[name])]);}
 await db.exec("set local session_replication_role='origin';");
 const fks=(await db.query("select c.conname,c.conrelid::regclass::text child,c.confrelid::regclass::text parent,array(select a.attname from unnest(c.conkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num order by k.ord) children,array(select a.attname from unnest(c.confkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.num order by k.ord) parents from pg_constraint c join pg_namespace n on n.oid=c.connamespace where c.contype='f' and n.nspname in ('public','private')")).rows;
 for(const fk of fks){const nonnull=fk.children.map(c=>'c.'+ident(c)+' is not null').join(' and '),join=fk.children.map((c,i)=>'c.'+ident(c)+'=p.'+ident(fk.parents[i])).join(' and ');if((await db.query(`select exists(select 1 from ${fk.child} c where ${nonnull} and not exists(select 1 from ${fk.parent} p where ${join})) invalid`)).rows[0].invalid)throw Error('BROKEN_RELATION: '+fk.conname);}
 let rows=0;for(const name of tables.keys()){const count=Number((await db.query('select count(*) n from '+name.split('.').map(ident).join('.'))).rows[0].n);if(count!==data.counts[name])throw Error('RESTORED_COUNT_MISMATCH: '+name);rows+=count;}
 // Only serial/identity columns in the restored scope are rebuilt.
 const sequences=(await db.query("select table_schema,table_name,column_name,pg_get_serial_sequence(format('%I.%I',table_schema,table_name),column_name) seq from information_schema.columns where table_schema in ('public','private') and (is_identity='YES' or column_default like 'nextval(%')")).rows;
 for(const s of sequences)if(s.seq&&tables.has(s.table_schema+'.'+s.table_name)){const max=(await db.query(`select max(${ident(s.column_name)})::bigint n from ${ident(s.table_schema)}.${ident(s.table_name)}`)).rows[0].n;await db.query('select setval($1::regclass,$2::bigint,$3)',[s.seq,Math.max(1,Number(max||0)),max!=null]);}
 // Optional trusted fixture inspection runs only against this disposable local DB.
 if(typeof options.onRestored==='function')await options.onRestored(db);
 await db.exec('commit');return {success:true,tables:tables.size,rows,relations:fks.length,files:data.files.length,milliseconds:Date.now()-started,scope:'Isolated scoped business data, checksums and relations. Excluded credentials/runtime state, managed Auth and Storage services are not recovered.'};
 }finally{await db.close()}}
module.exports={verify,drill,hash,decryptEnvelope};
if(require.main===module){if(!process.argv[2]){console.error('Usage: node scripts/restore-application-export.cjs export.json [--passphrase-stdin]');process.exitCode=1}else{const passphrase=process.argv.includes('--passphrase-stdin')?fs.readFileSync(0,'utf8').replace(/\r?\n$/,''):undefined;drill(JSON.parse(fs.readFileSync(process.argv[2],'utf8')),{passphrase}).then(r=>console.log(JSON.stringify(r,null,2))).catch(e=>{console.error(e.message);process.exitCode=1})}}
