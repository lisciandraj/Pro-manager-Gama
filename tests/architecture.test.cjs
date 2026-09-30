const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {root,manifest,runtimeFiles,header,validateManifest}=require('../scripts/lib/assets.cjs');
test('runtime copies match their named canonical sources',()=>{
 validateManifest();for(const item of [...manifest.scripts,...manifest.styles])assert.equal(fs.readFileSync(path.join(root,item.output),'utf8'),header(item.source)+fs.readFileSync(path.join(root,item.source),'utf8'),item.output);
});
test('HTML boot and deployment do not include test configuration or obsolete preload',()=>{
 const html=fs.readFileSync('index.html','utf8');
 assert.ok(!html.includes('https://cdn.jsdelivr.net/npm/@supabase/supabase-js'));
 assert.ok(!/<script>([\s\S]*?)<\/script>/.test(html));
 for(const file of ['playwright.config.js','playwright.responsive.config.js'])assert.ok(!runtimeFiles().includes(file));
 for(const file of ['gama-knowledge.js','gama-assistant-ia.js','gama-role-spanish.js'])assert.ok(!html.includes('<script src="'+file));
});
