const {test,expect,chromium}=require('@playwright/test');
const fs=require('fs'),path=require('path');
test('full production page starts browser camera without replacing getUserMedia',async()=>{
 const browser=await chromium.launch({executablePath:process.env.PLAYWRIGHT_CHROMIUM_PATH,args:['--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream']});
 try{
 const context=await browser.newContext();const page=await context.newPage();
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8')}));
 await page.goto('http://127.0.0.1:4173/index.html');
 await page.evaluate(()=>{window.BarcodeDetector=class{static async getSupportedFormats(){return ['ean_13']}async detect(){return []}};const button=document.createElement('button');button.id='cameraRealTest';button.textContent='Camera';button.onclick=()=>startGamaScan('pBarcode');document.body.append(button)});
 await page.click('#cameraRealTest');await expect(page.locator('#gamaPhoneScanner .status')).toContainText('Apunte');
 const info=await page.locator('#gamaPhoneScanner video').evaluate(v=>({width:v.videoWidth,ready:v.readyState,tracks:v.srcObject.getVideoTracks().map(t=>t.readyState)}));expect(info.width).toBeGreaterThan(0);expect(info.tracks).toEqual(['live']);
 await page.locator('#gamaPhoneScanner .close').click();
 await page.goto('http://127.0.0.1:4173/camera-check.html');await page.click('#default');await expect(page.locator('#status')).toHaveText('Cámara funcionando.');await page.click('#stop');await page.click('#rear');await expect(page.locator('#status')).toHaveText('Cámara funcionando.');await expect(page.locator('#report')).toContainText('Acceso concedido');
 }finally{await browser.close()}
});
