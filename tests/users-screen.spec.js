// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// The Usuarios table has always had an Email column, but it printed "—" for
// everyone: the address lives in auth.users, which the browser cannot read.
// profiles now carries a mirrored email column, kept in sync by triggers on
// auth.users, and readable only by the account itself or an administrator.
const PROFILES = [
  { id: 'test-admin-uid', full_name: 'Jimmy Lisciandra', email: 'admin@example.com', role: 'administrador', active: true, created_at: '2026-08-25T22:22:22Z' },
  { id: 'u2', full_name: 'Paula Martinez', email: 'paula@example.com', role: 'comercial', active: true, created_at: '2026-08-26T09:00:00Z' },
  { id: 'u3', full_name: 'Teddy Boy', email: 'teddy@example.com', role: 'cliente', active: false, created_at: '2026-09-05T11:43:50Z' },
];

async function openUsers(page, profiles = PROFILES) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Jimmy Lisciandra' }));
    // @ts-ignore
    window.__DB = {
      profiles: seed, products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      fleet_drivers: [], fleet_vehicles: [], fleet_assignments: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    };
    // @ts-ignore
    window.__DB._profile = { id: 'test-admin-uid', full_name: 'Jimmy Lisciandra', email: 'admin@example.com', role: 'administrador', active: true };
  }, profiles);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1200);
  await expect(page.locator('#cuRows tr')).toHaveCount(0);
  await page.locator('#arcSettings').click();
  await page.locator('#cfgTab-users').click();
  await page.waitForSelector('#cuRows tr', { state: 'attached', timeout: 10000 });
  await page.waitForTimeout(400);
}

const row = (page, name) => page.locator('#cuRows tr').filter({ hasText: name });

test.describe('Usuarios — correo asociado', () => {
  test('every account shows its email address next to its status', async ({ page }) => {
    await openUsers(page);

    await expect(row(page, 'Jimmy Lisciandra')).toContainText('admin@example.com');
    await expect(row(page, 'Paula Martinez')).toContainText('paula@example.com');
    await expect(row(page, 'Teddy Boy')).toContainText('teddy@example.com');

    // No row falls back to the placeholder any more.
    expect((await page.locator('#cuRows tr td:nth-child(2)').allTextContents()).every(text=>text!=='—')).toBe(true);
  });

  test('the email sits alongside the active / pending state', async ({ page }) => {
    await openUsers(page);

    await expect(row(page, 'Paula Martinez')).toContainText('Activo');
    await expect(row(page, 'Teddy Boy')).toContainText('Pendiente');
    // A deactivated account is still identifiable by its address.
    await expect(row(page, 'Teddy Boy')).toContainText('teddy@example.com');
    await expect(page.locator('#cuPending')).toBeHidden();
    await expect(row(page,'Teddy Boy').locator('[data-cu-toggle]')).toHaveCount(0);
  });

  test('an account with no address yet degrades to a placeholder, not to blank', async ({ page }) => {
    await openUsers(page, [
      { id: 'test-admin-uid', full_name: 'Admin', email: 'admin@example.com', role: 'administrador', active: true, created_at: '2026-08-25T22:22:22Z' },
      { id: 'u9', full_name: 'Sin correo', email: null, role: 'cliente', active: false, created_at: '2026-09-06T10:00:00Z' },
    ]);
    await expect(row(page, 'Sin correo')).toContainText('—');
  });
});

test('permanent deletion confirms the email, frees the row and hides historical actors in French',async({page})=>{
 await page.setViewportSize({width:390,height:844});
 await openUsers(page,[...PROFILES,{id:'archived',full_name:'Historical author',email:null,role:'comercial',active:false,deleted_at:'2026-09-27T10:00:00Z'}]);
 await expect(row(page,'Historical author')).toHaveCount(0);await expect(row(page,'Jimmy Lisciandra').locator('[data-cu-delete]')).toHaveCount(0);
 await page.evaluate(()=>{window.GamaI18n.setLanguage('fr');window.__deletes=[];const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(name,args)=>{if(name!=='gama_delete_user')return c.rpc(name,args);window.__deletes.push(args);const p=window.__DB.profiles.find(p=>p.id===args.p_user_id);p.deleted_at=new Date().toISOString();p.active=false;p.email=null;return {data:{deleted:true,user_id:p.id}}}}}});
 await row(page,'Teddy Boy').getByRole('button',{name:'Supprimer définitivement'}).click();
 const d=page.locator('dialog[data-identity]');await expect(d).toContainText('même adresse e-mail');await expect(d).toContainText('historique');
 await d.locator('[name=confirmation_email]').fill('wrong@example.com');await d.getByRole('button',{name:'Supprimer définitivement',exact:true}).click();
 await expect(d.locator('[role=alert]')).toContainText('ne correspond pas');expect(await page.evaluate(()=>window.__deletes.length)).toBe(0);
 await d.locator('[name=confirmation_email]').fill('teddy@example.com');await d.getByRole('button',{name:'Supprimer définitivement',exact:true}).click();
 await expect(d).toHaveCount(0);await expect(row(page,'Teddy Boy')).toHaveCount(0);await expect(page.locator('#cuCount')).toHaveText('2 utilisateurs');
 expect(await page.evaluate(()=>window.__deletes)).toEqual([{p_user_id:'u3',p_email:'teddy@example.com'}]);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});

