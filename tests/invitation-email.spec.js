// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// El correo con el que se crea un acceso se personaliza: el modelo de la
// empresa se edita en Usuarios y se puede retocar en cada invitación.
async function openUsers(page) {
  await page.addInitScript(() => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Jimmy Lisciandra' }));
    // @ts-ignore
    window.__DB = {
      profiles: [{ id: 'test-admin-uid', full_name: 'Jimmy Lisciandra', email: 'admin@example.com', role: 'administrador', active: true, created_at: '2026-08-25T22:22:22Z' }],
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      company_settings: [{ id: true, legal_name: 'Ferretería Andina' }],
      access_invitation_template: [{ id: true, subject: 'Tu acceso a {empresa}', message: 'Hola {nombre}:\n\n{empresa} te ha creado un acceso con el perfil {rol}.', version: 3 }],
    };
    // @ts-ignore
    window.__DB._profile = { id: 'test-admin-uid', full_name: 'Jimmy Lisciandra', email: 'admin@example.com', role: 'administrador', active: true };
  });
  await page.route('**/gama-supabase.js*', route => route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1200);
  await page.addScriptTag({ url: '/gama-cloud-users.js' });
  await page.click('#mainmenu .gamaF2Card[data-gama-module="users"]');
  await page.waitForSelector('[data-invite-template]');
  await page.evaluate(async () => {
    const old = GamaCloud.db; window.__invites = [];
    GamaCloud.db = async () => { const c = await old(); return { ...c, functions: { invoke: async (_name, { body }) => { window.__invites.push(body); return { data: { invited: true } }; } } }; };
  });
}

test('el administrador edita el correo de invitación con vista previa y control de versión', async ({ page }) => {
  await openUsers(page);
  await page.locator('[data-invite-template]').click();
  const d = page.locator('dialog');
  await expect(d.locator('[name=subject]')).toHaveValue('Tu acceso a {empresa}');
  await expect(d.locator('[data-invite-preview]')).toContainText('Tu acceso a Ferretería Andina');
  await d.locator('[name=subject]').fill('Bienvenido a {empresa}, {nombre}');
  await expect(d.locator('[data-invite-preview]')).toContainText('Bienvenido a Ferretería Andina, Ana Pérez');
  await d.locator('[type=submit]').click();
  await expect(d).toHaveCount(0);
  expect(await page.evaluate(() => __DB.access_invitation_template[0])).toMatchObject({ subject: 'Bienvenido a {empresa}, {nombre}', version: 4 });
});

test('la invitación envía el asunto y el mensaje ya personalizados, y se pueden retocar', async ({ page }) => {
  await openUsers(page);
  await page.locator('[data-invite-user]').click();
  const d = page.locator('dialog');
  await d.locator('[name=name]').fill('Paula Martínez');
  await d.locator('[name=email]').fill('paula@example.com');
  await d.locator('[name=role]').selectOption('comercial');
  await d.locator('details.idMail summary').click();
  await expect(d.locator('[data-invite-preview]')).toContainText('Hola Paula Martínez:');
  await d.locator('[name=message]').fill('Hola {nombre}, te esperamos el lunes en {empresa}.');
  await d.locator('[type=submit]').click();
  await expect(d).toHaveCount(0);
  expect(await page.evaluate(() => window.__invites)).toEqual([{ action: 'invite', name: 'Paula Martínez', email: 'paula@example.com', role: 'comercial', company: 'Ferretería Andina', subject: 'Tu acceso a Ferretería Andina', message: 'Hola Paula Martínez, te esperamos el lunes en Ferretería Andina.' }]);
});

test('un modelo cambiado por otra persona no se pisa', async ({ page }) => {
  await openUsers(page);
  await page.locator('[data-invite-template]').click();
  await page.evaluate(() => { __DB.access_invitation_template[0].version = 9; });
  await page.locator('dialog [name=message]').fill('Otro texto');
  await page.locator('dialog [type=submit]').click();
  await expect(page.locator('dialog [role=alert]')).not.toBeEmpty();
  expect(await page.evaluate(() => __DB.access_invitation_template[0].message)).not.toBe('Otro texto');
});
