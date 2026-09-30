/* Generated from src/features/projects/integration.js. Edit the source and run npm run build. */
/* Coco ERP — lightweight project integration.
   Shared permissions, API calls, alerts and links work without loading the
   full project editor. The editor loads only when a project is opened. */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id),
    esc = window.ArcUI.esc;
  let authEpoch = 0,
    alertsPending = null;
  const lang = () => window.GamaI18n?.language || "es";
  const t = (k) =>
    window.GamaProjectsText[k]?.[{ es: 0, fr: 1, en: 2 }[lang()]] || k;
  const allowed = () => !!window.gamaAccessAllowed?.("projects");
  const date = (d) =>
    d
      ? new Date(d.slice(0, 10) + "T12:00:00").toLocaleDateString(
          window.GamaI18n?.locale || "es-EC",
        )
      : "—";
  function error(e) {
    const s = String(e?.message || e);
    if (window.GamaProjectsText[s]) return t(s);
    const key = Object.keys(window.GamaProjectsText).find(
      (k) => k.startsWith("PM_") && s.includes(k),
    );
    return key
      ? t(key)
      : /PM_INVALID_|23514|23502|22P02|22007|22008/.test(s)
        ? t("invalid_data")
        : /23505/.test(s)
          ? t("PM_SOURCE_ALREADY_LINKED")
          : t("error");
  }
  const badge = (s) =>
    `<span class="arcStatusBadge pmBadge">${esc(t(s))}</span>`;
  async function rpc(action, data = {}, mutate = false) {
    if (!allowed()) throw Error("PM_FORBIDDEN");
    const epoch = authEpoch;
    await window.GamaCloudReady;
    if (epoch !== authEpoch || !allowed()) throw Error("PM_FORBIDDEN");
    const r = await window.ArcData.rawRpc("gama_projects_action", {
      p_action: action,
      p_data: {
        ...data,
        ...(mutate
          ? { request_key: data.request_key || crypto.randomUUID() }
          : {}),
      },
    });
    if (epoch !== authEpoch || !allowed()) throw Error("PM_FORBIDDEN");
    if (r.error) throw r.error;
    if (mutate) {
      window.dispatchEvent(new CustomEvent("gama:projects-change"));
      if (["reserve", "release"].includes(action))
        window.dispatchEvent(new CustomEvent("gama:stock-cloud-change"));
    }
    return r.data;
  }
  // Share only simultaneous reads. Resolved results are never cached across
  // refreshes or sessions, so the notification count always uses current data.
  function readAlerts() {
    if (alertsPending) return alertsPending;
    const pending = rpc("alerts");
    alertsPending = pending;
    const clear = () => {
      if (alertsPending === pending) alertsPending = null;
    };
    pending.then(clear, clear);
    return pending;
  }
  function alertsHTML(alerts, active = false) {
    return alerts.length
      ? alerts
          .map(
            (a) =>
              `<div class="pmRow"><div><span class="arcStatusBadge pmBadge pmHealth${a.severity}">${esc(t(a.alert))}</span><div class="pmRef">${esc(a.reference)}</div><button class="arcButton pmLink" ${active && a.item_id ? `data-pm-action="item" data-id="${a.item_id}"` : `data-pm-project="${a.project_id}" ${a.item_id ? `data-pm-item="${a.item_id}"` : ""}`} ${!a.item_id ? `data-pm-target-tab="${a.alert.startsWith("budget") ? "budget" : "plan"}"` : ""}>${esc(a.title)}</button></div><span class="pmMeta">${date(a.due_date)}</span></div>`,
          )
          .join("")
      : `<div class="pmEmpty">${esc(t("empty"))}</div>`;
  }
  function sourceButton(kind, id, host) {
    if (!allowed() || !host) return;
    const b = document.createElement("button");
    b.className = "secondary";
    b.type = "button";
    b.dataset.pmSource = kind;
    b.textContent = t("create_project");
    b.onclick = () => window.GamaProjects.fromSource(kind, id);
    host.appendChild(b);
  }
  async function countAlerts() {
    if (!allowed()) return 0;
    const epoch = authEpoch;
    const rows = await readAlerts();
    return epoch === authEpoch && allowed() && Array.isArray(rows)
      ? rows.length
      : 0;
  }
  async function mountAlerts(host) {
    if (!allowed() || !host) return;
    const epoch = authEpoch,
      request = crypto.randomUUID();
    host.dataset.pmAlertsRequest = request;
    try {
      const alerts = await readAlerts();
      if (
        !host.isConnected ||
        !allowed() ||
        epoch !== authEpoch ||
        host.dataset.pmAlertsRequest !== request ||
        !Array.isArray(alerts)
      )
        return;
      host.querySelector("[data-pm-alerts]")?.remove();
      const block = document.createElement("div");
      block.className = "pmPanel";
      block.dataset.pmAlerts = "";
      block.dataset.giIgnore = "";
      window.ArcUI.render(
        block,
        `<h3>${esc(t("projects"))} · ${esc(t("actions_required"))}</h3>` +
          alertsHTML(alerts),
      );
      block
        .querySelectorAll("[data-pm-project]")
        .forEach(
          (b) =>
            (b.onclick = () =>
              window.GamaProjects.open({
                projectId: b.dataset.pmProject,
                itemId: b.dataset.pmItem,
                tab: b.dataset.pmTargetTab || undefined,
              })),
        );
      host.appendChild(block);
      return alerts.length;
    } catch (e) {
      if (
        host.isConnected &&
        epoch === authEpoch &&
        allowed() &&
        host.dataset.pmAlertsRequest === request
      ) {
        const block = document.createElement("p");
        block.className = "pmError";
        block.textContent = t("projects") + ": " + error(e);
        host.appendChild(block);
      }
    }
  }
  async function customerProjects(id, host) {
    if (!allowed() || !id || !host) return;
    const epoch = authEpoch,
      request = crypto.randomUUID();
    host.dataset.pmCustomer = id;
    host.dataset.pmCustomerRequest = request;
    try {
      const [r, a, c] = await Promise.all([
        rpc("portfolio", { limit: 12, filters: { customer_id: id } }),
        rpc("portfolio", {
          limit: 1,
          filters: { customer_id: id, status: "active" },
        }),
        rpc("portfolio", {
          limit: 1,
          filters: { customer_id: id, status: "completed" },
        }),
      ]);
      if (
        !host.isConnected ||
        epoch !== authEpoch ||
        !allowed() ||
        host.dataset.pmCustomer !== id ||
        host.dataset.pmCustomerRequest !== request
      )
        return;
      window.ArcUI.render(
        host,
        `<div class="arcPanel pmPanel"><h3>${esc(t("projects"))}</h3><div class="pmTools"><span>${esc(t("active_projects"))}: ${a.total}</span><span>${esc(t("completed_projects"))}: ${c.total}</span><button class="arcButton secondary" data-all>${esc(t("portfolio"))} (${r.total})</button></div>${r.rows.map((p) => `<p><button class="arcButton pmLink" data-id="${p.id}">${esc(p.reference + " · " + p.name)}</button> ${badge(p.status)}</p>`).join("")}</div>`,
      );
      host
        .querySelectorAll("[data-id]")
        .forEach(
          (b) =>
            (b.onclick = () =>
              window.GamaProjects.open({ projectId: b.dataset.id })),
        );
      host.querySelector("[data-all]").onclick = () =>
        window.GamaProjects.open({ customerId: id });
    } catch (e) {
      if (
        host.isConnected &&
        epoch === authEpoch &&
        host.dataset.pmCustomerRequest === request
      )
        host.textContent = error(e);
    }
  }
  function reset() {
    authEpoch++;
    alertsPending = null;
    document
      .querySelectorAll("[data-pm-alerts],#pmCustomerProjects")
      .forEach((e) => e.replaceChildren());
  }
  window.addEventListener("gama:auth-change", (e) => {
    if (e.detail?.event !== "TOKEN_REFRESHED") reset();
  });
  window.addEventListener("gama:modules-change", () => {
    if (!allowed()) reset();
  });
  window.addEventListener("gama:projects-change", () => {
    alertsPending = null;
  });
  window.GamaProjectsShared = {
    t,
    error,
    rpc,
    lang,
    date,
    allowed,
    alertsHTML,
  };
  const deferred = window.GamaProjects;
  window.GamaProjects = {
    ...deferred,
    __arcLazy: true,
    open: (...args) => (allowed() ? deferred.open(...args) : undefined),
    fromSource: (...args) =>
      allowed() ? deferred.fromSource(...args) : undefined,
    t,
    error,
    rpc,
    sourceButton,
    countAlerts,
    mountAlerts,
    customerProjects,
    linkPurchase: (context, purchaseId, currency, exchangeRate) =>
      rpc(
        "link",
        {
          project_id: context.project_id,
          id: context.item_id,
          kind: "purchase",
          target_id: purchaseId,
          currency,
          exchange_rate: exchangeRate,
        },
        true,
      ),
  };
})();
