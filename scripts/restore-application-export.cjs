/* Isolated application-data recovery drill. No production connection or writes.
   Auth/Storage services must additionally be recovered using their managed backups. */
const fs=require('node:fs'),{createHash}=require('node:crypto'),{restore}=require('./restore-schema.cjs');
const hash=data=>createHash('sha256').update(data).digest('hex');
const ident=s=>'"'+String(s).replace(/"/g,'""')+'"';
function verify(envelope){
 if(envelope.format!=='architect-verified-export'||typeof envelope.payload!=='string'||hash(envelope.payload)!==envelope.sha256)throw Error('EXPORT_CHECKSUM_MISMATCH');
 const data=JSON.parse(envelope.payload);if(data.format!=='architect-application-export'||data.version!==1)throw Error('INVALID_EXPORT');
 for(const [name,rows] of Object.entries(data.tables))if(!Array.isArray(rows)||rows.length!==data.counts[name])throw Error('TABLE_COUNT_MISMATCH: '+name);
 if(data.files.length!==data.storage_objects.length)throw Error('FILES_MISSING');
 const paths=new Set();for(const file of data.files){const path=file.bucket+'/'+file.path;if(paths.has(path)||!data.storage_objects.some(o=>o.bucket===file.bucket&&o.path===file.path))throw Error('FILE_MANIFEST_MISMATCH');paths.add(path);const bytes=Buffer.from(file.base64,'base64');if(bytes.length!==file.bytes||hash(bytes)!==file.sha256)throw Error('FILE_HASH_MISMATCH');}
 return data;
}
async function drill(envelope){const started=Date.now(),data=verify(envelope),db=await restore();try{
 const meta=(await db.query("select table_schema,table_name,column_name,is_generated from information_schema.columns where table_schema in ('public','private') and table_name in (select table_name from information_schema.tables where table_type='BASE TABLE' and table_schema in ('public','private')) order by table_schema,table_name,ordinal_position")).rows;
 const tables=new Map();for(const c of meta){const key=c.table_schema+'.'+c.table_name;if(!tables.has(key))tables.set(key,[]);if(c.is_generated==='NEVER')tables.get(key).push(c.column_name);}
 for(const name of Object.keys(data.tables))if(!tables.has(name))throw Error('UNKNOWN_TABLE: '+name);
 for(const name of tables.keys())if(!Object.hasOwn(data.tables,name))throw Error('MISSING_TABLE: '+name);
 await db.exec("begin;set local session_replication_role='replica';");
 for(const name of tables.keys())await db.exec('delete from '+name.split('.').map(ident).join('.'));
 // Isolated Auth identities preserve FKs only; this does not restore sign-in.
 for(const u of data.identities)await db.query('insert into auth.users(id,email) values($1,$2) on conflict(id) do update set email=excluded.email',[u.id,u.email]);
 for(const [name,cols] of tables){const table=name.split('.').map(ident).join('.');if(data.tables[name].length)await db.query(`insert into ${table}(${cols.map(ident).join(',')}) overriding system value select ${cols.map(c=>'r.'+ident(c)).join(',')} from jsonb_populate_recordset(null::${table},$1) r`,[JSON.stringify(data.tables[name])]);}
 await db.exec("set local session_replication_role='origin';");
 const fks=(await db.query("select c.conname,c.conrelid::regclass::text child,c.confrelid::regclass::text parent,array(select a.attname from unnest(c.conkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num order by k.ord) children,array(select a.attname from unnest(c.confkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.num order by k.ord) parents from pg_constraint c join pg_namespace n on n.oid=c.connamespace where c.contype='f' and n.nspname in ('public','private')")).rows;
 for(const fk of fks){const nonnull=fk.children.map(c=>'c.'+ident(c)+' is not null').join(' and '),join=fk.children.map((c,i)=>'c.'+ident(c)+'=p.'+ident(fk.parents[i])).join(' and ');if((await db.query(`select exists(select 1 from ${fk.child} c where ${nonnull} and not exists(select 1 from ${fk.parent} p where ${join})) invalid`)).rows[0].invalid)throw Error('BROKEN_RELATION: '+fk.conname);}
 let rows=0;for(const name of tables.keys()){const count=Number((await db.query('select count(*) n from '+name.split('.').map(ident).join('.'))).rows[0].n);if(count!==data.counts[name])throw Error('RESTORED_COUNT_MISMATCH: '+name);rows+=count;}
 // Identity/serial counters are rebuilt from the restored values, not the new instance's seed.
 const sequences=(await db.query("select table_schema,table_name,column_name,pg_get_serial_sequence(format('%I.%I',table_schema,table_name),column_name) seq from information_schema.columns where table_schema in ('public','private') and (is_identity='YES' or column_default like 'nextval(%')")).rows;
 for(const s of sequences)if(s.seq){const max=(await db.query(`select max(${ident(s.column_name)})::bigint n from ${ident(s.table_schema)}.${ident(s.table_name)}`)).rows[0].n;await db.query('select setval($1::regclass,$2::bigint,$3)',[s.seq,Math.max(1,Number(max||0)),max!=null]);}
 await db.exec('commit');return {success:true,tables:tables.size,rows,relations:fks.length,files:data.files.length,milliseconds:Date.now()-started,scope:'Isolated application data, checksums and relations. Managed Auth and Storage services are not exercised.'};
 }finally{await db.close()}}
module.exports={verify,drill,hash};
if(require.main===module){if(!process.argv[2]){console.error('Usage: node scripts/restore-application-export.cjs export.json');process.exitCode=1}else drill(JSON.parse(fs.readFileSync(process.argv[2],'utf8'))).then(r=>console.log(JSON.stringify(r,null,2))).catch(e=>{console.error(e.message);process.exitCode=1})}
