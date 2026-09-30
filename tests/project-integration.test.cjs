const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"),
  vm = require("node:vm");
const tick = () => new Promise((resolve) => setImmediate(resolve));
function integration() {
  const handlers = {},
    calls = [],
    deferred = [],
    events = [];
  let allowed = true;
  const window = {
    ArcUI: { esc: String },
    GamaProjectsText: {},
    gamaAccessAllowed: () => allowed,
    GamaProjects: {
      open: (...args) => deferred.push(args),
      fromSource: (...args) => deferred.push(args),
    },
    addEventListener: (name, fn) => (handlers[name] ??= []).push(fn),
    dispatchEvent: (event) => {
      events.push(event.type);
      for (const fn of handlers[event.type] || []) fn(event);
    },
    ArcData: {
      rawRpc: (name, args) =>
        new Promise((resolve) => calls.push({ name, args, resolve })),
    },
  };
  vm.runInNewContext(
    fs.readFileSync("src/features/projects/integration.js", "utf8"),
    {
      window,
      crypto: require("node:crypto"),
      document: { querySelectorAll: () => [] },
      CustomEvent: class {
        constructor(type) {
          this.type = type;
        }
      },
    },
  );
  return {
    api: window.GamaProjects,
    calls,
    deferred,
    events,
    access: (value) => {
      allowed = value;
    },
    auth: (event) =>
      window.dispatchEvent({ type: "gama:auth-change", detail: { event } }),
  };
}
test("simultaneous alert counts share a request, later reads fetch fresh data", async () => {
  const x = integration(),
    a = x.api.countAlerts(),
    b = x.api.countAlerts();
  await tick();
  assert.equal(x.calls.length, 1);
  x.calls[0].resolve({ data: [{}, {}] });
  assert.equal(await a, 2);
  assert.equal(await b, 2);
  const c = x.api.countAlerts();
  await tick();
  assert.equal(x.calls.length, 2);
  x.calls[1].resolve({ data: [] });
  assert.equal(await c, 0);
});
test("failed alert reads can retry", async () => {
  const x = integration(),
    a = x.api.countAlerts();
  await tick();
  x.calls[0].resolve({ error: Error("offline") });
  await assert.rejects(a, /offline/);
  const b = x.api.countAlerts();
  await tick();
  x.calls[1].resolve({ data: [{}] });
  assert.equal(await b, 1);
});
test("session changes invalidate pending reads without clearing a newer request", async () => {
  const x = integration(),
    old = x.api.countAlerts();
  await tick();
  x.auth("SIGNED_OUT");
  const current = x.api.countAlerts();
  await tick();
  x.calls[0].resolve({ data: [{}] });
  await assert.rejects(old, /PM_FORBIDDEN/);
  const shared = x.api.countAlerts();
  await tick();
  assert.equal(x.calls.length, 2);
  x.calls[1].resolve({ data: [{}, {}] });
  assert.equal(await current, 2);
  assert.equal(await shared, 2);
});
test("token refresh preserves requests, revoked permissions block reads and deferred editors", async () => {
  const x = integration(),
    a = x.api.countAlerts();
  await tick();
  x.auth("TOKEN_REFRESHED");
  x.calls[0].resolve({ data: [{}] });
  assert.equal(await a, 1);
  x.access(false);
  assert.equal(await x.api.countAlerts(), 0);
  x.api.open();
  x.api.fromSource("quote", "1");
  assert.equal(x.deferred.length, 0);
  await assert.rejects(x.api.rpc("detail"), /PM_FORBIDDEN/);
  assert.equal(x.calls.length, 1);
});
test("mutations preserve idempotency keys and only notify the active session", async () => {
  const x = integration(),
    a = x.api.rpc("reserve", { request_key: "stable-key" }, true);
  await tick();
  assert.equal(x.calls[0].args.p_data.request_key, "stable-key");
  x.calls[0].resolve({ data: { ok: true } });
  await a;
  assert.deepEqual(x.events, [
    "gama:projects-change",
    "gama:stock-cloud-change",
  ]);
  const b = x.api.rpc("reserve", {}, true);
  await tick();
  assert.match(x.calls[1].args.p_data.request_key, /^[a-f0-9-]{36}$/);
  x.auth("SIGNED_OUT");
  x.calls[1].resolve({ data: { ok: true } });
  await assert.rejects(b, /PM_FORBIDDEN/);
  assert.equal(x.events.filter((e) => e === "gama:projects-change").length, 1);
});