test('cancelled or rejected permanent deletion keeps the account and leaves the form retryable',async({page})=>{
 await openUsers(page);await page.evaluate(()=>{window.__deletes=[];const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(name,args)=>{if(name!=='gama_delete_user')return c.rpc(name,args);window.__deletes.push(args);return {error:{message:'USER_DELETE_NOT_ALLOWED'}}}}}});
 await row(page,'Paula Martinez').locator('[data-cu-delete]').click();await page.locator('dialog[data-identity] [data-arc-dialog-close]').click();
 expect(await page.evaluate(()=>window.__deletes.length)).toBe(0);await expect(row(page,'Paula Martinez')).toBeVisible();
 await row(page,'Paula Martinez').locator('[data-cu-delete]').click();const d=page.locator('dialog[data-identity]');await d.locator('[name=confirmation_email]').fill('paula@example.com');await d.locator('[type=submit]').click();
 await expect(d.locator('[role=alert]')).toContainText('Tu perfil no permite eliminar usuarios.');await expect(d.locator('[type=submit]')).toBeEnabled();await expect(row(page,'Paula Martinez')).toHaveCount(1);
});

// Cada perfil de base con su color, «Activo» en verde y la pantalla entera en el
// idioma elegido (antes: «Cloud conectado», roles y estados en español, hora «p. m.»).
test.describe('Usuarios — colores y traducción', () => {
  const MIXED = [
    ...PROFILES,
    { id: 'u4', full_name: 'Carlos Andrade', email: 'carlos@example.com', role: 'almacenero', active: true, created_at: '2026-09-05T13:43:50Z' },
    { id: 'u5', full_name: 'Ana Torres', email: 'ana@example.com', role: 'rrhh', active: true, created_at: '2026-09-07T08:00:00Z' },
  ];
  const style = (page, name, sel) => row(page, name).locator(sel).evaluate(el => {
    const cs = getComputedStyle(el); return { color: cs.color, background: cs.backgroundColor };
  });

  test('each base role has its own colour and an active account shows in green', async ({ page }) => {
    await openUsers(page, MIXED);
    const names = ['Jimmy Lisciandra', 'Paula Martinez', 'Teddy Boy', 'Carlos Andrade', 'Ana Torres'];
    const badges = [];
    for (const name of names) badges.push(await style(page, name, '.cuBadge'));
    expect(new Set(badges.map(b => b.color + b.background)).size).toBe(names.length);
    expect(await row(page, 'Jimmy Lisciandra').locator('.cuBadge').getAttribute('data-role')).toBe('admin');
    expect((await style(page, 'Paula Martinez', 'td.cuActive')).color).toBe('rgb(13, 116, 70)');
    expect((await style(page, 'Teddy Boy', 'td.cuInactive')).color).toBe('rgb(179, 38, 30)');
  });

  test('the whole screen follows the chosen language', async ({ page }) => {
    await openUsers(page, MIXED);
    await page.evaluate(() => window.GamaI18n.setLanguage('fr'));
    await expect(page.locator('#users .cuOnline')).toHaveText('Cloud connecté');
    await expect(row(page, 'Carlos Andrade').locator('.cuBadge')).toHaveText('Magasinier');
    await expect(row(page, 'Jimmy Lisciandra').locator('.cuBadge')).toHaveText('Administrateur');
    await expect(row(page, 'Paula Martinez').locator('.cuState')).toHaveText('Actif');
    await expect(row(page, 'Teddy Boy').locator('.cuState')).toHaveText('En attente / désactivé');
    await expect(page.locator('#cuCount')).toHaveText('5 utilisateurs');
    await expect(page.locator('#cuPending')).toBeHidden();
    await expect(page.locator('#cuStatus')).not.toContainText('m.');
    await expect(row(page, 'Carlos Andrade')).not.toContainText('p. m.');
    await page.evaluate(() => window.GamaI18n.setLanguage('en'));
    await expect(row(page, 'Carlos Andrade').locator('.cuBadge')).toHaveText('Warehouse operator');
    await expect(page.locator('#cuCount')).toHaveText('5 users');
    await page.evaluate(() => window.GamaI18n.setLanguage('es'));
    await expect(row(page, 'Carlos Andrade').locator('.cuBadge')).toHaveText('Almacenero');
    await expect(page.locator('#cuCount')).toHaveText('5 usuarios');
  });
});
