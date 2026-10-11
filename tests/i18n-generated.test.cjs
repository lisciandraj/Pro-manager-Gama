const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
test('language bundles preserve every source key and the selected reviewed translation',()=>{
 const all={window:{}};vm.runInNewContext(fs.readFileSync('gama-i18n-catalog.js','utf8'),all);
 const context={window:{}};
 for(const [code,index]of [['fr',1],['en',2]]){
  vm.runInNewContext(fs.readFileSync('gama-i18n-'+code+'.js','utf8'),context);const translated=context.window.GamaI18nCatalogues[code];
  assert.deepEqual(Object.keys(translated).sort(),Object.keys(all.window.GamaI18nCatalog).sort());
  for(const [key,row]of Object.entries(all.window.GamaI18nCatalog)){assert.equal(translated[key][0],row[0]);assert.equal(translated[key][index],row[index]);}
 }
 assert.equal(context.window.GamaI18nCatalogues.fr!=null,true);assert.equal(context.window.GamaI18nCatalogues.en!=null,true);
});
