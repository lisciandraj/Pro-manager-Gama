/** Presentation only. Document currency always takes precedence over company defaults. */
export const escapeHtml = value => String(value ?? '').replace(/[&<>"'\\]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;','\\':'&#92;'}[c]));
export const translate = value => window.GamaI18n?.t?.(value) || value;
/** A quoted CSV field is still a formula in a spreadsheet. Only real numbers
 * bypass formula neutralization; never infer a numeric type from user text. */
export function csvCell(value) {
  let text = String(value ?? '');
  if (typeof value !== 'number' && (/^[\u0000-\u001f\u007f]/.test(text) || /^[\s\u0000-\u001f\u007f]*[=+@-]/u.test(text))) text = "'" + text;
  return '"' + text.replace(/"/g, '""') + '"';
}
export function csvRows(rows, {delimiter = ';', bom = true} = {}) {
  if (![';', ',', '\t'].includes(delimiter)) throw Error('CSV_DELIMITER_INVALID');
  return (bom ? '\uFEFF' : '') + rows.map(row => row.map(csvCell).join(delimiter)).join('\r\n');
}
/** Decode only inert receipt formats. Never pass a stored data URL into HTML
 * or a navigation sink. Size and magic bytes are checked before Blob creation. */
export function attachmentBlob(file, {maxBytes = 2000000} = {}) {
  const invalid = () => { throw Error('DOCUMENT_FILE_INVALID'); };
  const input = file?.data_url;
  if (typeof input !== 'string' || !Number.isSafeInteger(maxBytes) || maxBytes < 1 || input.length > 4 * Math.ceil(maxBytes / 3) + 64) return invalid();
  const match = /^data:(application\/pdf|image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/]+={0,2})$/.exec(input);
  if (!match || match[2].length % 4 !== 0 || (file.mime_type && file.mime_type !== match[1])) return invalid();
  const [ , type, data ] = match;
  const size = data.length / 4 * 3 - (data.endsWith('==') ? 2 : data.endsWith('=') ? 1 : 0);
  if (size < 1 || size > maxBytes) return invalid();
  let raw;
  try { raw = atob(data); } catch (_) { return invalid(); }
  if (raw.length !== size || btoa(raw) !== data) return invalid();
  const bytes = Uint8Array.from(raw, c => c.charCodeAt(0));
  const begins = signature => signature.every((byte, i) => bytes[i] === byte);
  const signatures = {
    'application/pdf': () => begins([0x25,0x50,0x44,0x46,0x2d]),
    'image/png': () => begins([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]),
    'image/jpeg': () => begins([0xff,0xd8,0xff]),
    'image/webp': () => begins([0x52,0x49,0x46,0x46]) && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  };
  if (!signatures[type]()) return invalid();
  return new Blob([bytes], {type});
}
const technicalDocumentName = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
export const format = {
  documentLabel(document) {
    if (technicalDocumentName.test(String(document.title || ''))) return document.erp_reference || translate('Documento');
    return document.title || document.erp_reference || translate('Documento');
  },
  documentFilename(filename, reference) {
    if (!reference || !technicalDocumentName.test(String(filename || ''))) return filename || 'document';
    const extension = String(filename).match(/\.[a-z0-9]{1,8}$/i)?.[0] || '';
    return String(reference).replace(/[\\/]/g, '_') + extension;
  },
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
  return { code, message, fields:error?.fields || {}, retryable:['NETWORK_ERROR','TIMEOUT','READ_CANCELLED','57014','53300'].includes(code), cause:error };
}
export function errorMessage(error) {
  const e = normalizeError(error);
  const messages = {AUTH_REQUIRED:'Vuelve a iniciar sesión.', ROLE_NOT_ALLOWED:'Tu perfil no puede realizar esta operación.', PM_FORBIDDEN:'Tu perfil no puede realizar esta operación.', '23505':'Ya existe un registro con estos datos.', '23503':'Este registro está vinculado a otros documentos.', PM_CONFLICT:'Los datos cambiaron. Actualiza antes de guardar.', NETWORK_ERROR:'Comprueba la conexión y vuelve a intentarlo.', DOCUMENT_FILE_INVALID:'Formato de archivo no permitido.'};
  const specific=e.message.match(/\b[A-Z][A-Z_]{3,}\b/)?.[0];
  const audit={
   CHECKOUT_RECEIPT_RESERVED:['Este anticipo está reservado. Aplícalo a una factura vinculada o solicita la liberación de su reserva contable.','Cet acompte est réservé. Affectez-le à une facture liée ou demandez la levée de sa réservation comptable.','This advance is reserved. Allocate it to a linked invoice or request release of its accounting reservation.'],
   CHECKOUT_PAYMENT_REVIEW_REQUIRED:['El pago requiere revisión contable antes de continuar.','Le paiement nécessite une vérification comptable avant de continuer.','The payment requires accounting review before continuing.'],
   SRI_TAX_MAPPING_REQUIRED:['Estas reglas de impuestos requieren una correspondencia fiscal SRI específica. Revisa la configuración antes de emitir; la factura interna se conserva.','Ces règles de taxes nécessitent une correspondance fiscale SRI spécifique. Vérifiez le paramétrage avant l’émission ; la facture interne est conservée.','These tax rules require a specific SRI fiscal mapping. Review the settings before issuing; the internal invoice is preserved.'],
   SRI_TAX_PRICE_PRECISION_REQUIRED:['Revisa los precios y el redondeo fiscal antes de emitir al SRI. Los importes de la factura interna se conservan.','Vérifiez les prix et l’arrondi fiscal avant l’émission au SRI. Les montants de la facture interne sont conservés.','Review prices and fiscal rounding before issuing to SRI. The internal invoice amounts are preserved.'],
   SRI_DEPOSIT_MAPPING_REQUIRED:['Revisa la correspondencia fiscal SRI del anticipo antes de emitir. El anticipo interno y sus impuestos se conservan.','Vérifiez la correspondance fiscale SRI de l’acompte avant l’émission. L’acompte interne et ses taxes sont conservés.','Review the advance’s SRI fiscal mapping before issuing. The internal advance and its taxes are preserved.'],
   TIMEOUT:['La lectura tarda demasiado. Vuelve a intentarlo.','Le chargement prend trop de temps. Réessayez.','Loading is taking too long. Try again.'],
   READ_CANCELLED:['La lectura se ha cancelado. Vuelve a intentarlo.','Le chargement a été annulé. Réessayez.','Loading was cancelled. Try again.'],
   EC_IDENTIFICATION_INVALID:['Revisa el RUC o la cédula y su tipo. El dígito verificador no coincide.','Vérifiez le RUC ou la cédula et son type. Le chiffre de contrôle ne correspond pas.','Check the RUC or cédula and its type. The check digit does not match.'],
   PARTNER_IDENTIFICATION_DUPLICATE:['Ya existe un contacto con esta identificación. Abre su ficha para actualizarlo.','Un contact possède déjà cette identification. Ouvrez sa fiche pour le mettre à jour.','A contact with this identification already exists. Open its record to update it.'],
   DOCUMENT_CHANGED:['La situación cambió. Actualiza la solicitud de aprobación.','La situation a changé. Actualisez la demande d’approbation.','The situation changed. Refresh the approval request.'],
   STOCK_REQUIRES_MOVEMENT:['El stock requiere un movimiento con ubicación.','Le stock nécessite un mouvement avec emplacement.','Stock requires a located movement.'],
   INDEPENDENT_APPROVER_REQUIRED:['Se requiere otro validador o una excepción autorizada y justificada.','Un autre validateur est requis, ou une exception autorisée et justifiée.','A different approver or an authorized justified exception is required.'],
   ADJUSTMENT_APPROVAL_REQUIRED:['Registra una solicitud de ajuste para su validación.','Enregistrez une demande d’ajustement à valider.','Submit an adjustment request for approval.'],
   OPENING_LOCATION_AND_REASON_REQUIRED:['Indica la ubicación y una justificación de al menos 10 caracteres para el stock inicial.','Indiquez l’emplacement et une justification d’au moins 10 caractères pour le stock initial.','Provide an opening location and a reason of at least 10 characters.'],
   METHOD_CHANGE_REQUIRES_EMPTY_STOCK:['Vacía el stock antes de cambiar el método de valoración.','Le stock doit être vide pour changer de méthode de valorisation.','Stock must be empty before changing the valuation method.'],
   PRODUCT_NOT_READY:['Completa los campos señalados antes de activar el producto.','Complétez les champs signalés avant d’activer le produit.','Complete the flagged fields before activating the product.'],
   LOCATION_SCAN_REQUIRED:['Escanea la ubicación de origen.','Scannez l’emplacement d’origine.','Scan the source location.']
  };
  if(audit[specific])return audit[specific][{es:0,fr:1,en:2}[window.GamaI18n?.language]??0]+(specific==='PRODUCT_NOT_READY'?' '+e.message.split(':').slice(1).join(':'):'');
  return translate(messages[e.code] || e.message);
}
