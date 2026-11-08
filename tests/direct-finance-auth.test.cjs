const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
for(const [file,globalName,method]of [['direct-invoices.js','CocoDirectInvoices','detail'],['direct-refunds.js','CocoDirectRefunds','open'],['invoice-checkout.js','CocoInvoiceCheckout','open']])test(file+' cannot open a previous session invoice after its pending read resolves',async()=>{
 const listeners={},pending=[];let dialogs=0;const window={ArcUI:{esc:String,dialog:()=>{dialogs++;throw Error('STALE_DIALOG')}},ArcData:{rpc:()=>new Promise(resolve=>pending.push(resolve))},ArcFormat:{money:String},GamaI18n:{language:'en'},addEventListener:(name,handler)=>{listeners[name]=handler}};
 vm.runInNewContext(fs.readFileSync('src/features/finance/'+file,'utf8'),{window,Intl,Set,Map,Date,Error,Object,Number,String});
 const result=window[globalName][method](file==='invoice-checkout.js'?{id:'old-invoice'}:'old-invoice');listeners['gama:auth-change']({detail:{event:'SIGNED_OUT'}});pending.forEach(resolve=>resolve({invitations:[],can_configure:false}));
 if(file==='invoice-checkout.js')assert.equal(await result,undefined);else await assert.rejects(result,/AUTH_CHANGED/);assert.equal(dialogs,0);
});
