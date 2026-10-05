import { lazyModules } from "./lazy-modules.js";
export { lazyModules } from "./lazy-modules.js";
const scripts = new Map();
const styles = new Map();
const modules = new Map(), prepared = new Set();
const filesFor = entry => [...(entry.dependencies || []), entry.file, ...(entry.extensions || [])];
/** Fetch on navigation intent; preloads never execute code or read business data. */
export function prepareModule(id) {
  const entry = lazyModules[id];
  if (!entry) return;
  for (const file of filesFor(entry)) {
    if (prepared.has(file) || scripts.has(file)) continue;
    prepared.add(file);
    const link = document.createElement('link');
    link.rel = 'preload'; link.as = 'script';
    link.href = window.ArcAssets?.[file] || file;
    document.head.appendChild(link);
  }
  for(const file of entry.styles||[]){if(prepared.has(file))continue;prepared.add(file);const link=document.createElement('link');link.rel='preload';link.as='style';link.href=window.ArcAssets?.[file]||file;document.head.appendChild(link)}
}
export function loadStyle(file){if(styles.has(file))return styles.get(file);const pending=new Promise((resolve,reject)=>{const link=document.createElement('link');link.rel='stylesheet';link.href=window.ArcAssets?.[file]||file;link.dataset.arcAsset=file;link.onload=resolve;link.onerror=()=>{link.remove();styles.delete(file);reject(Error('MODULE_LOAD_FAILED'))};document.head.appendChild(link)});styles.set(file,pending);return pending}
/** One request per asset, including modules sharing the same implementation.
 * Failed requests are removed so a later user action can retry. */
export function loadScript(file, options = {}) {
  if (scripts.has(file)) return scripts.get(file);
  const pending = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    // Only dependency groups need an execution queue. Independent downloads
    // (for example a PDF engine) must not postpone unrelated workspaces.
    script.async = options.ordered !== true;
    script.src = window.ArcAssets?.[file] || file;
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
export async function loadModule(id) {
  const entry = lazyModules[id];
  if (!entry) return;
  if (modules.has(id)) return modules.get(id);
  const installed = window[entry.global];
  if (installed && !installed.__arcLazy && !entry.extensions){await Promise.all((entry.styles||[]).map(loadStyle));return installed}
  prepareModule(id);
  const pending = (async () => {
    const css=Promise.all((entry.styles||[]).map(loadStyle));css.catch(()=>{});
    if (window.ArcRuntimeLoaded === false) await window.ArcEnsureRuntime();
    // Dependencies execute first. All their transfers start together.
    if (entry.dependencies?.length) await Promise.all(entry.dependencies.map(file => loadScript(file,{ordered:true})));
    await loadScript(entry.file);
    if (entry.extensions?.length) await Promise.all(entry.extensions.map(file => loadScript(file,{ordered:true})));
    await css;
    const api = window[entry.global];
    if (!api || api.__arcLazy) throw Error("MODULE_LOAD_FAILED");
    return api;
  })();
  modules.set(id, pending);
  try { return await pending; }
  catch (error) { if (modules.get(id) === pending) modules.delete(id); throw error; }
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
    for (const [name, method] of Object.entries(entry.aliases || {}))
      window[name] = (...args) => window[entry.global][method](...args);
    for (const [name, methods] of Object.entries(entry.apis || {})) {
      if (window[name]) continue;
      window[name] = {__arcLazy: true, ...Object.fromEntries(methods.map(method => [method,
        async (...args) => { await loadModule(id); return window[name][method](...args); }]))};
    }
  }
}
