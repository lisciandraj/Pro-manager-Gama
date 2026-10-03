const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),out=path.join(root,'dist-storefront');
fs.rmSync(out,{recursive:true,force:true});fs.mkdirSync(path.join(out,'fonts'),{recursive:true});
for(const file of ['index.html','site.js','site.css','surveys.html','surveys.js','_headers'])fs.copyFileSync(path.join(root,'src/storefront',file),path.join(out,file));
fs.copyFileSync(path.join(root,'src/features/surveys/survey-form.js'),path.join(out,'survey-form.js'));
fs.copyFileSync(path.join(root,'src/styles/surveys.css'),path.join(out,'surveys.css'));
fs.copyFileSync(path.join(root,'gama-logo.jpg'),path.join(out,'logo.jpg'));
fs.copyFileSync(path.join(root,'fonts/inter-latin-wght-normal.woff2'),path.join(out,'fonts/inter-latin-wght-normal.woff2'));
let html=fs.readFileSync(path.join(out,'index.html'),'utf8');for(const file of ['site.js','site.css']){const v=crypto.createHash('sha256').update(fs.readFileSync(path.join(out,file))).digest('hex').slice(0,12);html=html.replace('/'+file,'/'+file+'?v='+v)}
fs.writeFileSync(path.join(out,'index.html'),html);
let survey=fs.readFileSync(path.join(out,'surveys.html'),'utf8');for(const file of ['surveys.js','surveys.css','survey-form.js']){const hash=crypto.createHash('sha256').update(fs.readFileSync(path.join(out,file))).digest('hex').slice(0,12);survey=survey.replace('/'+file,'/'+file+'?v='+hash)}fs.writeFileSync(path.join(out,'surveys.html'),survey);
fs.writeFileSync(path.join(out,'_routes.json'),JSON.stringify({version:1,include:['/','/index.html','/api/storefront','/api/surveys'],exclude:[]}));
console.log('Public GAMA catalogue built in dist-storefront; Pages Functions supply the Coco connection.');
