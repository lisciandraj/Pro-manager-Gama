/** Presentation only. Document currency always takes precedence over company defaults. */
export const escapeHtml = value => String(value ?? '').replace(/[&<>"'\\]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;','\\':'&#92;'}[c]));
export const translate = value => window.GamaI18n?.t?.(value) || value;
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
  return { code, message, fields:error?.fields || {}, retryable:['NETWORK_ERROR','57014','53300'].includes(code), cause:error };
}
export function errorMessage(error) {
  const e = normalizeError(error);
  const messages = {AUTH_REQUIRED:'Vuelve a iniciar sesión.', ROLE_NOT_ALLOWED:'Tu perfil no puede realizar esta operación.', PM_FORBIDDEN:'Tu perfil no puede realizar esta operación.', '23505':'Ya existe un registro con estos datos.', '23503':'Este registro está vinculado a otros documentos.', PM_CONFLICT:'Los datos cambiaron. Actualiza antes de guardar.', NETWORK_ERROR:'Comprueba la conexión y vuelve a intentarlo.'};
  const specific=e.message.match(/\b[A-Z][A-Z_]{3,}\b/)?.[0];
  const audit={
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
