(function() {
  "use strict";
  const icons = {
    sales: '<path d="M3 20h18M5 17v-4M10 17V9M15 17V5M4 10l6-5 5 1 5-4M16 2h4v4"/>',
    globe: '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M5 6h14M5 18h14"/>',
    cocoBot: '<path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M4 11V7M20 11V7"/><rect x="4" y="6" width="16" height="15" rx="7"/><rect x="6.5" y="10" width="11" height="8" rx="4"/><path d="M8.5 14q1-2 2 0M13.5 14q1-2 2 0M4 11H3a1 1 0 0 0-1 1v4a1 1 0 0 0 1 1h1M20 11h1a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-1"/>',
    brain: '<path d="M12 5a3 3 0 0 0-5.8-1A4 4 0 0 0 3 10a4 4 0 0 0 1 7.8A4 4 0 0 0 12 18V5Zm0 0a3 3 0 0 1 5.8-1A4 4 0 0 1 21 10a4 4 0 0 1-1 7.8A4 4 0 0 1 12 18"/><path d="M6.2 4A3 3 0 0 0 7 7M3 10a3 3 0 0 1 4 1M4 17.8A3 3 0 0 0 7 15M17.8 4A3 3 0 0 1 17 7M21 10a3 3 0 0 0-4 1M20 17.8A3 3 0 0 1 17 15M9 10a3 3 0 0 1 3 3M15 10a3 3 0 0 0-3 3"/>',
    robot: '<rect x="4" y="7" width="16" height="13" rx="4"/><path d="M12 7V4M4 12H2v4h2M20 12h2v4h-2M9 16q3 2 6 0"/><circle cx="12" cy="2.5" r="1.5"/><circle cx="9" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1" fill="currentColor" stroke="none"/>',
    headset: '<path d="M4 14V11a8 8 0 0 1 16 0v6a4 4 0 0 1-4 4h-4"/><rect x="2" y="11" width="4" height="7" rx="2"/><rect x="18" y="11" width="4" height="7" rx="2"/>',
    documents: '<path d="M8 2h8l5 5v13a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2ZM16 2v6h5M10 12h7M10 16h7M3 5v14"/>',
    car: '<path d="m5 10 2-5h10l2 5M5 10h14a2 2 0 0 1 2 2v5H3v-5a2 2 0 0 1 2-2ZM5 17v3M19 17v3M6 13h2M16 13h2"/>',
    sparkles: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3ZM20 2v4M18 4h4M3 18v4M1 20h4"/>',
    ledger: '<path d="M5 3h12a2 2 0 0 1 2 2v16H7a2 2 0 0 1-2-2V3Z"/><path d="M5 7H3m2 5H3m2 5H3"/><path d="M9 8h6M9 12h6M9 16h3"/>',
    truck: '<path d="M3 7h11v9H3z"/><path d="M14 10h4l3 3v3h-7z"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
    returnArrow: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10a6 6 0 0 1 6 6v5"/>',
    project: '<path d="M4 3v18h17"/><rect x="7" y="5" width="6" height="3" rx=".5"/><rect x="11" y="10" width="8" height="3" rx=".5"/><rect x="15" y="15" width="6" height="3" rx=".5"/>',
    knowledge: '<path d="M5 3h12a2 2 0 0 1 2 2v16H6a3 3 0 0 1-3-3V5a2 2 0 0 1 2-2ZM3 17h16M8 3v8l3-2 3 2V3"/>',
    lock: '<rect x="5" y="10" width="14" height="12" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4M12 15v3"/>',
    message: '<path d="M21 14a3 3 0 0 1-3 3H9l-6 4V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8Z"/><path d="M7 8h10M7 12h6"/>',
    checklist: '<path d="M8 4H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-3"/><rect x="8" y="2" width="8" height="4" rx="1"/><path d="m6 11 1.5 1.5L10 10m-4 7 1.5 1.5L10 16M13 11h4M13 17h4"/>',
    banknote: '<rect x="2" y="5" width="20" height="14" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M2 9a4 4 0 0 0 4-4M18 5a4 4 0 0 0 4 4M2 15a4 4 0 0 1 4 4M18 19a4 4 0 0 1 4-4"/>',
    bag: '<path d="M5 7h14l2 14H3L5 7Z"/><path d="M9 8V5a3 3 0 0 1 6 0v3M8 14h8m-3-3 3 3-3 3"/>',
    folder: '<path d="M3 7V5a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/><circle cx="7" cy="14" r="1"/><circle cx="12" cy="14" r="1"/><circle cx="17" cy="14" r="1"/><path d="M8 14h3M13 14h3"/>',
    pin: '<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><path d="m8.5 10 2.2 2.2 4.8-4.8"/>',
    factory: '<path d="M3 21V10l6 3V9l6 3V3h4l2 18H3Z"/><path d="M6 17h1M11 17h1M16 17h1"/>',
    bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
    gauge: '<path d="M4.2 18a9 9 0 1 1 15.6 0Z"/><path d="M12 5v2M5.6 8l1.5 1.5M18.4 8l-1.5 1.5M12 14l3-4"/><circle cx="12" cy="14" r="1.5"/>',
    handshake: '<path d="M11 6.5 8.8 8.7a2 2 0 0 0 0 2.8l.3.3a2 2 0 0 0 2.8 0l1.2-1.2 3.4 3.4a1.6 1.6 0 0 1-2.3 2.3l-.5-.5"/><path d="M3 7.5 6 5l4 1 3.5-1.5L21 7.5"/><path d="M21 7.5v6M3 7.5v6"/>',
    chart: '<path d="M4 19V10m5 9V6m5 13v-8m5 8V3"/><path d="m4 9 5-4 5 3 6-6"/>',
    cube: '<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
    users: '<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
    move: '<path d="M7 4v16M17 20V4M4 7l3-3 3 3M14 17l3 3 3-3"/>',
    invoice: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
    stock: '<path d="M3 3v18M21 3v18M3 11h18M3 20h18"/><rect x="6" y="4" width="5" height="7" rx=".5"/><rect x="13" y="6" width="5" height="5" rx=".5"/><rect x="6" y="14" width="12" height="6" rx=".5"/>',
    audit: '<circle cx="10" cy="10" r="7"/><path d="m15 15 6 6M7 8h6M7 12h4"/>',
    cart: '<path d="M3 4h2l2.2 10.2a2 2 0 0 0 2 1.6h7.4a2 2 0 0 0 1.9-1.4L20 8H6"/><circle cx="9" cy="19" r="1.5"/><circle cx="17" cy="19" r="1.5"/><path d="M9 11h8M12 8v6M15 8v6"/>',
    spreadsheet: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18M15 3v18"/>',
    gears: '<g stroke-width="1.4"><path d="M11.61 5.44L13.50 5.81L13.50 9.59L11.61 9.96L11.61 9.96L12.23 11.78L8.97 13.67L7.70 12.21L7.70 12.21L6.43 13.67L3.17 11.78L3.79 9.96L3.79 9.96L1.90 9.59L1.90 5.81L3.79 5.44L3.79 5.44L3.17 3.62L6.43 1.73L7.70 3.19L7.70 3.19L8.97 1.73L12.23 3.62L11.61 5.44Z"/><circle cx="7.7" cy="7.7" r="1.83"/><path d="M20.14 15.19L21.66 15.49L21.66 18.51L20.14 18.81L20.14 18.81L20.64 20.28L18.02 21.79L17.00 20.63L17.00 20.63L15.98 21.79L13.36 20.28L13.86 18.81L13.86 18.81L12.34 18.51L12.34 15.49L13.86 15.19L13.86 15.19L13.36 13.72L15.98 12.21L17.00 13.37L17.00 13.37L18.02 12.21L20.64 13.72L20.14 15.19Z"/><circle cx="17" cy="17" r="1.47"/></g>',
    cloud: '<path d="M7 18h11a4 4 0 0 0 .5-8 6 6 0 0 0-11.6 1A3.5 3.5 0 0 0 7 18Z"/><path d="M12 12v6m0 0-2-2m2 2 2-2"/>',
    user: '<rect x="4" y="3" width="16" height="14" rx="2"/><path d="m4 17-2 4h20l-2-4M8 14a4 4 0 0 1 8 0"/><circle cx="12" cy="8" r="2"/>',
    barcode: '<path d="M4 5v14M7 5v14M10 5v14M14 5v14M17 5v14M20 5v14"/>',
    catalog: '<path d="M12 5C9 3 5 3 2 4v15c3-1 7-1 10 1 3-2 7-2 10-1V4c-3-1-7-1-10 1ZM12 5v15M5 8h4M5 12h4M15 8h4M15 12h4"/>',
    tag: '<path d="M3 12V5.5A2.5 2.5 0 0 1 5.5 3H12l9 9-9 9-9-9Z"/><circle cx="7.5" cy="7.5" r="1.4"/>',
    matrix: '<rect x="3" y="3" width="6" height="6" rx="1"/><rect x="15" y="3" width="6" height="6" rx="1"/><rect x="3" y="15" width="6" height="6" rx="1"/><rect x="15" y="15" width="6" height="6" rx="1"/><path d="M9 6h6M6 9v6M18 9v6M9 18h6"/>',
    warehouse: '<path d="M3 10.5 12 4l9 6.5V20H3z"/><path d="M7 20v-6h10v6M7 14h10"/>',
    badge: '<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M9 6V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V6"/><circle cx="12" cy="12" r="2"/><path d="M8.5 17c.4-1.6 1.8-2.5 3.5-2.5s3.1.9 3.5 2.5"/>'
  };
  const moduleIllustrations = {
    chart: '<g fill="currentColor" stroke="none"><rect x="3" y="15" width="3" height="7" rx=".6"/><rect x="8" y="11" width="3" height="11" rx=".6"/><rect x="13" y="13" width="3" height="9" rx=".6"/><rect x="18" y="8" width="3" height="14" rx=".6"/></g><path d="m4 11 5-6 5 2 6-5" fill="none" stroke="var(--gama-orange)" stroke-width="1.3"/><g fill="var(--gama-orange)" stroke="none"><circle cx="4" cy="11" r="1.5"/><circle cx="9" cy="5" r="1.5"/><circle cx="14" cy="7" r="1.5"/><circle cx="20" cy="2" r="1.5"/></g>',
    cube: '<path d="m12 2 10 5.5L12 13 2 7.5Z" fill="currentColor" stroke="none"/><path d="M2 9l9 5v9l-9-5Z" fill="var(--gama-blue-dark)" stroke="none"/><path d="m13 14 9-5v9l-9 5Z" fill="currentColor" stroke="none"/>',
    users: '<g fill="var(--gama-orange)" stroke="none"><circle cx="18" cy="7" r="3.1"/><path d="M15 12c5-1 8 2 8 8h-8Z"/></g><g fill="currentColor" stroke="none"><circle cx="8" cy="6" r="4"/><path d="M1 20v-2c0-7 14-7 14 0v2Z"/></g>',
    truck: '<path d="M2 4h12v13H2Z" fill="currentColor" stroke="none"/><path d="M15 8h4l4 5v4h-8Z" fill="var(--gama-blue-dark)" stroke="none"/><path d="M17 10h2l2 3h-4Z" fill="white" stroke="none"/><g fill="var(--gama-blue-dark)" stroke="white" stroke-width=".7"><circle cx="6" cy="18" r="3"/><circle cx="19" cy="18" r="3"/></g>',
    invoice: '<path d="M5 2h10l5 5v15H5Z M15 2v6h5" fill="none" stroke="var(--gama-blue-dark)" stroke-width="1.5"/><path d="M8 8h3M8 12h8M8 16h4" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M17 16c-3-2-4 2-1 2s2 4-1 2m1-5v7" fill="none" stroke="var(--gama-orange)" stroke-width="1.3"/>',
    cart: '<path d="M2 3h3l3 13h12l3-10H6" fill="var(--gama-orange)" fill-opacity=".15" stroke="var(--gama-orange)" stroke-width="1.5"/><g fill="currentColor" stroke="none"><circle cx="9" cy="21" r="2"/><circle cx="19" cy="21" r="2"/></g>'
  };
  function moduleIcon(name) {
    const drawing = moduleIllustrations[name] || icons[name];
    return drawing ? "<svg" + (moduleIllustrations[name] ? ' class="arcHomeIllustration"' : "") + ' xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">' + drawing + "</svg>" : "";
  }
  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"'\\]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;", "\\": "&#92;" })[c]);
  const translate = (value) => {
    var _a, _b;
    return ((_b = (_a = window.GamaI18n) == null ? void 0 : _a.t) == null ? void 0 : _b.call(_a, value)) || value;
  };
  const technicalDocumentName = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
  const format = {
    documentLabel(document2) {
      if (technicalDocumentName.test(String(document2.title || ""))) return document2.erp_reference || translate("Documento");
      return document2.title || document2.erp_reference || translate("Documento");
    },
    documentFilename(filename, reference) {
      var _a;
      if (!reference || !technicalDocumentName.test(String(filename || ""))) return filename || "document";
      const extension = ((_a = String(filename).match(/\.[a-z0-9]{1,8}$/i)) == null ? void 0 : _a[0]) || "";
      return String(reference).replace(/[\\/]/g, "_") + extension;
    },
    money(value, currency) {
      var _a, _b, _c;
      if (!currency && window.GamaCurrency) return window.GamaCurrency.format(value);
      return new Intl.NumberFormat(((_a = window.GamaI18n) == null ? void 0 : _a.locale) || "es-EC", { style: "currency", currency: currency || ((_c = (_b = window.GamaCurrency) == null ? void 0 : _b.get) == null ? void 0 : _c.call(_b)) || "USD" }).format(Number(value) || 0);
    },
    number(value, decimals = 3) {
      var _a;
      return new Intl.NumberFormat(((_a = window.GamaI18n) == null ? void 0 : _a.locale) || "es-EC", { maximumFractionDigits: decimals }).format(Number(value) || 0);
    },
    date(value) {
      var _a;
      if (!value) return "—";
      const d = /^\d{4}-\d{2}-\d{2}$/.test(value) ? /* @__PURE__ */ new Date(value + "T12:00:00") : new Date(value);
      return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString(((_a = window.GamaI18n) == null ? void 0 : _a.locale) || "es-EC");
    }
  };
  function normalizeError(error) {
    var _a;
    const message = String((error == null ? void 0 : error.message) || error || "UNKNOWN_ERROR");
    const code = (error == null ? void 0 : error.code) || ((_a = message.match(/\b[A-Z][A-Z_]{3,}\b/)) == null ? void 0 : _a[0]) || "UNKNOWN_ERROR";
    return { code, message, fields: (error == null ? void 0 : error.fields) || {}, retryable: ["NETWORK_ERROR", "57014", "53300"].includes(code), cause: error };
  }
  function errorMessage(error) {
    var _a, _b;
    const e = normalizeError(error);
    const messages = { AUTH_REQUIRED: "Vuelve a iniciar sesión.", ROLE_NOT_ALLOWED: "Tu perfil no puede realizar esta operación.", PM_FORBIDDEN: "Tu perfil no puede realizar esta operación.", "23505": "Ya existe un registro con estos datos.", "23503": "Este registro está vinculado a otros documentos.", PM_CONFLICT: "Los datos cambiaron. Actualiza antes de guardar.", NETWORK_ERROR: "Comprueba la conexión y vuelve a intentarlo." };
    const specific = (_a = e.message.match(/\b[A-Z][A-Z_]{3,}\b/)) == null ? void 0 : _a[0];
    const audit = {
      EC_IDENTIFICATION_INVALID: ["Revisa el RUC o la cédula y su tipo. El dígito verificador no coincide.", "Vérifiez le RUC ou la cédula et son type. Le chiffre de contrôle ne correspond pas.", "Check the RUC or cédula and its type. The check digit does not match."],
      PARTNER_IDENTIFICATION_DUPLICATE: ["Ya existe un contacto con esta identificación. Abre su ficha para actualizarlo.", "Un contact possède déjà cette identification. Ouvrez sa fiche pour le mettre à jour.", "A contact with this identification already exists. Open its record to update it."],
      DOCUMENT_CHANGED: ["La situación cambió. Actualiza la solicitud de aprobación.", "La situation a changé. Actualisez la demande d’approbation.", "The situation changed. Refresh the approval request."],
      STOCK_REQUIRES_MOVEMENT: ["El stock requiere un movimiento con ubicación.", "Le stock nécessite un mouvement avec emplacement.", "Stock requires a located movement."],
      INDEPENDENT_APPROVER_REQUIRED: ["Se requiere otro validador o una excepción autorizada y justificada.", "Un autre validateur est requis, ou une exception autorisée et justifiée.", "A different approver or an authorized justified exception is required."],
      ADJUSTMENT_APPROVAL_REQUIRED: ["Registra una solicitud de ajuste para su validación.", "Enregistrez une demande d’ajustement à valider.", "Submit an adjustment request for approval."],
      OPENING_LOCATION_AND_REASON_REQUIRED: ["Indica la ubicación y una justificación de al menos 10 caracteres para el stock inicial.", "Indiquez l’emplacement et une justification d’au moins 10 caractères pour le stock initial.", "Provide an opening location and a reason of at least 10 characters."],
      METHOD_CHANGE_REQUIRES_EMPTY_STOCK: ["Vacía el stock antes de cambiar el método de valoración.", "Le stock doit être vide pour changer de méthode de valorisation.", "Stock must be empty before changing the valuation method."],
      PRODUCT_NOT_READY: ["Completa los campos señalados antes de activar el producto.", "Complétez les champs signalés avant d’activer le produit.", "Complete the flagged fields before activating the product."],
      LOCATION_SCAN_REQUIRED: ["Escanea la ubicación de origen.", "Scannez l’emplacement d’origine.", "Scan the source location."]
    };
    if (audit[specific]) return audit[specific][{ es: 0, fr: 1, en: 2 }[(_b = window.GamaI18n) == null ? void 0 : _b.language] ?? 0] + (specific === "PRODUCT_NOT_READY" ? " " + e.message.split(":").slice(1).join(":") : "");
    return translate(messages[e.code] || e.message);
  }
  let sequence = 0;
  const attr = (key, value) => value == null || value === false ? "" : value === true ? " " + key : " " + key + '="' + escapeHtml(value) + '"';
  const attributes = (values) => Object.entries(values).map(([key, value]) => attr(key, value)).join("");
  function button({ label = "", variant = "secondary", id, type = "button", disabled = false, attrs = "", className = "" } = {}) {
    if (!["primary", "secondary", "ghost", "danger", "success"].includes(variant)) variant = "secondary";
    return `<button${attributes({ id, type, disabled })} class="arcButton ${variant} ${escapeHtml(className)}" ${attrs}>${escapeHtml(label)}</button>`;
  }
  function field({ id = "arc-field-" + ++sequence, key, name = key, label = "", type = "text", value = "", required = false, readOnly = false, disabled = false, min, max, step, maxLength, options = [], help = "", error = "", attrs = "", className = "" } = {}) {
    const errorId = id + "-error", helpId = id + "-help";
    const props = attributes({ id, name, required, readonly: readOnly, disabled, min, max, step, maxlength: maxLength, "aria-invalid": error ? "true" : null, "aria-describedby": error ? errorId : help ? helpId : null });
    let control;
    if (type === "select" || type === "multi") {
      const values = (Array.isArray(value) ? value : [value]).map(String);
      control = `<select${props}${type === "multi" ? " multiple" : ""} ${attrs}>${type === "select" ? '<option value="">—</option>' : ""}${options.map((o) => `<option value="${escapeHtml(o.value ?? o.id)}"${values.includes(String(o.value ?? o.id)) ? " selected" : ""}>${escapeHtml(o.label ?? o.name)}</option>`).join("")}</select>`;
    } else if (type === "textarea") control = `<textarea${props} ${attrs}>${escapeHtml(value)}</textarea>`;
    else control = `<input${props} type="${escapeHtml(type)}"${type === "checkbox" ? value ? " checked" : "" : ' value="' + escapeHtml(value) + '"'} ${attrs}>`;
    return `<label class="arcField ${escapeHtml(className)}" for="${escapeHtml(id)}"><span>${escapeHtml(translate(label))}${required ? " *" : ""}</span>${control}${help ? `<small id="${escapeHtml(helpId)}">${escapeHtml(translate(help))}</small>` : ""}<small id="${escapeHtml(errorId)}" class="arcFieldError"${error ? "" : " hidden"}>${escapeHtml(translate(error))}</small></label>`;
  }
  function panel(html, { className = "", id, accent } = {}) {
    return `<div${attributes({ id, "data-accent": accent })} class="arcPanel ${escapeHtml(className)}">${html}</div>`;
  }
  function toolbar(html, { className = "" } = {}) {
    return `<div class="arcToolbar ${escapeHtml(className)}">${html}</div>`;
  }
  const stripIcon = (text2) => {
    try {
      return String(text2).replace(/^[^\p{L}\p{N}]+/u, "") || String(text2);
    } catch (_) {
      return String(text2);
    }
  };
  function header({ title = "Módulo", lead = "", module = "" } = {}) {
    return `<div class="gamaStdHeader arcPageHeader gamaCompactHeader" data-gama-standard-header="1"><span class="gamaStdIcon" data-arc-icon-slot${module ? ' data-arc-module="' + escapeHtml(module) + '"' : ""} aria-hidden="true"></span><div class="gamaStdText"><div class="gamaStdKicker">COCO ERP</div><h2>${escapeHtml(stripIcon(title))}</h2>${lead ? "<p>" + escapeHtml(lead) + "</p>" : ""}</div><div class="gamaStdActions">${button({ label: translate("← Volver al menú"), className: "gamaStdBack", attrs: 'data-gi-live data-gi-aria-label=live aria-label="' + escapeHtml(translate("Volver al menú")) + '"' })}</div></div>`;
  }
  function headerIcon(root, id = "") {
    var _a;
    const scope = root && root.querySelectorAll ? root : document;
    const slots = scope.querySelectorAll(".gamaStdIcon[data-arc-icon-slot]");
    if (!slots.length) return;
    const modules2 = globalThis.ArcModules, icons2 = (_a = globalThis.ArcUI) == null ? void 0 : _a.icons;
    if (!modules2 || !icons2) return;
    let pending = false;
    slots.forEach((slot) => {
      const section = slot.closest("section[id]");
      const key = slot.dataset.arcModule || id || SECTION_ALIAS[section == null ? void 0 : section.id] || (section == null ? void 0 : section.id) || "";
      if (!key) {
        pending = true;
        return;
      }
      const definition = modules2.get(key);
      const drawing = definition && icons2[definition.icon];
      if (!drawing) return;
      slot.dataset.arcFam = definition.accent || "cyan";
      slot.innerHTML = moduleIcon(definition.icon);
      delete slot.dataset.arcIconSlot;
    });
    if (pending && !headerIcon.retrying) {
      headerIcon.retrying = true;
      setTimeout(() => {
        headerIcon.retrying = false;
        headerIcon(document);
      }, 0);
    }
  }
  const SECTION_ALIAS = { "gama-tms-section": "tms" };
  function badge(status, label = status, { className = "", tone = "neutral" } = {}) {
    return `<span class="arcStatusBadge ${escapeHtml(className)}" data-s="${escapeHtml(status)}" data-tone="${escapeHtml(tone)}">${escapeHtml(translate(label))}</span>`;
  }
  function kpi({ label, value, help = "", className = "" } = {}) {
    return `<div class="arcKpi ${escapeHtml(className)}"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value ?? "—")}</strong>${help ? "<small>" + escapeHtml(help) + "</small>" : ""}</div>`;
  }
  function form(fields, { id = "arc-form-" + ++sequence, values = {}, submitLabel = translate("Guardar") } = {}) {
    return `<form id="${escapeHtml(id)}" class="arcForm"><div class="arcFormGrid">${fields.map((f) => field({ ...f, value: values[f.key] ?? "" })).join("")}</div><p class="arcFormError" role="alert"></p>${button({ type: "submit", variant: "primary", label: submitLabel })}</form>`;
  }
  function bindForm(el, onSubmit, { error = errorMessage, onSuccess } = {}) {
    if (el.__arcForm) return el.__arcForm;
    let pending = false;
    const submit = async (event) => {
      event.preventDefault();
      if (pending || !el.reportValidity()) return;
      pending = true;
      el.setAttribute("aria-busy", "true");
      const controls = [...el.querySelectorAll("button,input[type=submit]")], previous = controls.map((c) => c.disabled);
      controls.forEach((c) => c.disabled = true);
      const message = el.querySelector("[role=alert]");
      if (message) message.textContent = "";
      try {
        await onSubmit(el, new FormData(el));
        await (onSuccess == null ? void 0 : onSuccess());
      } catch (e) {
        if (message) {
          message.textContent = error(e);
          message.tabIndex = -1;
          message.focus();
        } else throw e;
      } finally {
        pending = false;
        el.removeAttribute("aria-busy");
        controls.forEach((c, i) => c.disabled = previous[i]);
      }
    };
    el.addEventListener("submit", submit);
    const api = { get pending() {
      return pending;
    }, dispose() {
      el.removeEventListener("submit", submit);
      delete el.__arcForm;
    } };
    el.__arcForm = api;
    return api;
  }
  function guard(action2) {
    let pending;
    return function(...args) {
      if (pending) return pending;
      pending = Promise.resolve().then(() => action2.apply(this, args)).finally(() => {
        pending = void 0;
      });
      return pending;
    };
  }
  function dialog({ title, body = "", saveLabel = translate("Guardar"), onSave, error = errorMessage, className = "", ids = {} }) {
    const el = document.createElement("dialog"), lastFocus = document.activeElement;
    const titleId = "arc-dialog-title-" + ++sequence;
    el.className = "arcDialog " + className;
    el.setAttribute("aria-labelledby", titleId);
    el.innerHTML = `<form class="arcForm"><h2 id="${titleId}">${escapeHtml(translate(title))}</h2>${body}<p class="arcFormError gsError" role="alert"${attr("id", ids.error)}></p><div class="arcToolbar gsActions">${button({ id: ids.close, label: translate("Volver"), attrs: "data-arc-dialog-close" })}${button({ id: ids.save, type: "submit", variant: "primary", label: translate(saveLabel) })}</div></form>`;
    document.body.appendChild(el);
    let formApi;
    const close = () => {
      if (formApi == null ? void 0 : formApi.pending) return;
      el.close();
    };
    const remove = () => {
      formApi == null ? void 0 : formApi.dispose();
      el.remove();
      if (lastFocus == null ? void 0 : lastFocus.isConnected) lastFocus.focus();
    };
    el.querySelector("[data-arc-dialog-close]").onclick = close;
    el.addEventListener("cancel", (e) => {
      if (formApi == null ? void 0 : formApi.pending) e.preventDefault();
    });
    el.addEventListener("close", remove, { once: true });
    formApi = bindForm(el.querySelector("form"), () => onSave(el), { error, onSuccess: () => {
      el.close();
    } });
    el.showModal();
    mount(el);
    return el;
  }
  function confirm({ title = translate("Confirmar"), message, confirmLabel = translate("Confirmar"), variant = "danger" } = {}) {
    return new Promise((resolve) => {
      let accepted = false;
      const el = dialog({ title, body: "<p>" + escapeHtml(message) + "</p>", saveLabel: confirmLabel, onSave: () => {
        accepted = true;
      } });
      const save = el.querySelector("[type=submit]");
      save.classList.remove("primary");
      save.classList.add(variant);
      el.addEventListener("close", () => resolve(accepted), { once: true });
    });
  }
  function tabs(items, active, { label = "Navegación", className = "" } = {}) {
    return `<div class="arcTabs ${escapeHtml(className)}" role="tablist" aria-label="${escapeHtml(translate(label))}">${items.map((item) => `<button class="arcButton secondary" role="tab" type="button" data-arc-tab="${escapeHtml(item.id)}" aria-selected="${item.id === active}" tabindex="${item.id === active ? 0 : -1}"${attr("aria-controls", item.panelId)}>${escapeHtml(translate(item.label))}</button>`).join("")}</div>`;
  }
  function bindTabs(root, onChange) {
    root.querySelectorAll("[role=tablist]").forEach((list) => {
      if (list.__arcTabs) return;
      list.__arcTabs = true;
      const choose = (tab) => {
        list.querySelectorAll("[role=tab]").forEach((n) => {
          n.setAttribute("aria-selected", String(n === tab));
          n.tabIndex = n === tab ? 0 : -1;
          const p = document.getElementById(n.getAttribute("aria-controls"));
          if (p) p.hidden = n !== tab;
        });
        tab.focus();
        onChange == null ? void 0 : onChange(tab.dataset.arcTab);
      };
      list.addEventListener("click", (e) => {
        const tab = e.target.closest("[role=tab]");
        if (tab) choose(tab);
      });
      list.addEventListener("keydown", (e) => {
        const choices = [...list.querySelectorAll("[role=tab]:not(:disabled)")], index = choices.indexOf(document.activeElement);
        if (index < 0) return;
        const next = { ArrowRight: (index + 1) % choices.length, ArrowLeft: (index + choices.length - 1) % choices.length, Home: 0, End: choices.length - 1 }[e.key];
        if (next != null) {
          e.preventDefault();
          choose(choices[next]);
        }
      });
    });
  }
  function sideDialog({ id, prefix, title, navLabel, tabs: tabs2 = [], panes = [], opener, onSelect = () => {
  }, onClose = () => {
  } }) {
    const el = document.createElement("dialog");
    el.className = "arcSideDialog";
    el.id = id;
    el.setAttribute("aria-labelledby", prefix + "Title");
    el.innerHTML = `<div class="arcSideDialogHead"><h2 id="${escapeHtml(prefix)}Title"><span data-gi-live>${escapeHtml(title)}</span></h2><button type="button" class="arcButton arcIconBtn" data-side-close data-gi-aria-label=aeccae342e4b aria-label="Cerrar" data-gi-aria-label="live"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg></button></div><div class="arcSideDialogBody"><nav class="arcSideNav" aria-label="${escapeHtml(navLabel)}" data-gi-aria-label="live"><div class="arcSideList" role="tablist" aria-orientation="vertical"></div></nav><div class="arcSidePanes">${panes.map((p) => `<div role="tabpanel" id="${escapeHtml(prefix)}Pane-${escapeHtml(p.id)}" data-side-pane="${escapeHtml(p.id)}" tabindex="0" hidden>${p.html || ""}</div>`).join("")}</div></div>`;
    const list = el.querySelector("[role=tablist]");
    list.__arcTabs = true;
    let items = [], selected = null;
    const badge2 = (s) => s.badge ? `<span class="arcSideBadge"${s.tone ? ` data-tone="${escapeHtml(s.tone)}"` : ""}>${escapeHtml(s.badge)}</span>` : "";
    const tab = (s) => `<button type="button" role="tab" id="${escapeHtml(prefix)}Tab-${escapeHtml(s.id)}" data-side-tab="${escapeHtml(s.id)}" aria-controls="${escapeHtml(prefix)}Pane-${escapeHtml(s.pane)}" aria-selected="false" tabindex="-1"><span class="arcSideIcon" aria-hidden="true"><svg viewBox="0 0 24 24">${s.icon || ""}</svg></span><span class="arcSideLabel" data-gi-live>${escapeHtml(s.label)}</span>${badge2(s)}</button>`;
    const button2 = (id2) => [...list.querySelectorAll("[data-side-tab]")].find((b) => b.dataset.sideTab === id2);
    const mark = () => list.querySelectorAll("[data-side-tab]").forEach((b) => {
      const on = b.dataset.sideTab === selected;
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
    });
    function setTabs(next) {
      var _a, _b, _c, _d, _e;
      const same = next.length === items.length && next.every((s, i) => s.id === items[i].id);
      items = next;
      if (same) {
        for (const s of next) {
          const b = button2(s.id);
          (_a = b.querySelector(".arcSideBadge")) == null ? void 0 : _a.remove();
          if (s.badge) b.insertAdjacentHTML("beforeend", badge2(s));
        }
        return;
      }
      const focused = list.contains(document.activeElement) ? document.activeElement.dataset.sideTab : null;
      list.innerHTML = next.map(tab).join("");
      (_c = (_b = window.GamaI18n) == null ? void 0 : _b.scan) == null ? void 0 : _c.call(_b, list);
      if (selected && !next.some((s) => s.id === selected)) select((_d = next[0]) == null ? void 0 : _d.id);
      else mark();
      if (focused) (_e = button2(focused)) == null ? void 0 : _e.focus();
    }
    function select(id2, { focus = false } = {}) {
      var _a;
      const s = items.find((x) => x.id === id2) || items[0];
      if (!s) return;
      selected = s.id;
      mark();
      el.querySelectorAll("[data-side-pane]").forEach((p) => {
        const on = p.dataset.sidePane === s.pane;
        p.hidden = !on;
        if (on) p.setAttribute("aria-labelledby", prefix + "Tab-" + s.id);
      });
      el.querySelector(".arcSidePanes").scrollTop = 0;
      if (focus) (_a = button2(s.id)) == null ? void 0 : _a.focus();
      onSelect(s);
    }
    list.addEventListener("click", (e) => {
      const b = e.target.closest("[data-side-tab]");
      if (b) select(b.dataset.sideTab);
    });
    list.addEventListener("keydown", (e) => {
      const all2 = [...list.querySelectorAll("[data-side-tab]")], i = all2.indexOf(document.activeElement);
      if (i < 0) return;
      const n = all2.length, next = { ArrowDown: (i + 1) % n, ArrowRight: (i + 1) % n, ArrowUp: (i + n - 1) % n, ArrowLeft: (i + n - 1) % n, Home: 0, End: n - 1 }[e.key];
      if (next == null) return;
      e.preventDefault();
      select(all2[next].dataset.sideTab, { focus: true });
    });
    const close = () => {
      if (el.open) el.close();
    };
    el.querySelector("[data-side-close]").onclick = close;
    window.addEventListener("arc:route-change", close);
    const api = { el, select, setTabs, close, get selected() {
      return selected;
    } };
    el.addEventListener("close", () => {
      var _a;
      window.removeEventListener("arc:route-change", close);
      el.remove();
      onClose(api);
      if (!document.querySelector("dialog[open]")) (_a = opener == null ? void 0 : opener.focus) == null ? void 0 : _a.call(opener);
    }, { once: true });
    document.body.appendChild(el);
    setTabs(tabs2);
    mount(el);
    el.showModal();
    return api;
  }
  function table({ columns, items, empty = translate("No hay resultados."), className = "", rowAttributes = () => "" }) {
    const titleIndex = columns.findIndex((c) => !c.decorative);
    const html = items.length ? items.map((item) => `<tr ${rowAttributes(item)}>${columns.map((col, i) => `<td data-col="${escapeHtml(col.decorative || col.actions ? "" : translate(col.label))}"${i === titleIndex ? " data-gama-title" : ""}${col.sortValue ? ` data-sort-value="${escapeHtml(col.sortValue(item) ?? "")}"${typeof col.sortValue(item) === "number" ? ' data-sort-type="number"' : ""}` : col.key && typeof item[col.key] === "number" ? ` data-sort-value="${item[col.key]}" data-sort-type="number"` : ""}${col.numeric ? ' class="arcNumeric"' : ""}>${col.html ? col.html(item) : escapeHtml(col.value ? col.value(item) : item[col.key] ?? "")}</td>`).join("")}</tr>`).join("") : `<tr><td colspan="${columns.length}" class="arcEmpty">${escapeHtml(empty)}</td></tr>`;
    return `<div class="arcTableWrap gamaTableBox" data-arc-table><table class="arcTable gamaCards ${escapeHtml(className)}"><thead><tr data-gama-head>${columns.map((col, i) => `<th scope="col" data-column-key="${escapeHtml(col.sort || col.key || String(i))}"${col.actions ? ' data-column-kind="actions"' : col.decorative ? ' data-column-kind="decorative"' : ""}${col.numeric ? ' class="arcNumeric"' : ""}>${col.sort ? `<button type="button" class="arcSort" data-arc-sort="${escapeHtml(col.sort)}">${escapeHtml(translate(col.label))} <span aria-hidden="true">⇅</span></button>` : escapeHtml(translate(col.label))}</th>`).join("")}</tr></thead><tbody>${html}</tbody></table></div>`;
  }
  function pager({ page: page2 = 0, pageSize = 20, total = 0 } = {}) {
    if (total <= pageSize) return "";
    const pages = Math.max(1, Math.ceil(total / pageSize));
    return `<div class="arcPager gamaPager">${button({ label: translate("‹ Anterior"), className: "gamaPagerBtn", disabled: page2 <= 0, attrs: 'data-arc-page="-1" data-page-prev' })}<span class="gamaPagerInfo" aria-live="polite">${total ? page2 * pageSize + 1 : 0}–${Math.min(total, (page2 + 1) * pageSize)} ${escapeHtml(translate("de"))} ${total} · ${page2 + 1} / ${pages}</span>${button({ label: translate("Siguiente ›"), className: "gamaPagerBtn", disabled: page2 >= pages - 1, attrs: 'data-arc-page="1" data-page-next' })}</div>`;
  }
  function dataTable(host, { columns, source, searchInput, searchControl = searchInput, actions = {}, empty, className = "", initial = {} }) {
    var _a;
    let disposed = false, generation = 0, timer;
    const saved = (_a = window.GamaTable) == null ? void 0 : _a.sourceSort(host);
    const state = { page: 0, pageSize: 20, search: "", ...initial, ...saved && columns.some((c) => c.sort === saved.col) ? { sort: saved.col, ascending: saved.dir !== "desc" } : {} };
    const sortBy = async (col, dir) => {
      var _a2, _b, _c;
      const active = document.activeElement, header2 = active == null ? void 0 : active.closest("th"), column = header2 == null ? void 0 : header2.cellIndex;
      (_a2 = window.GamaTable) == null ? void 0 : _a2.sourceSort(host, col ? { col, dir } : null);
      await refresh({ page: 0, sort: col || initial.sort, ascending: col ? dir !== "desc" : initial.ascending !== false });
      if (column != null && document.activeElement === document.body) {
        const next = (_b = host.querySelector("thead tr")) == null ? void 0 : _b.cells[column];
        (_c = (next == null ? void 0 : next.querySelector("button")) || next) == null ? void 0 : _c.focus({ preventScroll: true });
      }
    };
    async function refresh(patch = {}) {
      var _a2;
      Object.assign(state, patch);
      const token = ++generation;
      host.setAttribute("aria-busy", "true");
      if (!host.firstElementChild) host.innerHTML = '<p role="status">' + escapeHtml(translate("Cargando…")) + "</p>";
      try {
        const result = await source({ ...state });
        if (disposed || token !== generation || !host.isConnected) return;
        if (result.total > 0 && state.page * state.pageSize >= result.total) {
          return refresh({ page: Math.max(0, Math.ceil(result.total / state.pageSize) - 1) });
        }
        host.innerHTML = table({ columns, items: result.items, empty, className }) + pager(result);
        (_a2 = window.GamaTable) == null ? void 0 : _a2.bind(host.querySelector("table"), { get: () => state.sort ? { col: state.sort, dir: state.ascending === false ? "desc" : "asc" } : null, set: sortBy, column: (_, i) => columns[i].sort ?? null, search: { input: searchControl, get: () => state.search, set: scheduleSearch } });
        mount(host);
      } catch (e) {
        if (!disposed && token === generation) {
          host.innerHTML = '<p role="alert">' + escapeHtml(errorMessage(e)) + "</p>" + button({ label: translate("Reintentar"), attrs: "data-arc-retry" });
        }
      } finally {
        if (token === generation) host.removeAttribute("aria-busy");
      }
    }
    function click(e) {
      const b = e.target.closest("button");
      if (!b) return;
      if (b.hasAttribute("data-arc-page")) refresh({ page: Math.max(0, state.page + Number(b.dataset.arcPage)) });
      else if (b.hasAttribute("data-arc-sort")) sortBy(b.dataset.arcSort, state.sort === b.dataset.arcSort && state.ascending !== false ? "desc" : "asc");
      else if (b.hasAttribute("data-arc-retry")) refresh();
      else for (const [attribute, callback] of Object.entries(actions)) {
        if (b.hasAttribute(attribute)) {
          callback(b.getAttribute(attribute), b);
          break;
        }
      }
    }
    function scheduleSearch(value) {
      clearTimeout(timer);
      ++generation;
      state.search = value;
      timer = setTimeout(() => refresh({ page: 0, search: value }), 200);
    }
    const search = () => scheduleSearch(searchInput.value);
    host.addEventListener("click", click);
    searchInput == null ? void 0 : searchInput.addEventListener("input", search);
    refresh();
    return { refresh, state, dispose() {
      disposed = true;
      ++generation;
      clearTimeout(timer);
      host.removeEventListener("click", click);
      searchInput == null ? void 0 : searchInput.removeEventListener("input", search);
    } };
  }
  function documentLines(lines, { currency, quantity = "quantity", price = "unit_price", tax = "tax_rate" } = {}) {
    const amounts = lines.reduce((a, l) => {
      const sub = Number(l[quantity] || 0) * Number(l[price] || 0);
      a.subtotal += sub;
      a.tax += sub * Number(l[tax] || 0) / 100;
      return a;
    }, { subtotal: 0, tax: 0 });
    return { ...amounts, total: amounts.subtotal + amounts.tax, formattedTotal: format.money(amounts.subtotal + amounts.tax, currency) };
  }
  function mount(root = document) {
    var _a, _b, _c, _d, _e, _f, _g;
    root.querySelectorAll(".gamaStdBack").forEach((b) => {
      if (!b.__gamaBound) {
        b.__gamaBound = true;
        b.onclick = () => window.ArcRouter.show("mainmenu");
      }
    });
    root.querySelectorAll("label").forEach((label) => {
      var _a2;
      const control = label.querySelector("input,select,textarea") || (!label.htmlFor && ((_a2 = label.nextElementSibling) == null ? void 0 : _a2.matches("input,select,textarea")) ? label.nextElementSibling : null);
      if (control) {
        if (!control.id) control.id = "arc-control-" + ++sequence;
        if (!label.htmlFor) label.htmlFor = control.id;
      }
    });
    bindTabs(root);
    (_b = (_a = window.GamaTable) == null ? void 0 : _a.scan) == null ? void 0 : _b.call(_a, root);
    (_d = (_c = window.GamaSelectSearch) == null ? void 0 : _c.scan) == null ? void 0 : _d.call(_c, root);
    (_e = window.gamaApplyAccess) == null ? void 0 : _e.call(window);
    (_g = (_f = window.GamaI18n) == null ? void 0 : _f.scan) == null ? void 0 : _g.call(_f, root);
  }
  function render(element, html) {
    element.innerHTML = html;
    mount(element);
    const section = element.closest("section[id]");
    if (section) window.dispatchEvent(new CustomEvent("arc:module-rendered", { detail: { id: section.id } }));
    return html;
  }
  const ui = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
    __proto__: null,
    badge,
    bindForm,
    bindTabs,
    button,
    confirm,
    dataTable,
    dialog,
    documentLines,
    field,
    form,
    guard,
    header,
    headerIcon,
    kpi,
    mount,
    pager,
    panel,
    render,
    sideDialog,
    table,
    tabs,
    toolbar
  }, Symbol.toStringTag, { value: "Module" }));
  const text = (value) => value ?? "";
  const number = (value) => Number(value ?? 0);
  const productFromRow = (p) => ({
    id: p.id,
    name: text(p.name),
    barcode: text(p.barcode),
    reference: text(p.reference),
    category: text(p.category),
    description: text(p.description),
    family: text(p.family),
    lines: text(p.lines),
    brand: text(p.brand),
    presentation: text(p.presentation),
    location: text(p.location),
    supplierId: p.supplier_id || null,
    minStock: number(p.min_stock),
    maxStock: number(p.max_stock),
    qtyPerCarton: number(p.qty_per_carton),
    weightG: number(p.weight_g),
    volumeCm3: number(p.volume_cm3),
    stock: number(p.stock),
    salePrice: number(p.sale_price),
    salePriceB: number(p.sale_price_b),
    purchasePrice: number(p.purchase_price),
    taxRate: Number(p.tax_rate ?? 15),
    productKind: p.product_kind || "goods",
    baseUnit: text(p.base_unit),
    orderMinimum: number(p.order_minimum),
    orderMultiple: number(p.order_multiple),
    lotTracking: !!p.lot_tracking,
    lotTrackingSince: text(p.lot_tracking_since),
    createdAt: text(p.created_at),
    updatedAt: text(p.updated_at),
    active: p.active !== false,
    hasPhoto: !!(p.has_photo || p.photo_data),
    photo: text(p.photo_data)
  });
  const customerFromRow = (c) => ({ id: c.id, taxId: text(c.identification), identificationKind: c.identification_kind || "auto", name: text(c.name), category: c.category || "A", address: text(c.address), phone: text(c.phone), email: text(c.email), city: text(c.city), province: text(c.province), postalCode: text(c.postal_code), country: text(c.country), notes: text(c.notes), paymentTermsDays: c.payment_terms_days ?? null, lat: c.lat ?? null, lng: c.lng ?? null, active: c.active !== false });
  const supplierFromRow = (s) => ({ id: s.id, taxId: text(s.tax_id), identificationKind: s.identification_kind || "auto", name: text(s.name), contactName: text(s.contact_name), address: text(s.address), phone: text(s.phone), email: text(s.email), city: text(s.city), province: text(s.province), postalCode: text(s.postal_code), country: text(s.country), notes: text(s.notes), active: s.active !== false });
  const supplierToRow = (s) => ({ name: s.name, tax_id: s.taxId || null, identification_kind: s.identificationKind || "auto", contact_name: s.contactName || null, address: s.address || null, phone: s.phone || null, email: s.email || null, city: s.city || null, province: s.province || null, postal_code: s.postalCode || null, country: s.country || null, notes: s.notes || null, active: s.active !== false });
  const formatAddress = (c = {}) => [...new Set([c.address, c.city, c.province, c.postalCode ?? c.postal_code, c.country].map((v) => String(v ?? "").trim()).filter(Boolean))].join(", ");
  const legacyProduct = (p) => {
    const x = productFromRow(p);
    return { ...x, ref: x.reference, cat: x.category, loc: x.location, min: x.minStock, qtyCarton: x.qtyPerCarton, price: x.salePrice, purchase_price: x.purchasePrice, iva: x.taxRate, supplierId: x.supplierId || "" };
  };
  const legacyCustomer = (c) => {
    const x = customerFromRow(c);
    return { ...x, cloudId: x.id, id: x.taxId, idType: "RUC" };
  };
  const legacySupplier = (s) => {
    const x = supplierFromRow(s);
    return { ...x, tax: x.taxId, contact: x.contactName };
  };
  const entities = {
    suppliers: { table: "suppliers", select: "id,name,tax_id,contact_name,phone,email,city,address,province,postal_code,country,notes,active,created_at,updated_at", order: "name", search: ["name", "tax_id", "contact_name", "email", "phone", "city"], fromRow: supplierFromRow, toRow: supplierToRow },
    customers: { table: "customers", select: "id,name,identification,category,address,phone,email,city,province,postal_code,country,notes,payment_terms_days,lat,lng,active,created_at,updated_at", order: "name", search: ["name", "identification", "email", "phone", "city"], fromRow: customerFromRow },
    products: { table: "products", select: "id,barcode,name,description,reference,category,family,lines,brand,presentation,location,supplier_id,min_stock,max_stock,qty_per_carton,weight_g,volume_cm3,stock,sale_price,sale_price_b,purchase_price,tax_rate,active,has_photo,product_kind,base_unit,order_minimum,order_multiple,lot_tracking,lot_tracking_since,created_at,updated_at", order: "name", search: ["name", "barcode", "reference", "category"], fromRow: productFromRow }
  };
  const supplierFields = [
    { id: "supName", key: "name", label: "Nombre / razón social", required: true, maxLength: 300 },
    { id: "supTax", key: "taxId", label: "RUC / identificación", maxLength: 100 },
    { id: "supContact", key: "contactName", label: "Persona de contacto", maxLength: 200 },
    { id: "supPhone", key: "phone", label: "Teléfono", type: "tel", maxLength: 80 },
    { id: "supEmail", key: "email", label: "Email", type: "email", maxLength: 250 },
    { id: "supCity", key: "city", label: "Ciudad", maxLength: 200 },
    { id: "supAddress", key: "address", label: "Dirección", maxLength: 500 },
    { id: "supNotes", key: "notes", label: "Observaciones", type: "textarea", maxLength: 4e3 }
  ];
  const entities$1 = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
    __proto__: null,
    customerFromRow,
    entities,
    formatAddress,
    legacyCustomer,
    legacyProduct,
    legacySupplier,
    productFromRow,
    supplierFields,
    supplierFromRow,
    supplierToRow
  }, Symbol.toStringTag, { value: "Module" }));
  const cache = /* @__PURE__ */ new Map();
  const cloud = () => {
    if (!window.GamaCloud) throw Error("NETWORK_ERROR");
    return window.GamaCloud;
  };
  function invalidate(table2) {
    for (const key of cache.keys()) if (!table2 || key.startsWith(table2 + ":")) cache.delete(key);
  }
  async function all(table2, options = {}, cached = false) {
    const key = table2 + ":" + JSON.stringify(options);
    if (cached && cache.has(key)) return cache.get(key);
    const pending = (async () => {
      const data2 = [], seen = /* @__PURE__ */ new Set();
      let offset = 0;
      for (let page2 = 0; page2 < 1e4; page2++) {
        const r = await cloud().list(table2, { ...options, order: options.order || "id", range: [offset, offset + 199] });
        if (r.error) return r;
        const rows = r.data || [];
        if (!rows.length) return { data: data2, error: null };
        const signature = JSON.stringify(rows.map((row) => row.id ?? row));
        if (seen.has(signature)) throw Error("PAGINATION_RANGE_IGNORED");
        seen.add(signature);
        data2.push(...rows);
        offset += rows.length;
        if (typeof r.count === "number" && offset >= r.count) return { data: data2, error: null };
      }
      throw Error("PAGINATION_LIMIT");
    })();
    if (cached) cache.set(key, pending);
    try {
      const r = await pending;
      if (r.error && cache.get(key) === pending) cache.delete(key);
      return r;
    } catch (e) {
      if (cache.get(key) === pending) cache.delete(key);
      throw e;
    }
  }
  async function byIds(table2, column, ids, options = {}, cached = false) {
    if (!/^[_a-z][_a-z0-9]*$/.test(column)) throw Error("INVALID_FILTER_COLUMN");
    const keys = [...new Set(ids)], data2 = [];
    for (let i = 0; i < keys.length; i += 100) {
      const result = await all(table2, { ...options, in: { ...options.in, [column]: keys.slice(i, i + 100) } }, cached);
      if (result.error) return result;
      data2.push(...result.data);
    }
    return { data: data2, error: null };
  }
  async function page(entity, options = {}) {
    const schema = entities[entity];
    if (!schema) throw Error("UNKNOWN_ENTITY");
    const size = Math.min(100, Math.max(1, Number(options.pageSize) || 20)), index = Math.max(0, Number(options.page) || 0);
    const order = options.sort || schema.order;
    if (!schema.select.split(",").includes(order)) throw Error("INVALID_SORT");
    const request = { select: schema.select, count: "exact", order, ascending: options.ascending !== false, eq: { active: options.archived !== true }, range: [index * size, (index + 1) * size - 1] };
    const term = String(options.search || "").trim();
    if (term) request.search = { columns: schema.search, value: term };
    const result = await cloud().list(schema.table, request);
    if (result.error) throw result.error;
    if (typeof result.count !== "number") throw Error("COUNT_REQUIRED");
    return { items: (result.data || []).map(schema.fromRow), total: result.count, page: index, pageSize: size, sort: order };
  }
  async function rpc(name, data2 = {}) {
    const r = await rawRpc(name, data2);
    if (r.error) {
      const e = new Error(r.error.message || "UNKNOWN_ERROR");
      Object.assign(e, r.error, { details: normalizeError(r.error) });
      throw e;
    }
    return r.data;
  }
  async function rawRpc(name, data2 = {}) {
    const started = performance.now();
    let success = false;
    try {
      const r = await (await cloud().db()).rpc(name, data2);
      success = !r.error;
      return r;
    } finally {
      if (name !== "gama_operational_metrics") window.dispatchEvent(new CustomEvent("arc:metric", { detail: { metric: "rpc", operation: name, duration_ms: Math.round(performance.now() - started), success } }));
    }
  }
  const action = (domain, operation, data2 = {}) => rpc("gama_" + domain + "_action", { p_action: operation, p_data: data2 });
  function startDataEvents() {
    window.addEventListener("gama:data-change", (event) => {
      var _a;
      return invalidate((_a = event.detail) == null ? void 0 : _a.table);
    });
    window.addEventListener("gama:auth-change", () => invalidate());
    window.addEventListener("gama:products-cloud-change", () => invalidate("products"));
    window.addEventListener("gama:stock-cloud-change", () => {
      invalidate("products");
      invalidate("stock_quants");
      invalidate("stock_movements");
      invalidate("stock_reservations");
    });
    window.addEventListener("gama:sales-change", () => {
      invalidate("invoices");
      invalidate("invoice_lines");
      invalidate("customers");
    });
  }
  const data = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
    __proto__: null,
    action,
    all,
    byIds,
    invalidate,
    page,
    rawRpc,
    rpc,
    startDataEvents
  }, Symbol.toStringTag, { value: "Module" }));
  const definitions = [
    { id: "surveys", label: "Encuestas", icon: "checklist", group: "Ventas", description: "Cuestionarios, respuestas y satisfacción", accent: "teal", order: 7.2, menu: true, roles: ["admin", "commercial"] },
    { id: "sri", label: "Facturación SRI", icon: "invoice", group: "Administración", description: "Facturas electrónicas, autorización SRI y archivo XML / RIDE", accent: "orange", order: 15.1, menu: true, roles: ["admin"] },
    { id: "website", label: "Sitio web", icon: "globe", group: "Administración", description: "Catálogo web, presentación y solicitudes de prueba", accent: "teal", order: 16.5, menu: true, roles: ["admin"] },
    { id: "sav", label: "Reclamaciones", icon: "headset", group: "Ventas", description: "Reclamaciones, garantías y seguimiento", accent: "violet", order: 7.1, menu: false, tabOf: "returns", roles: ["admin", "commercial"] },
    { id: "documents", label: "Documentos", icon: "documents", group: "Administración", description: "Archivos, contratos y versiones", accent: "blue", order: 14.1, menu: true, roles: ["admin", "commercial", "magasinier"] },
    {
      "id": "tms",
      "label": "TMS",
      "icon": "truck",
      "group": "Logística",
      "description": "Preparación, rutas y pruebas de entrega",
      "accent": "teal",
      "order": 5,
      "menu": true,
      "configLabel": "TMS",
      "roles": [
        "admin",
        "magasinier"
      ]
    },
    {
      "id": "accounting",
      "label": "Contabilidad",
      "icon": "ledger",
      "group": "Administración",
      "description": "Seguimiento financiero y contabilidad",
      "accent": "orange",
      "order": 15,
      "menu": true,
      "configLabel": "Contabilidad",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "fleet",
      "label": "Gestión de flota",
      "icon": "car",
      "group": "Administración",
      "description": "Vehículos, papeles y consumos",
      "accent": "teal",
      "order": 100,
      "menu": true,
      "configLabel": "Gestión de flota",
      "roles": [
        "admin"
      ]
    },
    {
      "id": "projects",
      "label": "Proyectos",
      "icon": "project",
      "group": "Administración",
      "description": "Gestión de proyectos",
      "accent": "blue",
      "order": 12,
      "menu": true,
      "configLabel": "Proyectos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "assistant-ia",
      "label": "Agent Coco",
      "icon": "cocoBot",
      "group": "Resumen",
      "description": "Conversación e informes de análisis semanales para tu empresa",
      "accent": "blue",
      "order": 1,
      "menu": true,
      "configLabel": "Agent Coco",
      "roles": [
        "admin"
      ]
    },
    {
      "id": "dashboard",
      "label": "Panel de control",
      "icon": "chart",
      "group": "Resumen",
      "description": "Vista de conjunto de tu actividad",
      "accent": "blue",
      "order": 0,
      "menu": true,
      "configLabel": "Panel de control y análisis",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ],
      "header": [
        "Panel de control",
        "Toda la analítica del negocio en una pantalla."
      ]
    },
    {
      "id": "notifications",
      "label": "Notificaciones",
      "icon": "bell",
      "group": "Resumen",
      "description": "Avisos y bloqueos pendientes",
      "accent": "blue",
      "order": 100,
      "menu": true,
      "topbar": true,
      "configLabel": "Notificaciones y bloqueos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "knowledge",
      "label": "Base de conocimientos",
      "icon": "knowledge",
      "group": "Administración",
      "description": "Base de conocimientos",
      "accent": "blue",
      "order": 14,
      "menu": true,
      "configLabel": "Base de conocimientos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "products",
      "label": "Productos",
      "icon": "cube",
      "group": "Inventario y compras",
      "description": "Catálogo y fichas de producto",
      "accent": "teal",
      "order": 10,
      "menu": true,
      "configLabel": "Productos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ],
      "header": [
        "Productos",
        "Crea tus productos y consulta el catálogo."
      ]
    },
    {
      "id": "warehouses",
      "label": "Almacenes y existencias",
      "icon": "warehouse",
      "group": "Inventario y compras",
      "description": "Existencias y ubicaciones",
      "accent": "teal",
      "order": 11,
      "menu": true,
      "configLabel": "Almacenes y existencias",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "movement",
      "label": "Entradas / Salidas",
      "icon": "move",
      "group": "Inventario y compras",
      "description": "Entradas y salidas de mercancía",
      "accent": "teal",
      "order": 100,
      "menu": false,
      "retired": true,
      "configLabel": "Entradas / Salidas",
      "roles": [],
      "header": [
        "Movimientos",
        "Registra entradas y salidas de mercancía."
      ]
    },
    {
      "id": "gamaPurchasesV14",
      "label": "Compras",
      "icon": "cart",
      "group": "Inventario y compras",
      "description": "Pedidos de compra y recepciones",
      "accent": "teal",
      "order": 8,
      "menu": true,
      "configLabel": "Compras",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "matrix",
      "tabOf": "quotes",
      "label": "Matriz comercial",
      "icon": "matrix",
      "group": "Ventas",
      "description": "Precios de compra y de venta",
      "accent": "teal",
      "order": 100,
      "menu": true,
      "configLabel": "Matriz comercial",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "barcode",
      "label": "Códigos de barras",
      "icon": "barcode",
      "group": "Inventario y compras",
      "description": "Etiquetas y códigos de barras",
      "accent": "teal",
      "order": 100,
      "menu": true,
      "configLabel": "Códigos de barras",
      "roles": [
        "admin",
        "magasinier"
      ],
      "header": [
        "Códigos de barras",
        "Genera códigos de barras para imprimir."
      ]
    },
    {
      "id": "quotes",
      "label": "Ventas",
      "icon": "sales",
      "group": "Ventas",
      "description": "Solicitudes, presupuestos, pedidos, facturas y tarifas",
      "accent": "violet",
      "order": 3,
      "menu": true,
      "configLabel": "Ventas",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "contacts",
      "label": "Contactos",
      "icon": "users",
      "group": "Administración",
      "description": "Clientes, proveedores y prospectos",
      "accent": "violet",
      "order": 16,
      "menu": true,
      "configLabel": "Contactos",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "dossier-flow",
      "label": "Seguimiento de procesos",
      "icon": "folder",
      "group": "Resumen",
      "description": "Ventas, compras y devoluciones de clientes y proveedores",
      "accent": "blue",
      "order": 100,
      "menu": true,
      "configLabel": "Seguimiento de procesos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "sales-orders",
      "tabOf": "quotes",
      "label": "Pedidos de venta",
      "icon": "bag",
      "group": "Ventas",
      "description": "Gestión y seguimiento de pedidos",
      "accent": "violet",
      "order": 4,
      "menu": false,
      "configLabel": "Pedidos de venta",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "payments",
      "tabOf": "quotes",
      "label": "Facturas y cobros",
      "icon": "banknote",
      "group": "Ventas",
      "description": "Registro de facturas y cobros",
      "accent": "violet",
      "order": 6,
      "menu": false,
      "configLabel": "Pagos de clientes",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "returns",
      "label": "Devoluciones y posventa",
      "icon": "returnArrow",
      "group": "Logística",
      "description": "Devoluciones, abonos y reembolsos",
      "accent": "teal",
      "order": 7,
      "menu": true,
      "configLabel": "Devoluciones y posventa",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "crm",
      "label": "CRM",
      "icon": "handshake",
      "group": "Ventas",
      "description": "Prospectos y oportunidades",
      "accent": "violet",
      "order": 2,
      "menu": true,
      "configLabel": "CRM",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "price-lists",
      "tabOf": "quotes",
      "label": "Tarifas",
      "icon": "tag",
      "group": "Ventas",
      "description": "Tarifas y precios especiales",
      "accent": "violet",
      "order": 100,
      "menu": true,
      "configLabel": "Tarifas",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "reports",
      "settingsTab": "reports",
      "label": "Importar datos",
      "icon": "spreadsheet",
      "group": "Administración",
      "description": "Importar datos desde Excel",
      "accent": "blue",
      "order": 100,
      "menu": false,
      "configLabel": "Importar datos",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "hr",
      "label": "Recursos humanos",
      "icon": "badge",
      "group": "Administración",
      "description": "Equipos, ausencias y nóminas",
      "accent": "orange",
      "order": 13,
      "menu": true,
      "configLabel": "Recursos humanos",
      "roles": [
        "admin",
        "commercial",
        "magasinier",
        "rh"
      ]
    },
    {
      "id": "audit",
      "label": "Auditoría",
      "icon": "audit",
      "group": "Administración",
      "description": "Las acciones importantes, quién y cuándo",
      "accent": "orange",
      "order": 100,
      "menu": true,
      "configLabel": "Auditoría",
      "roles": [
        "admin"
      ],
      "header": [
        "Auditoría",
        "Stock, cobros y pagos, facturas, validaciones y accesos."
      ]
    },
    {
      "id": "users",
      "settingsTab": "users",
      "label": "Usuarios",
      "icon": "user",
      "group": "Administración",
      "description": "Cuentas y perfiles",
      "accent": "orange",
      "order": 100,
      "menu": false,
      "configLabel": "Usuarios y accesos",
      "roles": [
        "admin"
      ]
    },
    {
      "id": "access-settings",
      "settingsTab": "access-settings",
      "label": "Parámetros de acceso",
      "icon": "lock",
      "group": "Administración",
      "description": "Permisos por perfil",
      "accent": "orange",
      "order": 100,
      "menu": false,
      "configLabel": "Parámetros de acceso",
      "locked": true,
      "roles": [
        "admin"
      ]
    },
    {
      "id": "settings",
      "label": "Configuración",
      "icon": "gears",
      "group": "Administración",
      "description": "Configuración del ERP",
      "accent": "orange",
      "order": 17,
      "menu": true,
      "topbar": true,
      "configLabel": "Configuración",
      "locked": true,
      "roles": [
        "admin",
        "commercial",
        "magasinier",
        "rh"
      ]
    },
    {
      "id": "backup",
      "settingsTab": "backup",
      "label": "Copias de seguridad",
      "icon": "cloud",
      "group": "Administración",
      "description": "Copias de seguridad de tus datos",
      "accent": "orange",
      "order": 100,
      "menu": false,
      "configLabel": "Copias de seguridad",
      "roles": [
        "admin"
      ],
      "header": [
        "Copias de seguridad",
        "Exporta tus datos y guarda copias de la base."
      ]
    },
    {
      "id": "billing",
      "label": "Formulario anterior de presupuestos",
      "description": "Presupuestos para tus clientes, en PDF.",
      "menu": false,
      "retired": true,
      "configLabel": "Formulario anterior de presupuestos",
      "roles": [
        "admin",
        "commercial"
      ],
      "header": [
        "Presupuestos",
        "Presupuestos para tus clientes, en PDF."
      ]
    }
  ];
  const groups = ["Resumen", "Inventario y compras", "Ventas", "Administración", "Logística"];
  const aliases = { menu: "mainmenu", inicio: "mainmenu", movements: "movement", operations: "dashboard", "order-preparation": "tms", clients: "contacts", suppliers: "contacts", stock: "warehouses" };
  const roleAliases = { administrador: "admin", comercial: "commercial", almacenero: "magasinier", rrhh: "rh" };
  const roles = Object.fromEntries([["admin", "Administrador"], ["commercial", "Comercial"], ["magasinier", "Almacenero"], ["rh", "Responsable RH"]].map(([id, label]) => [id, { label, perms: id === "admin" ? "*" : definitions.filter((m) => m.roles.includes(id)).map((m) => m.id).concat(id === "commercial" ? ["customer-requests"] : []) }]));
  const tabsOf = (id) => definitions.filter((m) => m.tabOf === id).map((m) => m.id);
  const canOpen = (id) => {
    var _a;
    return !!((_a = window.gamaAccessAllowed) == null ? void 0 : _a.call(window, id)) || tabsOf(id).some((t) => {
      var _a2;
      return (_a2 = window.gamaAccessAllowed) == null ? void 0 : _a2.call(window, t);
    });
  };
  const openers = {
    matrix: () => {
      var _a;
      return (_a = window.GamaMatrix) == null ? void 0 : _a.open();
    },
    surveys: () => {
      var _a;
      return (_a = window.GamaSurveys) == null ? void 0 : _a.open();
    },
    website: () => {
      var _a;
      return (_a = window.GamaWebsite) == null ? void 0 : _a.open();
    },
    contacts: (from) => {
      var _a;
      return (_a = window.GamaContacts) == null ? void 0 : _a.open(from);
    },
    sav: () => {
      var _a;
      return (_a = window.GamaService) == null ? void 0 : _a.open();
    },
    documents: () => {
      var _a;
      return (_a = window.GamaDocuments) == null ? void 0 : _a.open();
    },
    tms: () => {
      var _a;
      return (_a = window.gamaTMS) == null ? void 0 : _a.open();
    },
    accounting: () => {
      var _a;
      return (_a = window.GamaAccounting) == null ? void 0 : _a.open();
    },
    sri: () => {
      var _a;
      return (_a = window.GamaAccounting) == null ? void 0 : _a.openSri();
    },
    fleet: () => {
      var _a;
      return (_a = window.GamaFleet) == null ? void 0 : _a.open();
    },
    returns: () => {
      var _a, _b, _c;
      return ((_a = window.gamaAccessAllowed) == null ? void 0 : _a.call(window, "returns")) ? (_b = window.GamaReturns) == null ? void 0 : _b.open() : (_c = window.GamaService) == null ? void 0 : _c.open();
    },
    projects: () => {
      var _a;
      return (_a = window.GamaProjects) == null ? void 0 : _a.open();
    },
    "assistant-ia": () => {
      var _a;
      return (_a = window.GamaAssistant) == null ? void 0 : _a.open();
    },
    knowledge: () => {
      var _a;
      return (_a = window.GamaKnowledge) == null ? void 0 : _a.open();
    },
    payments: () => {
      var _a;
      return (_a = window.GamaPayments) == null ? void 0 : _a.open();
    },
    "dossier-flow": () => {
      var _a;
      return (_a = window.GamaDossierFlow) == null ? void 0 : _a.open();
    },
    notifications: () => {
      var _a;
      return (_a = window.GamaOperations) == null ? void 0 : _a.open("notifications");
    },
    quotes: () => {
      var _a;
      return (_a = window.GamaQuotes) == null ? void 0 : _a.enter();
    },
    "sales-orders": () => {
      var _a;
      return (_a = window.GamaSales) == null ? void 0 : _a.open();
    },
    reports: () => {
      var _a;
      return (_a = window.GamaSettings) == null ? void 0 : _a.open("reports");
    },
    backup: () => {
      var _a;
      return (_a = window.GamaSettings) == null ? void 0 : _a.open("backup");
    },
    gamaPurchasesV14: () => {
      var _a;
      if (window.gamaShowPurchases) return window.gamaShowPurchases();
      (_a = window.showTab) == null ? void 0 : _a.call(window, "gamaPurchasesV14", null);
      setTimeout(() => {
        var _a2;
        return (_a2 = window.gamaShowPurchases) == null ? void 0 : _a2.call(window);
      }, 100);
    },
    crm: () => {
      var _a, _b;
      (_a = window.showTab) == null ? void 0 : _a.call(window, "crm", null);
      return (_b = window.GamaOpenCRM) == null ? void 0 : _b.call(window);
    },
    "price-lists": () => {
      var _a, _b;
      (_a = window.showTab) == null ? void 0 : _a.call(window, "price-lists", null);
      return (_b = window.GamaOpenPriceLists) == null ? void 0 : _b.call(window);
    },
    warehouses: () => {
      var _a, _b;
      (_a = window.showTab) == null ? void 0 : _a.call(window, "warehouses", null);
      return (_b = window.GamaOpenWarehouses) == null ? void 0 : _b.call(window);
    },
    hr: () => {
      var _a;
      return (_a = window.GamaOpenHR) == null ? void 0 : _a.call(window);
    },
    "access-settings": () => {
      var _a;
      return (_a = window.GamaOpenAccessSettings) == null ? void 0 : _a.call(window);
    },
    settings: () => {
      var _a;
      return (_a = window.GamaOpenSettings) == null ? void 0 : _a.call(window);
    }
  };
  function openModule(id, from) {
    var _a, _b, _c;
    if (window.ArcRuntimeLoaded === false) return window.ArcEnsureRuntime().then(() => openModule(id, from));
    if (window.gamaAccessAllowed && !canOpen(id)) return;
    if (window.GamaModules && !window.GamaModules.enabled(id)) {
      (_b = window.gamaToast) == null ? void 0 : _b.call(window, ((_a = window.GamaI18n) == null ? void 0 : _a.t("Este módulo está desactivado en Configuración.")) || "Este módulo está desactivado en Configuración.");
      return;
    }
    return openers[id] ? openers[id](from) : (_c = window.showTab) == null ? void 0 : _c.call(window, id, null);
  }
  const registry = definitions.map((m) => Object.freeze({ ...m, open: (from) => openModule(m.id, from) }));
  const hooks = /* @__PURE__ */ new Map();
  let current = "mainmenu", cleanups = [];
  function unmount() {
    const callbacks = cleanups;
    cleanups = [];
    for (const callback of callbacks) callback();
  }
  const canonical = (id) => aliases[id] || id;
  const emit = (type, detail) => window.dispatchEvent(new CustomEvent(type, { detail }));
  function allowed(id) {
    return id === "mainmenu" || (!window.gamaAccessAllowed ? false : canOpen(id === "gama-tms-section" ? "tms" : id));
  }
  function refuse(id) {
    var _a, _b, _c, _d;
    if (window.gamaAccessAllowed) {
      const message = ((_a = window.GamaModules) == null ? void 0 : _a.enabled(id)) === false ? "Este módulo está desactivado en Configuración." : "Acceso denegado para este perfil.";
      (_d = window.gamaToast) == null ? void 0 : _d.call(window, ((_c = (_b = window.GamaI18n) == null ? void 0 : _b.t) == null ? void 0 : _c.call(_b, message)) || message);
    }
    return false;
  }
  function onEnter(id, fn) {
    const key = canonical(id);
    if (!hooks.has(key)) hooks.set(key, /* @__PURE__ */ new Set());
    hooks.get(key).add(fn);
    return () => {
      var _a;
      return (_a = hooks.get(key)) == null ? void 0 : _a.delete(fn);
    };
  }
  function show(id, button2) {
    var _a, _b, _c, _d, _e, _f, _g;
    id = canonical(id);
    if (!allowed(id)) return refuse(id);
    const settingsTab = (_a = registry.find((m) => m.id === id)) == null ? void 0 : _a.settingsTab;
    if (settingsTab) return (_b = window.GamaSettings) == null ? void 0 : _b.open(settingsTab);
    if (id === "customer-requests") {
      (_c = window.GamaQuotes) == null ? void 0 : _c.openRequests();
      return false;
    }
    unmount();
    if (current !== id) emit("arc:route-leave", { id: current });
    for (const hook of hooks.get(id) || []) {
      const result = hook({ id, button: button2 });
      if (typeof result === "function") cleanups.push(result);
    }
    const target = document.getElementById(id);
    if (!target) return false;
    document.querySelectorAll("section").forEach((section) => {
      if (section.closest("dialog")) return;
      const active = section === target;
      section.classList.toggle("active", active);
      section.style.setProperty("display", active ? "block" : "none", "important");
      if (active) section.removeAttribute("hidden");
    });
    document.querySelectorAll(".tab").forEach((tab) => tab.classList.toggle("active", tab === button2));
    current = id;
    (_d = window.renderForRoute) == null ? void 0 : _d.call(window, id);
    (_e = window.ArcStandardHeaders) == null ? void 0 : _e.call(window, target);
    (_g = (_f = window.ArcUI) == null ? void 0 : _f.headerIcon) == null ? void 0 : _g.call(_f, target, id);
    mount(target);
    emit("arc:route-change", { id });
    window.scrollTo({ top: 0, behavior: "smooth" });
    return true;
  }
  function open(id) {
    const requested = id;
    id = canonical(id);
    if (!allowed(id)) return refuse(id);
    const definition = registry.find((m) => m.id === id), started = performance.now();
    const record = (success) => emit("arc:metric", { metric: "navigation", module: id, operation: "open", duration_ms: Math.round(performance.now() - started), success });
    try {
      const result = (definition == null ? void 0 : definition.open) ? definition.open(requested) : show(id);
      if (result == null ? void 0 : result.then) return result.then((r) => {
        record(true);
        return r;
      }, (e) => {
        record(false);
        throw e;
      });
      record(result !== false);
      return result;
    } catch (e) {
      record(false);
      throw e;
    }
  }
  function startRouter() {
    window.addEventListener("gama:modules-change", () => {
      if (!allowed(current)) show("mainmenu");
    });
    window.addEventListener("gama:auth-change", () => {
      unmount();
      if (!allowed(current)) show("mainmenu");
    });
  }
  const router = { show, open, onEnter, get current() {
    return current;
  } };
  const views = /* @__PURE__ */ new Map();
  const $ = (id) => document.getElementById(id);
  const directoryColumns = {
    products: [
      { label: "Foto", decorative: true, html: (p) => {
        var _a;
        return ((_a = window.gamaPhotoCell) == null ? void 0 : _a.call(window, legacyProduct({ id: p.id, name: p.name, has_photo: p.hasPhoto }))) || "";
      } },
      { key: "barcode", label: "Código", sort: "barcode" },
      { key: "name", label: "Producto", sort: "name" },
      { key: "reference", label: "Referencia", sort: "reference" },
      { key: "family", label: "Familia", sort: "family" },
      { key: "category", label: "Categoría", sort: "category" },
      { key: "lines", label: "Líneas", sort: "lines" },
      { key: "brand", label: "Marca", sort: "brand" },
      { key: "presentation", label: "Presentación", sort: "presentation" },
      { key: "description", label: "Descripción", sort: "description" },
      { key: "productKind", label: "Tipo de producto", sort: "product_kind", value: (p) => translate(p.productKind === "service" ? "Servicio" : "Artículo almacenado") },
      { key: "baseUnit", label: "Unidad base", sort: "base_unit" },
      { key: "location", label: "Ubicación", sort: "location" },
      { label: "Proveedor", sort: "supplier_name", value: (p) => {
        var _a;
        return ((_a = (window.ArcEntities.suppliersCache || []).find((s) => s.id === p.supplierId)) == null ? void 0 : _a.name) || "—";
      } },
      ...[["stock", "Stock", "stock"], ["minStock", "Stock mínimo", "min_stock"], ["maxStock", "Stock máximo", "max_stock"], ["orderMinimum", "Pedido mínimo", "order_minimum"], ["orderMultiple", "Múltiplo de pedido", "order_multiple"], ["qtyPerCarton", "Cantidad por cartón", "qty_per_carton"], ["weightG", "Peso (g)", "weight_g"], ["volumeCm3", "Volumen (cm³)", "volume_cm3"]].map(([key, label, sort]) => ({ key, label, sort, numeric: true, value: (p) => format.number(p[key]) })),
      { label: "Precio compra", sort: "purchase_price", value: (p) => format.money(p.purchasePrice), numeric: true },
      { label: "Venta A", value: (p) => format.money(p.salePrice), numeric: true, sort: "sale_price" },
      { label: "Venta B", sort: "sale_price_b", value: (p) => format.money(p.salePriceB), numeric: true },
      { label: "IVA", sort: "tax_rate", value: (p) => format.number(p.taxRate) + " %" },
      { key: "lotTracking", label: "Seguimiento por lotes", sort: "lot_tracking", value: (p) => translate(p.lotTracking ? "Sí" : "No") },
      { key: "lotTrackingSince", label: "Seguimiento activado el", sort: "lot_tracking_since", value: (p) => format.date(p.lotTrackingSince) },
      { key: "active", label: "Estado", sort: "active", value: (p) => translate(p.active ? "Activo" : "Archivado") },
      { key: "createdAt", label: "Fecha de creación", sort: "created_at", value: (p) => format.date(p.createdAt) },
      { key: "updatedAt", label: "Última modificación", sort: "updated_at", value: (p) => format.date(p.updatedAt) },
      { label: "Acciones", actions: true, html: (p) => button({ label: translate("Unidades e historial"), attrs: 'data-product-controls="' + escapeHtml(p.id) + '"' }) + " " + (p.active ? button({ label: translate("Editar"), attrs: 'data-edit="' + escapeHtml(p.id) + '"' }) + " " + button({ label: translate("Archivar"), variant: "danger", attrs: 'data-archive="' + escapeHtml(p.id) + '"' }) : button({ label: translate("Editar"), attrs: 'data-edit="' + escapeHtml(p.id) + '"' }) + " " + button({ label: translate("Restaurar"), attrs: 'data-restore="' + escapeHtml(p.id) + '"' }) + " " + button({ label: translate("Borrar definitivamente"), variant: "danger", attrs: 'data-delete="' + escapeHtml(p.id) + '"' })) }
    ]
  };
  function directory(entity, filter = "") {
    var _a, _b;
    if (entity !== "products") return;
    if (!((_a = window.gamaAccessAllowed) == null ? void 0 : _a.call(window, "products"))) {
      (_b = views.get(entity)) == null ? void 0 : _b.dispose();
      views.delete(entity);
      return;
    }
    const key = "products", host = $("productsTable");
    if (!host) return;
    const prior = views.get(entity);
    if ((prior == null ? void 0 : prior.host) === host && host.firstElementChild) {
      prior.refresh(filter);
      return;
    }
    prior == null ? void 0 : prior.dispose();
    host.innerHTML = "<div data-arc-archive></div><div data-arc-directory></div>";
    let rows = /* @__PURE__ */ new Map(), lastFilter = filter, lastArchived;
    const grid = dataTable(host.querySelector("[data-arc-directory]"), { columns: directoryColumns[entity], searchControl: $("productSearch"), initial: { search: filter }, source: async (request) => {
      const archived = window.GamaArchive.mode(key) === "archived";
      lastArchived = archived;
      let result;
      if (request.sort === "supplier_name") {
        const schema = window.ArcEntities.entities.products;
        const term = String(request.search || "").trim();
        const loaded = await all(entity, { select: schema.select, eq: { active: !archived }, ...term ? { search: { columns: schema.search, value: term } } : {} }, true);
        if (loaded.error) throw loaded.error;
        const names = new Map((window.ArcEntities.suppliersCache || []).map((s) => [s.id, s.name]));
        const items = loaded.data.map(schema.fromRow).sort((a, b) => window.GamaTable.compare(names.get(a.supplierId), names.get(b.supplierId), request.ascending === false ? "desc" : "asc"));
        result = { items: items.slice(request.page * request.pageSize, (request.page + 1) * request.pageSize), total: items.length, page: request.page, pageSize: request.pageSize };
      } else result = await page(entity, { ...request, archived });
      rows = new Map(result.items.map((x) => [x.id, x]));
      const other = await window.GamaCloud.list(entity, { select: "id", count: "exact", head: true, eq: { active: archived } });
      if (other.error) throw other.error;
      host.querySelector("[data-arc-archive]").innerHTML = window.GamaArchive.tabs(key, archived ? other.count : result.total, archived ? result.total : other.count);
      return result;
    }, actions: { "data-product-controls": (id) => window.ArchitectProductsControls.open(id), "data-edit": (id) => {
      const row = rows.get(id);
      if (row) window.editProduct(row.barcode, row.id);
    }, "data-archive": (id) => {
      const row = rows.get(id);
      if (row) window.deleteProduct(row.barcode);
    }, "data-restore": (id) => window.restoreProduct(id), "data-delete": (id) => window.purgeProduct(id) } });
    const onChange = (e) => {
      var _a2;
      if (((_a2 = e.detail) == null ? void 0 : _a2.table) === entity) grid.refresh();
    };
    window.addEventListener("gama:data-change", onChange);
    const view = { host, refresh(search) {
      const archived = window.GamaArchive.mode(key) === "archived";
      const changed = search !== lastFilter || archived !== lastArchived;
      lastFilter = search;
      grid.refresh(changed ? { page: 0, search } : {});
    }, dispose() {
      grid.dispose();
      window.removeEventListener("gama:data-change", onChange);
    } };
    window.GamaArchive.register(key, () => grid.refresh({ page: 0 }));
    views.set(entity, view);
  }
  const lazyModules = {
    "price-lists": { "global": "gamaPriceLists", "file": "gama-price-lists.js", "methods": ["open"], "aliases": { "GamaOpenPriceLists": "open" } },
    "matrix": { "global": "GamaMatrix", "file": "gama-proveedores-matriz.js", "methods": ["open", "render"], "apis": { "GamaSuppliers": ["migrate"] } },
    "workflow-tools": { "global": "CocoFlows", "file": "coco-flow-tools.js", "methods": ["draftBills", "projectTime", "importSupplierXml", "messages"] },
    "automation": { "global": "CocoAutomation", "file": "coco-automation.js", "methods": ["mount"] },
    "dashboard": { "global": "ArchitectDashboard", "file": "architect-dashboard.js", "dependencies": ["architect-kpi-catalog.js", "architect-home-kpis.js"], "methods": ["refresh"], "apis": { "ArchitectHomeKpis": ["refresh"] } },
    "crm": { "styles": ["coco-style-crm-core.css", "coco-style-crm-activities.css", "coco-style-crm-contacts.css", "coco-style-crm-leads.css", "coco-style-crm-opportunities.css", "coco-style-crm-reports.css", "coco-style-crm-targets.css"], "global": "GamaCRM", "file": "gama-crm-core.js", "extensions": ["gama-crm-scoring.js", "gama-crm-leads.js", "gama-crm-opportunities.js", "gama-crm-activities.js", "gama-crm-contacts.js", "gama-crm-reports.js", "gama-crm-targets.js"], "methods": ["open", "ir"], "aliases": { "GamaOpenCRM": "open" }, "apis": { "GamaCRMLeads": ["open"], "GamaCRMOpportunities": ["open", "openRecord"], "GamaCRMActivities": ["open"], "GamaCRMContacts": ["open"], "GamaCRMReports": ["open"] } },
    "hr-operations": { "styles": ["coco-style-hr-operations.css"], "global": "GamaHRP1", "file": "gama-hr-p1.js", "methods": ["mountFinance", "load"] },
    "hr": { "styles": ["coco-style-hr.css", "coco-style-hr-operations.css"], "global": "GamaHR", "file": "gama-hr.js", "dependencies": ["gama-hr-p1.js"], "methods": ["open", "load"], "aliases": { "GamaOpenHR": "open" } },
    "dossier-flow": { "styles": ["coco-style-dossier-flow.css"], "global": "GamaDossierFlow", "file": "gama-dossier-flow.js", "methods": ["open", "attachHistory"] },
    "gamaPurchasesV14": { "styles": ["coco-style-purchases.css"], "global": "GamaPurchases", "file": "gama-purchases-v14.js", "methods": ["open", "openOrder", "openDossier", "fromProject", "prepareAction", "prepareSupplierOffer"], "aliases": { "gamaShowPurchases": "open", "gamaOpenPurchaseV14": "openOrder", "gamaOpenPurchaseDossier": "openDossier", "gamaCreateProjectPurchase": "fromProject", "gamaPrepareActionPurchase": "prepareAction", "gamaPrepareSupplierOffer": "prepareSupplierOffer" } },
    "warehouses": { "styles": ["coco-style-inventory.css"], "global": "GamaInventoryV2", "file": "gama-stock-workspace.js", "methods": ["abrir", "openCount", "openAdjustments", "cargar"] },
    "surveys": { "global": "GamaSurveys", "file": "gama-surveys.js", "dependencies": ["gama-survey-form.js"], "methods": ["open"] },
    "website": {
      "global": "GamaWebsite",
      "file": "gama-website.js",
      "methods": [
        "open"
      ]
    },
    "audit-controls": {
      "global": "ArchitectStockAudit",
      "file": "architect-audit-controls.js",
      "methods": [
        "products",
        "valuation",
        "performance"
      ]
    },
    "sav": {
      "global": "GamaService",
      "file": "gama-service-documents.js",
      "methods": [
        "open",
        "openTicket"
      ]
    },
    "documents": {
      "global": "GamaDocuments",
      "file": "gama-service-documents.js",
      "methods": [
        "open"
      ]
    },
    "accounting": {
      "styles": ["coco-style-accounting.css"],
      "global": "GamaAccounting",
      "file": "gama-accounting.js",
      "dependencies": ["gama-sri-documents.js"],
      "methods": [
        "openSri",
        "mountSriConfig",
        "open",
        "rpc"
      ]
    },
    "fleet": {
      "styles": ["coco-style-fleet.css"],
      "global": "GamaFleet",
      "file": "gama-fleet.js",
      "methods": [
        "open",
        "openVehicle",
        "openDriver",
        "rpc"
      ]
    },
    "returns": {
      "styles": ["coco-style-returns.css"],
      "global": "GamaReturns",
      "file": "gama-returns.js",
      "dependencies": ["gama-sri-documents.js"],
      "methods": [
        "open",
        "openReturn",
        "createFrom",
        "createFromService",
        "rpc",
        "mount"
      ]
    },
    "knowledge": {
      "global": "GamaKnowledge",
      "file": "gama-knowledge.js",
      "methods": [
        "open",
        "openArticle"
      ]
    },
    "assistant-ia": {
      "global": "GamaAssistant",
      "file": "gama-assistant-ia.js",
      "methods": [
        "open"
      ]
    },
    "tms": {
      "styles": ["coco-style-tms-module.css"],
      "global": "gamaTMS",
      "file": "gama-tms-module.js",
      "dependencies": ["gama-tms-delivery-operations.js", "gama-sri-documents.js"],
      "methods": [
        "open",
        "openDelivery",
        "openProof",
        "viewProofArchive",
        "downloadProofReport",
        "downloadProofCertificate"
      ]
    },
    "projects": { "global": "GamaProjects", "file": "gama-projects.js", "dependencies": ["gama-projects-core.js"], "methods": ["open", "fromSource"] }
  };
  const scripts = /* @__PURE__ */ new Map();
  const styles = /* @__PURE__ */ new Map();
  const modules = /* @__PURE__ */ new Map(), prepared = /* @__PURE__ */ new Set();
  const filesFor = (entry) => [...entry.dependencies || [], entry.file, ...entry.extensions || []];
  function prepareModule(id) {
    var _a, _b;
    const entry = lazyModules[id];
    if (!entry) return;
    for (const file of filesFor(entry)) {
      if (prepared.has(file) || scripts.has(file)) continue;
      prepared.add(file);
      const link = document.createElement("link");
      link.rel = "preload";
      link.as = "script";
      link.href = ((_a = window.ArcAssets) == null ? void 0 : _a[file]) || file;
      document.head.appendChild(link);
    }
    for (const file of entry.styles || []) {
      if (prepared.has(file)) continue;
      prepared.add(file);
      const link = document.createElement("link");
      link.rel = "preload";
      link.as = "style";
      link.href = ((_b = window.ArcAssets) == null ? void 0 : _b[file]) || file;
      document.head.appendChild(link);
    }
  }
  function loadStyle(file) {
    if (styles.has(file)) return styles.get(file);
    const pending = new Promise((resolve, reject) => {
      var _a;
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = ((_a = window.ArcAssets) == null ? void 0 : _a[file]) || file;
      link.dataset.arcAsset = file;
      link.onload = resolve;
      link.onerror = () => {
        link.remove();
        styles.delete(file);
        reject(Error("MODULE_LOAD_FAILED"));
      };
      document.head.appendChild(link);
    });
    styles.set(file, pending);
    return pending;
  }
  function loadScript(file, options = {}) {
    if (scripts.has(file)) return scripts.get(file);
    const pending = new Promise((resolve, reject) => {
      var _a;
      const script = document.createElement("script");
      script.async = options.ordered !== true;
      script.src = ((_a = window.ArcAssets) == null ? void 0 : _a[file]) || file;
      script.dataset.arcAsset = file;
      for (const key of ["integrity", "crossOrigin", "referrerPolicy"])
        if (options[key]) script[key] = options[key];
      script.onload = () => options.validate && !options.validate() ? script.onerror() : resolve();
      script.onerror = () => {
        script.remove();
        scripts.delete(file);
        reject(Error("MODULE_LOAD_FAILED"));
      };
      document.head.appendChild(script);
    });
    scripts.set(file, pending);
    return pending;
  }
  async function loadModule(id) {
    const entry = lazyModules[id];
    if (!entry) return;
    if (modules.has(id)) return modules.get(id);
    const installed = window[entry.global];
    if (installed && !installed.__arcLazy && !entry.extensions) {
      await Promise.all((entry.styles || []).map(loadStyle));
      return installed;
    }
    prepareModule(id);
    const pending = (async () => {
      var _a, _b;
      const css = Promise.all((entry.styles || []).map(loadStyle));
      css.catch(() => {
      });
      if (window.ArcRuntimeLoaded === false) await window.ArcEnsureRuntime();
      if ((_a = entry.dependencies) == null ? void 0 : _a.length) await Promise.all(entry.dependencies.map((file) => loadScript(file, { ordered: true })));
      await loadScript(entry.file);
      if ((_b = entry.extensions) == null ? void 0 : _b.length) await Promise.all(entry.extensions.map((file) => loadScript(file, { ordered: true })));
      await css;
      const api = window[entry.global];
      if (!api || api.__arcLazy) throw Error("MODULE_LOAD_FAILED");
      return api;
    })();
    modules.set(id, pending);
    try {
      return await pending;
    } catch (error) {
      if (modules.get(id) === pending) modules.delete(id);
      throw error;
    }
  }
  function installLazyModules() {
    for (const [id, entry] of Object.entries(lazyModules)) {
      if (window[entry.global]) continue;
      window[entry.global] = {
        __arcLazy: true,
        ...Object.fromEntries(
          entry.methods.map((method) => [
            method,
            async (...args) => {
              var _a, _b;
              try {
                return await (await loadModule(id))[method](...args);
              } catch (e) {
                (_b = window.gamaToast) == null ? void 0 : _b.call(window, ((_a = window.ArcErrors) == null ? void 0 : _a.message(e)) || e.message);
                throw e;
              }
            }
          ])
        )
      };
      for (const [name, method] of Object.entries(entry.aliases || {}))
        window[name] = (...args) => window[entry.global][method](...args);
      for (const [name, methods] of Object.entries(entry.apis || {})) {
        if (window[name]) continue;
        window[name] = { __arcLazy: true, ...Object.fromEntries(methods.map((method) => [
          method,
          async (...args) => {
            await loadModule(id);
            return window[name][method](...args);
          }
        ])) };
      }
    }
  }
  function startPerformance() {
    const entries = [], start = performance.now();
    let samples = [], epoch = 0, pending = false;
    const capture = (detail) => {
      var _a, _b, _c, _d;
      if (!((_b = (_a = window.GamaRoleAccess) == null ? void 0 : _a.isReady) == null ? void 0 : _b.call(_a))) return;
      const module = detail.module || ((_c = window.ArcRouter) == null ? void 0 : _c.current) || "mainmenu";
      if (!/^[a-zA-Z0-9_-]{1,64}$/.test(module) || !/^[a-zA-Z0-9_-]{0,64}$/.test(detail.operation || "")) return;
      samples.push({ metric: detail.metric, module, operation: detail.operation || "", duration_ms: Math.min(3e5, Math.max(0, detail.duration_ms || 0)), success: detail.success !== false, device: innerWidth < 768 ? "mobile" : "desktop", network: ((_d = navigator.connection) == null ? void 0 : _d.effectiveType) ? ["slow-2g", "2g"].includes(navigator.connection.effectiveType) ? "slow" : "normal" : "unknown" });
      if (samples.length > 100) samples.shift();
    };
    const flush = async () => {
      if (pending || document.hidden || !samples.length) return;
      pending = true;
      const token = epoch, batch = samples.splice(0, 50);
      try {
        const db = await window.GamaCloud.db();
        if (token === epoch) await db.rpc("gama_operational_metrics", { p_action: "record", p_data: { samples: batch } });
      } catch (_) {
      } finally {
        pending = false;
      }
    };
    window.addEventListener("arc:metric", (e) => capture(e.detail));
    document.addEventListener("click", (e) => {
      var _a, _b;
      if ((_b = (_a = e.target).closest) == null ? void 0 : _b.call(_a, "button,[role=button],a")) capture({ metric: "action", duration_ms: 1, success: true });
    }, { passive: true });
    window.addEventListener("gama:auth-change", (e) => {
      var _a;
      if (((_a = e.detail) == null ? void 0 : _a.event) === "TOKEN_REFRESHED") return;
      epoch++;
      samples = [];
    });
    setInterval(flush, 3e4);
    const record = (type, detail) => {
      entries.push({ type, at: Math.round(performance.now()), ...detail });
      if (entries.length > 100) entries.shift();
    };
    window.addEventListener("arc:route-change", (e) => record("navigation", { route: e.detail.id }));
    window.addEventListener("architect:route-data-ready", (e) => record("data", { route: e.detail.route, milliseconds: Math.round(e.detail.milliseconds), tables: e.detail.tables.length }));
    let measured = false;
    window.addEventListener("gama:modules-change", () => {
      var _a;
      if (!measured && ((_a = window.GamaRoleAccess) == null ? void 0 : _a.isReady())) {
        measured = true;
        record("access_ready", { milliseconds: Math.round(performance.now() - start) });
      }
    });
    window.ArchitectPerformance = { snapshot: () => ({ entries: entries.map((x) => ({ ...x })), resources: performance.getEntriesByType("resource").filter((r) => ["fetch", "xmlhttprequest", "script"].includes(r.initiatorType)).map((r) => ({ kind: r.initiatorType, milliseconds: Math.round(r.duration), bytes: r.transferSize || null })), navigation: performance.getEntriesByType("navigation").map((n) => ({ domContentLoaded: Math.round(n.domContentLoadedEventEnd), load: Math.round(n.loadEventEnd) })) }), open: async () => {
      const token = epoch, r = await window.ArcData.rpc("gama_operational_metrics", { p_action: "report" });
      if (token !== epoch) return;
      window.ArcUI.dialog({ title: "Rendimiento observado", saveLabel: "Cerrar", body: "<p>Últimos 7 días. El percentil 95 se calcula sobre mediciones reales; sin muestras no se estima. Los tiempos de navegación miden la apertura; los RPC miden la respuesta del servidor.</p>" + window.ArcUI.table({ columns: [{ key: "module", label: "Módulo" }, { key: "operation", label: "Operación" }, { key: "metric", label: "Medición" }, { key: "device", label: "Dispositivo" }, { key: "network", label: "Red" }, { key: "samples", label: "Muestras" }, { key: "p95_ms", label: "P95 (ms)" }, { key: "errors", label: "Errores" }], items: r.rows }), onSave: async () => {
      } });
    } };
  }
  window.ArcUI = { ...ui, icons, moduleIcon, esc: escapeHtml };
  window.ArcFormat = format;
  window.ArcErrors = { normalize: normalizeError, message: errorMessage };
  window.ArcData = data;
  window.ArcEntities = { ...entities$1 };
  window.ArcModules = { registry, groups, roles, aliases, roleAliases, tabsOf, get: (id) => registry.find((m) => m.id === (aliases[id] || id)) };
  window.ArcRouter = router;
  window.ArcDirectories = { directory };
  window.ArcLoad = loadModule;
  window.ArcLoadScript = loadScript;
  window.ArcPrefetch = prepareModule;
  const runtime = document.querySelector("script[data-arc-runtime]");
  window.ArcRuntimeLoaded = !runtime;
  window.ArcRuntimeReady = runtime ? new Promise((resolve, reject) => {
    runtime.addEventListener("load", () => {
      window.ArcRuntimeLoaded = true;
      resolve();
    }, { once: true });
    runtime.addEventListener("error", () => {
      window.ArcRuntimeFailed = true;
      reject(Error("MODULE_LOAD_FAILED"));
    }, { once: true });
  }) : Promise.resolve();
  window.ArcRuntimeReady.catch(() => {
  });
  window.ArcEnsureRuntime = () => window.ArcRuntimeLoaded ? Promise.resolve() : window.ArcRuntimeFailed ? loadScript("coco-modules.js", { validate: () => window.ArcRuntimeLoaded }) : window.ArcRuntimeReady;
  installLazyModules();
  router.onEnter("matrix", () => {
    window.GamaMatrix.render().catch(() => {
    });
  });
  router.onEnter("dashboard", () => {
    window.ArchitectDashboard.refresh().catch(() => {
    });
  });
  startDataEvents();
  startRouter();
  startPerformance();
})();
