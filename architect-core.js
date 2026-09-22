(function() {
  "use strict";
  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"'\\]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;", "\\": "&#92;" })[c]);
  const translate = (value) => {
    var _a, _b;
    return ((_b = (_a = window.GamaI18n) == null ? void 0 : _a.t) == null ? void 0 : _b.call(_a, value)) || value;
  };
  const format = {
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
    const e = normalizeError(error);
    const messages = { AUTH_REQUIRED: "Vuelve a iniciar sesión.", ROLE_NOT_ALLOWED: "Tu perfil no puede realizar esta operación.", PM_FORBIDDEN: "Tu perfil no puede realizar esta operación.", "23505": "Ya existe un registro con estos datos.", "23503": "Este registro está vinculado a otros documentos.", PM_CONFLICT: "Los datos cambiaron. Actualiza antes de guardar.", NETWORK_ERROR: "Comprueba la conexión y vuelve a intentarlo." };
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
    return `<div class="gamaStdHeader arcPageHeader" data-gama-standard-header="1"><span class="gamaStdIcon" data-arc-icon-slot${module ? ' data-arc-module="' + escapeHtml(module) + '"' : ""} aria-hidden="true"></span><div class="gamaStdText"><div class="gamaStdKicker">ARCHITECT ERP</div><h2>${escapeHtml(stripIcon(title))}</h2>${lead ? "<p>" + escapeHtml(lead) + "</p>" : ""}</div><div class="gamaStdActions">${button({ label: translate("← Volver al menú"), className: "gamaStdBack", attrs: 'aria-label="' + escapeHtml(translate("Volver al menú")) + '"' })}</div></div>`;
  }
  function headerIcon(root, id = "") {
    var _a;
    const scope = root && root.querySelectorAll ? root : document;
    const slots = scope.querySelectorAll(".gamaStdIcon[data-arc-icon-slot]");
    if (!slots.length) return;
    const modules = globalThis.ArcModules, icons2 = (_a = globalThis.ArcUI) == null ? void 0 : _a.icons;
    if (!modules || !icons2) return;
    let pending2 = false;
    slots.forEach((slot) => {
      const section = slot.closest("section[id]");
      const key = slot.dataset.arcModule || id || SECTION_ALIAS[section == null ? void 0 : section.id] || (section == null ? void 0 : section.id) || "";
      if (!key) {
        pending2 = true;
        return;
      }
      const definition = modules.get(key);
      const drawing = definition && icons2[definition.icon];
      if (!drawing) return;
      slot.dataset.arcFam = definition.accent || "cyan";
      slot.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">' + drawing + "</svg>";
      delete slot.dataset.arcIconSlot;
    });
    if (pending2 && !headerIcon.retrying) {
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
    let pending2 = false;
    const submit = async (event) => {
      event.preventDefault();
      if (pending2 || !el.reportValidity()) return;
      pending2 = true;
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
        pending2 = false;
        el.removeAttribute("aria-busy");
        controls.forEach((c, i) => c.disabled = previous[i]);
      }
    };
    el.addEventListener("submit", submit);
    const api = { get pending() {
      return pending2;
    }, dispose() {
      el.removeEventListener("submit", submit);
      delete el.__arcForm;
    } };
    el.__arcForm = api;
    return api;
  }
  function guard(action2) {
    let pending2;
    return function(...args) {
      if (pending2) return pending2;
      pending2 = Promise.resolve().then(() => action2.apply(this, args)).finally(() => {
        pending2 = void 0;
      });
      return pending2;
    };
  }
  function dialog({ title, body = "", saveLabel = translate("Guardar"), onSave, error = errorMessage, className = "", ids = {} }) {
    const el = document.createElement("dialog"), lastFocus = document.activeElement;
    const titleId = "arc-dialog-title-" + ++sequence;
    el.className = "arcDialog " + className;
    el.setAttribute("aria-labelledby", titleId);
    el.innerHTML = `<form class="arcForm"><h2 id="${titleId}">${escapeHtml(title)}</h2>${body}<p class="arcFormError gsError" role="alert"${attr("id", ids.error)}></p><div class="arcToolbar gsActions">${button({ id: ids.close, label: translate("Volver"), attrs: "data-arc-dialog-close" })}${button({ id: ids.save, type: "submit", variant: "primary", label: saveLabel })}</div></form>`;
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
  function table({ columns, items, empty = translate("No hay resultados."), className = "", rowAttributes = () => "" }) {
    const titleIndex = columns.findIndex((c) => !c.decorative);
    const html = items.length ? items.map((item) => `<tr ${rowAttributes(item)}>${columns.map((col, i) => `<td data-col="${escapeHtml(col.decorative || col.actions ? "" : translate(col.label))}"${i === titleIndex ? " data-gama-title" : ""}${col.numeric ? ' class="arcNumeric"' : ""}>${col.html ? col.html(item) : escapeHtml(col.value ? col.value(item) : item[col.key] ?? "")}</td>`).join("")}</tr>`).join("") : `<tr><td colspan="${columns.length}" class="arcEmpty">${escapeHtml(empty)}</td></tr>`;
    return `<div class="arcTableWrap gamaTableBox" data-arc-table><table class="arcTable gamaCards ${escapeHtml(className)}"><thead><tr data-gama-head>${columns.map((col) => `<th scope="col">${col.sort ? `<button type="button" class="arcSort" data-arc-sort="${escapeHtml(col.sort)}">${escapeHtml(translate(col.label))} <span aria-hidden="true">↕</span></button>` : escapeHtml(translate(col.label))}</th>`).join("")}</tr></thead><tbody>${html}</tbody></table></div>`;
  }
  function pager({ page: page2 = 0, pageSize = 20, total = 0 } = {}) {
    if (total <= pageSize) return "";
    const pages = Math.max(1, Math.ceil(total / pageSize));
    return `<div class="arcPager gamaPager">${button({ label: translate("‹ Anterior"), className: "gamaPagerBtn", disabled: page2 <= 0, attrs: 'data-arc-page="-1" data-page-prev' })}<span class="gamaPagerInfo" aria-live="polite">${total ? page2 * pageSize + 1 : 0}–${Math.min(total, (page2 + 1) * pageSize)} ${escapeHtml(translate("de"))} ${total} · ${page2 + 1} / ${pages}</span>${button({ label: translate("Siguiente ›"), className: "gamaPagerBtn", disabled: page2 >= pages - 1, attrs: 'data-arc-page="1" data-page-next' })}</div>`;
  }
  function dataTable(host, { columns, source, searchInput, actions = {}, empty, className = "", initial = {} }) {
    let disposed = false, generation = 0, timer;
    const state = { page: 0, pageSize: 20, search: "", ...initial };
    async function refresh(patch = {}) {
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
      else if (b.hasAttribute("data-arc-sort")) refresh({ page: 0, sort: b.dataset.arcSort, ascending: state.sort === b.dataset.arcSort ? !state.ascending : true });
      else if (b.hasAttribute("data-arc-retry")) refresh();
      else for (const [attribute, callback] of Object.entries(actions)) {
        if (b.hasAttribute(attribute)) {
          callback(b.getAttribute(attribute), b);
          break;
        }
      }
    }
    const search = () => {
      clearTimeout(timer);
      timer = setTimeout(() => refresh({ page: 0, search: searchInput.value }), 200);
    };
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
    table,
    tabs,
    toolbar
  }, Symbol.toStringTag, { value: "Module" }));
  const icons = {
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
    active: p.active !== false,
    hasPhoto: !!(p.has_photo || p.photo_data),
    photo: text(p.photo_data)
  });
  const customerFromRow = (c) => ({ id: c.id, taxId: text(c.identification), name: text(c.name), category: c.category || "A", address: text(c.address), phone: text(c.phone), email: text(c.email), city: text(c.city), province: text(c.province), notes: text(c.notes), paymentTermsDays: c.payment_terms_days ?? null, active: c.active !== false });
  const supplierFromRow = (s) => ({ id: s.id, taxId: text(s.tax_id), name: text(s.name), contactName: text(s.contact_name), address: text(s.address), phone: text(s.phone), email: text(s.email), city: text(s.city), province: text(s.province), postalCode: text(s.postal_code), country: text(s.country), notes: text(s.notes), active: s.active !== false });
  const supplierToRow = (s) => ({ name: s.name, tax_id: s.taxId || null, contact_name: s.contactName || null, address: s.address || null, phone: s.phone || null, email: s.email || null, city: s.city || null, province: s.province || null, postal_code: s.postalCode || null, country: s.country || null, notes: s.notes || null, active: s.active !== false });
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
    customers: { table: "customers", select: "id,name,identification,category,address,phone,email,city,province,notes,payment_terms_days,active,created_at,updated_at", order: "name", search: ["name", "identification", "email", "phone", "city"], fromRow: customerFromRow },
    products: { table: "products", select: "id,barcode,name,description,reference,category,family,lines,brand,presentation,location,supplier_id,min_stock,max_stock,qty_per_carton,weight_g,volume_cm3,stock,sale_price,sale_price_b,purchase_price,tax_rate,active,has_photo,created_at,updated_at", order: "name", search: ["name", "barcode", "reference", "category"], fromRow: productFromRow }
  };
  const supplierFields = [
    { id: "supName", key: "name", label: "Nombre / razón social", required: true, maxLength: 300 },
    { id: "supTax", key: "taxId", label: "RUC / identificación", maxLength: 100 },
    { id: "supContact", key: "contactName", label: "Persona de contacto", maxLength: 200 },
    { id: "supPhone", key: "phone", label: "Teléfono", type: "tel", maxLength: 80 },
    { id: "supEmail", key: "email", label: "Email", type: "email", maxLength: 250 },
    { id: "supCity", key: "city", label: "Ciudad / país", maxLength: 200 },
    { id: "supAddress", key: "address", label: "Dirección", maxLength: 500 },
    { id: "supNotes", key: "notes", label: "Información clave", type: "textarea", maxLength: 4e3 }
  ];
  const entities$1 = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
    __proto__: null,
    customerFromRow,
    entities,
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
    const pending2 = (async () => {
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
    if (cached) cache.set(key, pending2);
    try {
      const r = await pending2;
      if (r.error) cache.delete(key);
      return r;
    } catch (e) {
      cache.delete(key);
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
    return (await cloud().db()).rpc(name, data2);
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
      invalidate("stock_movements");
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
    { id: "sav", label: "Servicio posventa", icon: "headset", group: "Ventas", description: "Reclamaciones, garantías y seguimiento", accent: "orange", order: 7.1, menu: true, roles: ["admin", "commercial"] },
    { id: "documents", label: "Documentos", icon: "documents", group: "Administración", description: "Archivos, contratos y versiones", accent: "blue", order: 14.1, menu: true, roles: ["admin", "commercial", "magasinier"] },
    {
      "id": "tms",
      "label": "Entregas / TMS",
      "icon": "truck",
      "group": "Logística",
      "description": "Transporte y pruebas de entrega",
      "accent": "indigo",
      "order": 5,
      "menu": true,
      "configLabel": "Transporte y entregas",
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
      "accent": "indigo",
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
      "label": "Asistente IA",
      "icon": "sparkles",
      "group": "Resumen",
      "description": "Analiza tus datos y obtén respuestas",
      "accent": "pink",
      "order": 1,
      "menu": true,
      "configLabel": "Asistente IA",
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
      "accent": "cyan",
      "order": 0,
      "menu": true,
      "configLabel": "Panel de control y análisis",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ],
      "header": [
        "📈 Panel de control",
        "Toda la analítica del negocio en una pantalla."
      ]
    },
    {
      "id": "notifications",
      "label": "Notificaciones",
      "icon": "bell",
      "group": "Resumen",
      "description": "Avisos y bloqueos pendientes",
      "accent": "orange",
      "order": 100,
      "menu": true,
      "configLabel": "Notificaciones y bloqueos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "knowledge",
      "label": "Knowledge · Base de conocimientos",
      "icon": "knowledge",
      "group": "Administración",
      "description": "Base de conocimientos",
      "accent": "violet",
      "order": 14,
      "menu": true,
      "configLabel": "Knowledge · Base de conocimientos",
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
      "accent": "green",
      "order": 10,
      "menu": true,
      "configLabel": "Productos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ],
      "header": [
        "📦 Productos",
        "Crea tus productos y consulta el catálogo."
      ]
    },
    {
      "id": "warehouses",
      "label": "Almacenes y existencias",
      "icon": "warehouse",
      "group": "Inventario y compras",
      "description": "Existencias y ubicaciones",
      "accent": "blue",
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
      "accent": "cyan",
      "order": 100,
      "menu": true,
      "configLabel": "Entradas / Salidas",
      "roles": [
        "admin",
        "magasinier"
      ],
      "header": [
        "🔄 Movimientos",
        "Registra entradas y salidas de mercancía."
      ]
    },
    {
      "id": "stock",
      "label": "Inventario",
      "icon": "stock",
      "group": "Inventario y compras",
      "description": "Niveles de existencias disponibles",
      "accent": "green",
      "order": 100,
      "menu": true,
      "configLabel": "Inventario",
      "roles": [
        "admin",
        "magasinier"
      ],
      "header": [
        "📊 Inventario",
        "Las existencias de todos tus productos."
      ]
    },
    {
      "id": "gamaPurchasesV14",
      "label": "Compras",
      "icon": "cart",
      "group": "Inventario y compras",
      "description": "Pedidos de compra y recepciones",
      "accent": "cyan",
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
      "id": "suppliers",
      "label": "Proveedores",
      "icon": "factory",
      "group": "Inventario y compras",
      "description": "Gestión de los proveedores",
      "accent": "indigo",
      "order": 9,
      "menu": true,
      "configLabel": "Proveedores",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "matrix",
      "label": "Matriz comercial",
      "icon": "matrix",
      "group": "Inventario y compras",
      "description": "Precios de compra y de venta",
      "accent": "violet",
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
      "accent": "blue",
      "order": 100,
      "menu": true,
      "configLabel": "Códigos de barras",
      "roles": [
        "admin",
        "magasinier"
      ],
      "header": [
        "🏷️ Códigos de barras",
        "Genera códigos de barras para imprimir."
      ]
    },
    {
      "id": "quotes",
      "label": "Presupuestos y facturas",
      "icon": "invoice",
      "group": "Ventas",
      "description": "Crea y sigue tus presupuestos",
      "accent": "cyan",
      "order": 3,
      "menu": true,
      "configLabel": "Presupuestos y facturas",
      "roles": [
        "admin",
        "commercial",
        "client"
      ]
    },
    {
      "id": "client-deliveries",
      "label": "Mis entregas",
      "icon": "pin",
      "group": "Cliente",
      "description": "Tus entregas y sus pruebas",
      "accent": "indigo",
      "order": 100,
      "menu": true,
      "configLabel": "Mis entregas y pruebas",
      "roles": [
        "admin",
        "client"
      ]
    },
    {
      "id": "clients",
      "label": "Clientes",
      "icon": "users",
      "group": "Ventas",
      "description": "Base de clientes",
      "accent": "cyan",
      "order": 16,
      "menu": true,
      "configLabel": "Clientes",
      "roles": [
        "admin",
        "commercial"
      ],
      "header": [
        "👥 Clientes",
        "La ficha de cada cliente, en un solo sitio."
      ]
    },
    {
      "id": "dossier-flow",
      "label": "Seguimiento de procesos",
      "icon": "folder",
      "group": "Ventas",
      "description": "Venta (PDV) y compra (PDC), paso a paso",
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
      "label": "Pedidos de venta",
      "icon": "bag",
      "group": "Ventas",
      "description": "Gestión y seguimiento de pedidos",
      "accent": "red",
      "order": 4,
      "menu": true,
      "configLabel": "Pedidos de venta",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "payments",
      "label": "Facturas y cobros",
      "icon": "banknote",
      "group": "Ventas",
      "description": "Registro de facturas y cobros",
      "accent": "blue",
      "order": 6,
      "menu": true,
      "configLabel": "Pagos de clientes",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "order-preparation",
      "label": "Preparación de pedidos",
      "icon": "checklist",
      "group": "Logística",
      "description": "Preparación y pruebas de entrega",
      "accent": "green",
      "order": 100,
      "menu": true,
      "configLabel": "Preparación de pedidos",
      "roles": [
        "admin",
        "magasinier"
      ]
    },
    {
      "id": "returns",
      "label": "Devoluciones",
      "icon": "returnArrow",
      "group": "Logística",
      "description": "Devoluciones, abonos y reembolsos",
      "accent": "red",
      "order": 7,
      "menu": true,
      "configLabel": "Devoluciones",
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
      "accent": "blue",
      "order": 2,
      "menu": true,
      "configLabel": "CRM",
      "roles": [
        "admin",
        "commercial"
      ]
    },
    {
      "id": "client-catalog",
      "label": "Catálogo de productos",
      "icon": "catalog",
      "group": "Cliente",
      "description": "Catálogo para tus clientes",
      "accent": "cyan",
      "order": 100,
      "menu": true,
      "configLabel": "Catálogo de productos",
      "roles": [
        "admin",
        "client"
      ]
    },
    {
      "id": "price-lists",
      "label": "Tarifas",
      "icon": "tag",
      "group": "Ventas",
      "description": "Tarifas y precios especiales",
      "accent": "orange",
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
      "label": "Importar datos",
      "icon": "spreadsheet",
      "group": "Administración",
      "description": "Importar datos desde Excel",
      "accent": "green",
      "order": 100,
      "menu": true,
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
      "accent": "green",
      "order": 13,
      "menu": true,
      "configLabel": "Recursos humanos",
      "roles": [
        "admin",
        "commercial",
        "magasinier"
      ]
    },
    {
      "id": "audit",
      "label": "Auditoría",
      "icon": "audit",
      "group": "Administración",
      "description": "Historial de todas las operaciones",
      "accent": "cyan",
      "order": 100,
      "menu": true,
      "configLabel": "Auditoría",
      "roles": [
        "admin"
      ],
      "header": [
        "🔎 Auditoría",
        "Historial de todas las entradas y salidas."
      ]
    },
    {
      "id": "users",
      "label": "Usuarios",
      "icon": "user",
      "group": "Administración",
      "description": "Cuentas y perfiles",
      "accent": "blue",
      "order": 100,
      "menu": true,
      "configLabel": "Usuarios y accesos",
      "roles": [
        "admin"
      ]
    },
    {
      "id": "access-settings",
      "label": "Parámetros de acceso",
      "icon": "lock",
      "group": "Administración",
      "description": "Permisos por perfil",
      "accent": "violet",
      "order": 100,
      "menu": true,
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
      "accent": "indigo",
      "order": 17,
      "menu": true,
      "configLabel": "Configuración",
      "locked": true,
      "roles": [
        "admin",
        "commercial",
        "magasinier",
        "client"
      ]
    },
    {
      "id": "backup",
      "label": "Copias de seguridad",
      "icon": "cloud",
      "group": "Administración",
      "description": "Copias de seguridad de tus datos",
      "accent": "blue",
      "order": 100,
      "menu": true,
      "configLabel": "Copias de seguridad",
      "roles": [
        "admin"
      ],
      "header": [
        "💾 Copias de seguridad",
        "Exporta tus datos y guarda copias de la base."
      ]
    },
    {
      "id": "billing",
      "label": "Formulario anterior de presupuestos",
      "description": "Presupuestos para tus clientes, en PDF.",
      "menu": false,
      "configLabel": "Formulario anterior de presupuestos",
      "roles": [
        "admin",
        "commercial"
      ],
      "header": [
        "🧾 Presupuestos",
        "Presupuestos para tus clientes, en PDF."
      ]
    }
  ];
  const groups = ["Resumen", "Inventario y compras", "Ventas", "Cliente", "Administración", "Logística"];
  const aliases = { menu: "mainmenu", inicio: "mainmenu", movements: "movement", operations: "dashboard" };
  const roleAliases = { administrador: "admin", comercial: "commercial", almacenero: "magasinier", cliente: "client" };
  const roles = Object.fromEntries([["admin", "Administrador"], ["commercial", "Comercial"], ["magasinier", "Almacenero"], ["client", "Cliente"]].map(([id, label]) => [id, { label, perms: id === "admin" ? "*" : definitions.filter((m) => m.roles.includes(id)).map((m) => m.id).concat(id === "commercial" ? ["customer-requests"] : []) }]));
  function ensureExcelModule() {
    var _a;
    let section = document.getElementById("reports");
    if (!section) {
      section = document.createElement("section");
      section.id = "reports";
      (document.querySelector(".wrap") || document.body).appendChild(section);
    }
    section.innerHTML = '<div class="wrap"><div id="excel-import-module" data-module="excel"></div></div>';
    if (!document.getElementById("gamaExcelLoader")) {
      const s = document.createElement("script");
      s.id = "gamaExcelLoader";
      s.src = ((_a = window.ArcAssets) == null ? void 0 : _a["gama-excel-import-v1.js"]) || "gama-excel-import-v1.js";
      s.onload = () => window.GamaExcelImport && window.GamaExcelImport.render();
      s.onerror = () => {
        const h = document.getElementById("excel-import-module");
        if (h) h.innerHTML = '<div class="card"><h2 data-gi=63e31998d5d9>Importar datos</h2><p class="low" data-gi=2f9af44c4156>No se pudo cargar el módulo Excel. Recarga la aplicación.</p></div>';
      };
      document.head.appendChild(s);
    } else if (window.GamaExcelImport) window.GamaExcelImport.render();
  }
  function openLegacy(x) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x;
    if (window.gamaAccessAllowed && !window.gamaAccessAllowed(x[1])) return;
    if (x[1] === "sav") {
      return (_a = window.GamaService) == null ? void 0 : _a.open();
    }
    if (x[1] === "documents") {
      return (_b = window.GamaDocuments) == null ? void 0 : _b.open();
    }
    if (x[1] === "tms") {
      return (_c = window.gamaTMS) == null ? void 0 : _c.open("planning");
    }
    if (x[1] === "accounting") {
      return (_d = window.GamaAccounting) == null ? void 0 : _d.open();
    }
    if (x[1] === "fleet") {
      return (_e = window.GamaFleet) == null ? void 0 : _e.open();
    }
    if (x[1] === "returns") {
      return (_f = window.GamaReturns) == null ? void 0 : _f.open();
    }
    if (x[1] === "projects") {
      return (_g = window.GamaProjects) == null ? void 0 : _g.open();
    }
    if (x[1] === "assistant-ia") {
      return (_h = window.GamaAssistant) == null ? void 0 : _h.open();
    }
    if (x[1] === "knowledge") {
      return (_i = window.GamaKnowledge) == null ? void 0 : _i.open();
    }
    if (x[1] === "payments") {
      return (_j = window.GamaPayments) == null ? void 0 : _j.open();
    }
    if (x[1] === "order-preparation") {
      return (_k = window.GamaPreparation) == null ? void 0 : _k.open();
    }
    if (x[1] === "dossier-flow") {
      return (_l = window.GamaDossierFlow) == null ? void 0 : _l.open();
    }
    if (["operations", "notifications"].includes(x[1])) {
      return (_m = window.GamaOperations) == null ? void 0 : _m.open(x[1]);
    }
    if (x[1] === "quotes") {
      return (_n = window.GamaQuotes) == null ? void 0 : _n.open();
    }
    if (x[1] === "client-deliveries") {
      return (_o = window.GamaQuotes) == null ? void 0 : _o.deliveries();
    }
    if (x[1] === "sales-orders") {
      return (_p = window.GamaSales) == null ? void 0 : _p.open();
    }
    if (window.GamaModules && !window.GamaModules.enabled(x[1])) {
      alert("Este módulo está desactivado en Configuración.");
      return;
    }
    if (x[1] === "reports") {
      ensureExcelModule();
      window.showTab && window.showTab("reports", null);
      return;
    }
    if (x[1] === "gamaPurchasesV14") {
      if (window.gamaShowPurchases) window.gamaShowPurchases();
      else {
        window.showTab && window.showTab("gamaPurchasesV14", null);
        setTimeout(() => window.gamaShowPurchases && window.gamaShowPurchases(), 100);
      }
      return;
    }
    if (x[1] === "crm") {
      if (window.showTab) window.showTab("crm", null);
      (_q = window.GamaOpenCRM) == null ? void 0 : _q.call(window);
      return;
    }
    if (x[1] === "price-lists") {
      if (window.showTab) window.showTab("price-lists", null);
      (_r = window.GamaOpenPriceLists) == null ? void 0 : _r.call(window);
      return;
    }
    if (x[1] === "client-catalog") {
      if (window.showTab) window.showTab("client-catalog", null);
      (_s = window.GamaOpenClientCatalog) == null ? void 0 : _s.call(window);
      return;
    }
    if (x[1] === "customer-requests") {
      if (window.showTab) window.showTab("customer-requests", null);
      (_t = window.GamaOpenCustomerRequests) == null ? void 0 : _t.call(window);
      return;
    }
    if (x[1] === "warehouses") {
      if (window.showTab) window.showTab("warehouses", null);
      (_u = window.GamaOpenWarehouses) == null ? void 0 : _u.call(window);
      return;
    }
    if (x[1] === "hr") {
      (_v = window.GamaOpenHR) == null ? void 0 : _v.call(window);
      return;
    }
    if (x[1] === "access-settings") {
      (_w = window.GamaOpenAccessSettings) == null ? void 0 : _w.call(window);
      return;
    }
    if (x[1] === "settings") {
      (_x = window.GamaOpenSettings) == null ? void 0 : _x.call(window);
      return;
    }
    if (window.showTab) window.showTab(x[1], null);
  }
  const registry = definitions.map((m) => Object.freeze({ ...m, open: () => openLegacy([m.label, m.id, m.icon, m.group]) }));
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
    return id === "mainmenu" || (!window.gamaAccessAllowed ? false : window.gamaAccessAllowed(id === "gama-tms-section" ? "tms" : id));
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
    var _a, _b, _c, _d, _e;
    id = canonical(id);
    if (!allowed(id)) return refuse(id);
    if (id === "customer-requests") {
      (_a = window.GamaQuotes) == null ? void 0 : _a.openRequests();
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
    (_b = window.renderForRoute) == null ? void 0 : _b.call(window, id);
    (_c = window.ArcStandardHeaders) == null ? void 0 : _c.call(window, target);
    (_e = (_d = window.ArcUI) == null ? void 0 : _d.headerIcon) == null ? void 0 : _e.call(_d, target, id);
    mount(target);
    emit("arc:route-change", { id });
    window.scrollTo({ top: 0, behavior: "smooth" });
    return true;
  }
  function open(id) {
    id = canonical(id);
    if (!allowed(id)) return refuse(id);
    const definition = registry.find((m) => m.id === id);
    if (definition == null ? void 0 : definition.open) return definition.open();
    return show(id);
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
  const call = async (promise) => {
    const r = await promise;
    if (r.error) throw r.error;
    return r.data;
  };
  function suppliers(host) {
    var _a;
    (_a = views.get("suppliers")) == null ? void 0 : _a.dispose();
    host.innerHTML = `<div class="gamaPMGrid"><div class="arcPanel gamaPMForm"><h3 id="supFormTitle">${escapeHtml(translate("Nuevo proveedor"))}</h3><form id="supForm" class="arcForm"><div class="arcFormGrid">${supplierFields.map((field$1) => field(field$1)).join("")}</div>${toolbar(button({ id: "supSave", type: "submit", variant: "primary", label: translate("＋ Guardar proveedor") }) + button({ id: "supClear", label: translate("Limpiar") }))}<p id="supMsg" role="alert" class="arcFormError"></p></form></div><div class="arcPanel gamaPMForm"><h3>${escapeHtml(translate("Proveedores registrados"))}</h3>${field({ id: "supSearch", type: "search", label: "Buscar por nombre, ciudad, contacto..." })}<div id="supList"><div id="supArchive"></div><div id="supDataTable"></div></div></div></div>`;
    let editing = null, rows = /* @__PURE__ */ new Map();
    const form2 = $("supForm");
    const reset = () => {
      editing = null;
      form2.reset();
      $("supFormTitle").textContent = translate("Nuevo proveedor");
      $("supMsg").textContent = "";
    };
    $("supClear").onclick = reset;
    const columns = [{ key: "name", label: "Proveedor", sort: "name" }, { key: "taxId", label: "RUC / identificación", sort: "tax_id" }, { key: "contactName", label: "Persona de contacto" }, { key: "phone", label: "Teléfono" }, { key: "email", label: "Email" }, { key: "city", label: "Ciudad", sort: "city" }, { key: "address", label: "Dirección" }, { key: "notes", label: "Información clave" }, { label: "Acciones", actions: true, html: (s) => button({ label: translate("Historial"), attrs: 'data-partner="' + escapeHtml(s.id) + '"' }) + " " + (s.active ? button({ label: translate("✏️ Editar"), attrs: 'data-edit="' + escapeHtml(s.id) + '"' }) + " " + button({ label: translate("🗄️ Archivar"), variant: "danger", attrs: 'data-del="' + escapeHtml(s.id) + '"' }) : button({ label: translate("♻️ Restaurar"), attrs: 'data-restore="' + escapeHtml(s.id) + '"' }) + " " + button({ label: translate("🗑️ Borrar"), variant: "danger", attrs: 'data-purge="' + escapeHtml(s.id) + '"' })) }];
    const refresh = async () => {
      invalidate("suppliers");
      await grid.refresh({ page: 0 });
      window.dispatchEvent(new CustomEvent("gama:data-change", { detail: { table: "suppliers" } }));
    };
    const mutate = async (id, operation) => {
      var _a2;
      const supplier = rows.get(id);
      if (!supplier) return;
      if (operation === "archive" && !window.confirm(translate("¿Archivar al proveedor «") + supplier.name + "»?")) return;
      if (operation === "delete" && !window.confirm(translate("¿Borrar definitivamente a «") + supplier.name + "»?")) return;
      try {
        await call(operation === "delete" ? window.GamaCloud.remove("suppliers", id) : window.GamaCloud.update("suppliers", id, { active: operation === "restore" }));
        await refresh();
      } catch (e) {
        $("supMsg").textContent = ((_a2 = window.GamaArchive) == null ? void 0 : _a2.friendlyError(e, "supplier")) || errorMessage(e);
      }
    };
    const grid = dataTable($("supDataTable"), { columns, searchInput: $("supSearch"), source: async (request) => {
      const archived = window.GamaArchive.mode("suppliersDir") === "archived";
      const result = await page("suppliers", { ...request, archived });
      rows = new Map(result.items.map((s) => [s.id, s]));
      const count = await window.GamaCloud.list("suppliers", { select: "id", count: "exact", head: true, eq: { active: archived } });
      if (count.error) throw count.error;
      $("supArchive").innerHTML = window.GamaArchive.tabs("suppliersDir", archived ? count.count : result.total, archived ? result.total : count.count);
      return result;
    }, actions: { "data-product-controls": (id) => window.ArchitectProductsControls.open(id), "data-partner": (id) => window.ArchitectPartners.open("supplier", id), "data-del": (id) => mutate(id, "archive"), "data-restore": (id) => mutate(id, "restore"), "data-purge": (id) => mutate(id, "delete"), "data-edit": (id) => {
      editing = rows.get(id);
      if (!editing) return;
      for (const f of supplierFields) $(f.id).value = editing[f.key] || "";
      $("supFormTitle").textContent = translate("Editar proveedor");
      $("supName").focus();
    } } });
    window.GamaArchive.register("suppliersDir", () => grid.refresh({ page: 0 }));
    const formApi = bindForm(form2, async () => {
      const value = Object.fromEntries(supplierFields.map((f) => [f.key, $(f.id).value.trim()]));
      if (!value.name) throw Error(translate("El nombre del proveedor es obligatorio."));
      const payload = supplierToRow({ ...editing, ...value, active: (editing == null ? void 0 : editing.active) !== false });
      if (!editing) for (const key of ["country", "province", "postal_code"]) delete payload[key];
      await call(editing ? window.GamaCloud.update("suppliers", editing.id, payload) : window.GamaCloud.insert("suppliers", payload));
      reset();
      await refresh();
    });
    const view = { dispose() {
      grid.dispose();
      formApi.dispose();
    } };
    views.set("suppliers", view);
    mount(host);
    return () => view.dispose();
  }
  const directoryColumns = {
    products: [
      { label: "Foto", decorative: true, html: (p) => {
        var _a;
        return ((_a = window.gamaPhotoCell) == null ? void 0 : _a.call(window, legacyProduct({ id: p.id, name: p.name, has_photo: p.hasPhoto }))) || "";
      } },
      { key: "barcode", label: "Código", sort: "barcode" },
      { key: "name", label: "Producto", sort: "name" },
      { key: "brand", label: "Marca" },
      { key: "stock", label: "Stock", numeric: true, sort: "stock" },
      { label: "Precio compra", value: (p) => format.money(p.purchasePrice), numeric: true },
      { label: "Venta A", value: (p) => format.money(p.salePrice), numeric: true, sort: "sale_price" },
      { label: "Venta B", value: (p) => format.money(p.salePriceB), numeric: true },
      { label: "IVA", value: (p) => format.number(p.taxRate) + " %" },
      { key: "location", label: "Ubicación" },
      { label: "Proveedor", value: (p) => {
        var _a;
        return ((_a = (window.ArcEntities.suppliersCache || []).find((s) => s.id === p.supplierId)) == null ? void 0 : _a.name) || "—";
      } },
      { label: "Acciones", actions: true, html: (p) => button({ label: translate("Unidades e historial"), attrs: 'data-product-controls="' + escapeHtml(p.id) + '"' }) + " " + (p.active ? button({ label: translate("✏️ Editar"), attrs: 'data-edit="' + escapeHtml(p.id) + '"' }) + " " + button({ label: translate("🗄️ Archivar"), variant: "danger", attrs: 'data-archive="' + escapeHtml(p.id) + '"' }) : button({ label: translate("♻️ Restaurar"), attrs: 'data-restore="' + escapeHtml(p.id) + '"' }) + " " + button({ label: translate("🗑️ Borrar definitivamente"), variant: "danger", attrs: 'data-delete="' + escapeHtml(p.id) + '"' })) }
    ],
    customers: [
      { key: "name", label: "Cliente", sort: "name" },
      { key: "taxId", label: "Identificación", sort: "identification" },
      { key: "category", label: "Categoría" },
      { key: "address", label: "Dirección" },
      { key: "city", label: "Ciudad" },
      { key: "phone", label: "Teléfono" },
      { key: "email", label: "Email" },
      { label: "Acciones", actions: true, html: (c) => button({ label: translate("Historial"), attrs: 'data-partner="' + escapeHtml(c.id) + '"' }) + " " + (c.active ? button({ label: translate("✏️ Editar"), attrs: 'data-edit="' + escapeHtml(c.id) + '"' }) + " " + button({ label: translate("🗄️ Archivar"), variant: "danger", attrs: 'data-archive="' + escapeHtml(c.id) + '"' }) : button({ label: translate("♻️ Restaurar"), attrs: 'data-restore="' + escapeHtml(c.id) + '"' }) + " " + button({ label: translate("🗑️ Borrar definitivamente"), variant: "danger", attrs: 'data-delete="' + escapeHtml(c.id) + '"' })) }
    ]
  };
  function directory(entity, filter = "") {
    var _a, _b;
    const moduleId = entity === "customers" ? "clients" : entity;
    if (!((_a = window.gamaAccessAllowed) == null ? void 0 : _a.call(window, moduleId))) {
      (_b = views.get(entity)) == null ? void 0 : _b.dispose();
      views.delete(entity);
      return;
    }
    const key = entity === "customers" ? "clients" : entity, host = $(key === "clients" ? "clientsTable" : "productsTable");
    if (!host) return;
    const prior = views.get(entity);
    if ((prior == null ? void 0 : prior.host) === host && host.firstElementChild) {
      prior.refresh(filter);
      return;
    }
    prior == null ? void 0 : prior.dispose();
    host.innerHTML = "<div data-arc-archive></div><div data-arc-directory></div>";
    let rows = /* @__PURE__ */ new Map(), lastFilter = filter, lastArchived;
    const grid = dataTable(host.querySelector("[data-arc-directory]"), { columns: directoryColumns[entity], initial: { search: filter }, source: async (request) => {
      const archived = window.GamaArchive.mode(key) === "archived";
      lastArchived = archived;
      const result = await page(entity, { ...request, archived });
      rows = new Map(result.items.map((x) => [x.id, x]));
      const other = await window.GamaCloud.list(entity, { select: "id", count: "exact", head: true, eq: { active: archived } });
      if (other.error) throw other.error;
      host.querySelector("[data-arc-archive]").innerHTML = window.GamaArchive.tabs(key, archived ? other.count : result.total, archived ? result.total : other.count);
      return result;
    }, actions: { "data-product-controls": (id) => window.ArchitectProductsControls.open(id), "data-partner": (id) => window.ArchitectPartners.open("customer", id), "data-edit": (id) => {
      const row = rows.get(id);
      if (row) entity === "products" ? window.editProduct(row.barcode, row.id) : window.editClient(row.taxId);
    }, "data-archive": (id) => {
      const row = rows.get(id);
      if (row) entity === "products" ? window.deleteProduct(row.barcode) : window.deleteClient(row.taxId);
    }, "data-restore": (id) => entity === "products" ? window.restoreProduct(id) : window.restoreClient(id), "data-delete": (id) => entity === "products" ? window.purgeProduct(id) : window.purgeClient(id) } });
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
  const pending = /* @__PURE__ */ new Map();
  const lazyModules = {
    sav: { global: "GamaService", file: "gama-service-documents.js", methods: ["open", "openTicket"] },
    documents: { global: "GamaDocuments", file: "gama-service-documents.js", methods: ["open"] },
    accounting: { global: "GamaAccounting", file: "gama-accounting.js", methods: ["open", "rpc"] },
    fleet: { global: "GamaFleet", file: "gama-fleet.js", methods: ["open", "openVehicle", "openDriver", "rpc"] },
    returns: { global: "GamaReturns", file: "gama-returns.js", methods: ["open", "openReturn", "createFrom", "rpc"] }
  };
  function loadModule(id) {
    const entry = lazyModules[id];
    if (!entry) return Promise.resolve();
    if (window[entry.global] && !window[entry.global].__arcLazy) return Promise.resolve(window[entry.global]);
    if (pending.has(id)) return pending.get(id);
    const promise = new Promise((resolve, reject) => {
      var _a;
      const script = document.createElement("script");
      script.src = ((_a = window.ArcAssets) == null ? void 0 : _a[entry.file]) || entry.file;
      script.dataset.arcModule = id;
      script.onload = () => {
        const api = window[entry.global];
        if (api && !api.__arcLazy) resolve(api);
        else {
          script.remove();
          pending.delete(id);
          reject(Error("MODULE_LOAD_FAILED"));
        }
      };
      script.onerror = () => {
        script.remove();
        pending.delete(id);
        reject(Error("MODULE_LOAD_FAILED"));
      };
      document.head.appendChild(script);
    });
    pending.set(id, promise);
    return promise;
  }
  function installLazyModules() {
    for (const [id, entry] of Object.entries(lazyModules)) {
      if (window[entry.global]) continue;
      window[entry.global] = { __arcLazy: true, ...Object.fromEntries(entry.methods.map((method) => [method, async (...args) => {
        var _a, _b;
        try {
          return (await loadModule(id))[method](...args);
        } catch (e) {
          (_b = window.gamaToast) == null ? void 0 : _b.call(window, ((_a = window.ArcErrors) == null ? void 0 : _a.message(e)) || e.message);
          throw e;
        }
      }])) };
    }
  }
  function startPerformance() {
    const entries = [], start = performance.now();
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
    window.ArchitectPerformance = { snapshot: () => ({ entries: entries.map((x) => ({ ...x })), resources: performance.getEntriesByType("resource").filter((r) => ["fetch", "xmlhttprequest", "script"].includes(r.initiatorType)).map((r) => ({ kind: r.initiatorType, milliseconds: Math.round(r.duration), bytes: r.transferSize || null })), navigation: performance.getEntriesByType("navigation").map((n) => ({ domContentLoaded: Math.round(n.domContentLoadedEventEnd), load: Math.round(n.loadEventEnd) })) }) };
  }
  window.ArcUI = { ...ui, icons, esc: escapeHtml };
  window.ArcFormat = format;
  window.ArcErrors = { normalize: normalizeError, message: errorMessage };
  window.ArcData = data;
  window.ArcEntities = { ...entities$1 };
  window.ArcModules = { registry, groups, roles, aliases, roleAliases, get: (id) => registry.find((m) => m.id === (aliases[id] || id)) };
  window.ArcRouter = router;
  window.ArcDirectories = { directory, suppliers };
  window.ArcLoad = loadModule;
  installLazyModules();
  startDataEvents();
  startRouter();
  startPerformance();
})();
