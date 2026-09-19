/** Presentation only. Document currency always takes precedence over company defaults. */
export const escapeHtml = value => String(value ?? '').replace(/[&<>"'\\]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;','\\':'&#92;'}[c]));
export const translate = value => window.GamaI18n?.t?.(value) || value;
export const format = {
  money(value, currency) {
    if (!currency && window.GamaCurrency) return window.GamaCurrency.format(value);
    return new Intl.NumberFormat(window.GamaI18n?.locale || 'es-EC', {style:'currency', currency:currency || window.GamaCurrency?.get?.() || 'USD'}).format(Number(value) || 0);
  },
  number(value, decimals = 3) { return new Intl.NumberFormat(window.GamaI18n?.locale || 'es-EC', {maximumFractionDigits:decimals}).format(Number(value) || 0); },
  date(value) { if (!value) return '—'; const d = /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(value + 'T12:00:00') : new Date(value); return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString(window.GamaI18n?.locale || 'es-EC'); }
};
export function normalizeError(error) {
  const message = String(error?.message || error || 'UNKNOWN_ERROR');
  const code = error?.code || message.match(/\b[A-Z][A-Z_]{3,}\b/)?.[0] || 'UNKNOWN_ERROR';
  return { code, message, fields:error?.fields || {}, retryable:['NETWORK_ERROR','57014','53300'].includes(code), cause:error };
}
export function errorMessage(error) {
  const e = normalizeError(error);
  const messages = {AUTH_REQUIRED:'Vuelve a iniciar sesión.', ROLE_NOT_ALLOWED:'Tu perfil no puede realizar esta operación.', PM_FORBIDDEN:'Tu perfil no puede realizar esta operación.', '23505':'Ya existe un registro con estos datos.', '23503':'Este registro está vinculado a otros documentos.', PM_CONFLICT:'Los datos cambiaron. Actualiza antes de guardar.', NETWORK_ERROR:'Comprueba la conexión y vuelve a intentarlo.'};
  return translate(messages[e.code] || e.message);
}
