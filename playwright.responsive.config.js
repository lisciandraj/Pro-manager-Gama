const {defineConfig,devices}=require('@playwright/test');
const base=require('./playwright.config');
module.exports=defineConfig({...base,testMatch:'**/responsive-layout.spec.js',projects:[
 ...base.projects.map(p=>({...p,use:{...p.use,locale:'fr-FR'}})),
 {name:'webkit',use:{...devices['Desktop Safari'],locale:'fr-FR'}}
]});
