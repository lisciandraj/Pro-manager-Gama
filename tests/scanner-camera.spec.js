const {test,expect}=require('@playwright/test');
async function boot(page,mode='ok'){
 await page.route('**/scanner-test',r=>r.fulfill({contentType:'text/html',body:'<meta charset="utf-8"><input id="scanTarget"><button id="open">Scan</button>'}));await page.goto('/scanner-test');
 await page.evaluate(mode=>{
 window.__mode=mode;window.__stops=0;window.__requests=0;window.__plays=0;window.__pending=[];window.__detected=[];
 const make=()=>({getTracks:()=>[{stop:()=>window.__stops++}]});
 Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{__requests++;if(__mode==='denied')throw new DOMException('denied','NotAllowedError');if(__mode==='pending')return new Promise(resolve=>__pending.push(()=>resolve(make())));return make()}}});
 Object.defineProperty(HTMLMediaElement.prototype,'srcObject',{configurable:true,set(v){this.__src=v},get(){return this.__src}});
 HTMLMediaElement.prototype.play=async function(){__plays++;if(__mode==='play-blocked')throw new DOMException('play denied','NotAllowedError')};HTMLMediaElement.prototype.pause=function(){};
 Object.defineProperty(HTMLMediaElement.prototype,'readyState',{configurable:true,get:()=>4});
 window.BarcodeDetector=class{static async getSupportedFormats(){return ['ean_13']}async detect(){return __detected}};
 },mode);
 await page.addScriptTag({url:'/gama-scanner-phone.js'});await page.evaluate(()=>document.querySelector('#open').onclick=()=>startGamaScan('scanTarget'));
}
test('denied permission shows recovery and retry opens camera',async({page})=>{
 await boot(page,'denied');await page.click('#open');await expect(page.locator('.status')).toContainText('no permite');await expect(page.locator('.help')).toBeVisible();
 await page.evaluate(()=>__mode='ok');await page.click('.retry');await expect(page.locator('.status')).toContainText('Apunte');expect(await page.evaluate(()=>__requests)).toBe(2);
 await page.click('.close');expect(await page.evaluate(()=>__stops)).toBe(1);
});
test('blocked playback uses authorized stream on user retry',async({page})=>{
 await boot(page,'play-blocked');await page.click('#open');await expect(page.locator('.status')).toContainText('Cámara autorizada');await expect(page.locator('.help')).toBeHidden();
 await page.evaluate(()=>__mode='ok');await page.getByRole('button',{name:'Iniciar vídeo'}).click();await expect(page.locator('.status')).toContainText('Apunte');expect(await page.evaluate(()=>__requests)).toBe(1);
});
test('closed camera request cannot leak a stream or affect a new session',async({page})=>{
 await boot(page,'pending');await page.click('#open');await page.click('.close');await page.click('#open');await page.evaluate(()=>__pending[0]());expect(await page.evaluate(()=>__stops)).toBe(1);
 await expect(page.locator('.status')).toContainText('Activando');await page.evaluate(()=>__pending[1]());await expect(page.locator('.status')).toContainText('Apunte');await page.click('.close');expect(await page.evaluate(()=>__stops)).toBe(2);
});
test('scan fills target once and releases camera; manual entry remains accessible',async({page})=>{
 await boot(page);await page.evaluate(()=>document.querySelector('#scanTarget').addEventListener('gama:barcode-scanned',()=>window.__scans=(window.__scans||0)+1));await page.click('#open');await page.evaluate(()=>__detected=[{rawValue:'0012345678905'}]);await expect(page.locator('#scanTarget')).toHaveValue('0012345678905');await expect(page.locator('#gamaPhoneScanner')).toHaveCount(0);expect(await page.evaluate(()=>__scans)).toBe(1);expect(await page.evaluate(()=>__stops)).toBe(1);
 await page.evaluate(()=>__detected=[]);await page.click('#open');await page.click('.manual');await expect(page.locator('#scanTarget')).toBeFocused();
});
