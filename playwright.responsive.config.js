const {defineConfig,devices}=require('@playwright/test');
const base=require('./playwright.config');
module.exports=defineConfig({...base,
 // WebKit upgrades HTTP fixture scripts under the production CSP. Match the
 // deployed HTTPS origin; allow only this ephemeral fixture's self-signed cert.
 use:{...base.use,baseURL:'https://127.0.0.1:4175',ignoreHTTPSErrors:true},
 webServer:{...base.webServer,command:'python3 scripts/serve-test-https.py --port 4175',url:'https://127.0.0.1:4175/index.html',ignoreHTTPSErrors:true,reuseExistingServer:false},
 testMatch:'**/responsive-layout.spec.js',projects:[
 ...base.projects.map(p=>({...p,use:{...p.use,locale:'fr-FR'}})),
 {name:'webkit',use:{...devices['Desktop Safari'],locale:'fr-FR'}}
]});
