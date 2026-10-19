// Optional local test preload: run the existing public/B2B fixtures against
// the audit proposal, without altering production migration history.
const fs=require('node:fs'),path=require('node:path');
const schema=require('../../scripts/restore-schema.cjs'),restore=schema.restore;
const sql=fs.readFileSync(path.join(__dirname,'../../docs/audits/proposals/coco-storefront-projection.sql'),'utf8');
schema.restore=async options=>{
 const db=await restore(options);
 try{if(!(await db.query("select to_regclass('private.gama_storefront_projection') existing")).rows[0].existing)await db.exec(sql);return db}catch(error){await db.close();throw error}
};
