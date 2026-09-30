import { lazyModules } from "./lazy-modules.js";
export { lazyModules } from "./lazy-modules.js";
const scripts = new Map();
/** One request per asset, including modules sharing the same implementation.
 * Failed requests are removed so a later user action can retry. */
export function loadScript(file, options = {}) {
  if (scripts.has(file)) return scripts.get(file);
  const pending = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = window.ArcAssets?.[file] || file;
    script.dataset.arcAsset = file;
    for (const key of ["integrity", "crossOrigin", "referrerPolicy"])
      if (options[key]) script[key] = options[key];
    script.onload = () => resolve();
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
export async function loadModule(id) {
  const entry = lazyModules[id];
  if (!entry) return;
  const installed = window[entry.global];
  if (installed && !installed.__arcLazy) return installed;
  for (const file of entry.dependencies || []) await loadScript(file);
  await loadScript(entry.file);
  const api = window[entry.global];
  if (!api || api.__arcLazy) throw Error("MODULE_LOAD_FAILED");
  return api;
}
export function installLazyModules() {
  for (const [id, entry] of Object.entries(lazyModules)) {
    if (window[entry.global]) continue;
    window[entry.global] = {
      __arcLazy: true,
      ...Object.fromEntries(
        entry.methods.map((method) => [
          method,
          async (...args) => {
            try {
              return await (await loadModule(id))[method](...args);
            } catch (e) {
              window.gamaToast?.(window.ArcErrors?.message(e) || e.message);
              throw e;
            }
          },
        ]),
      ),
    };
  }
}
