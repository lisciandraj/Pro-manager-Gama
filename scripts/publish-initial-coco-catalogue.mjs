import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

export const APPROVED = '20272ccbd040a5a00b32d6632ba8ad9eb1b72481';
const BACKEND = 'https://vhutzdfatijjpahsqkne.supabase.co';
const SITE = 'https://gama-coco.pages.dev';
const PROJECT = 'gama-coco';
const forbiddenBackend = 'mknsaibrewksgomuslev.supabase.co';
const sort = value => Array.isArray(value) ? value.map(sort) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])])) : value;
const fingerprint = value => createHash('sha256').update(JSON.stringify(sort(value))).digest('hex');
const statePath = () => path.join(process.env.RUNNER_TEMP, 'coco-initial-catalogue-state.json');
const sourceWithoutProductionFlag = source => {
  if (!source) return null;
  const result = structuredClone(source);
  if (result.config) delete result.config.production_deployments_enabled;
  return result;
};
// Hash values in memory. Never print or upload Cloudflare configuration replies.
const bindings = project => Object.fromEntries(Object.entries(project.deployment_configs || {}).map(([environment, config]) => [environment,
  Object.fromEntries(Object.entries(config || {}).filter(([key]) => !['wrangler_config_hash'].includes(key)))
]));

export async function assertReady(runtime, fetcher = fetch) {
  if (runtime?.url !== BACKEND || !/^sb_publishable_[A-Za-z0-9_-]+$/.test(runtime?.publishable_key || '')) throw Error('Frozen production backend configuration mismatch');
  const rpc = async (name, body) => {
    const response = await fetcher(`${BACKEND}/rest/v1/rpc/${name}`, {method:'POST', redirect:'error', signal:AbortSignal.timeout(15000),
      headers:{'Content-Type':'application/json',apikey:runtime.publishable_key},body:JSON.stringify(body)});
    if (!response.ok) throw Error(`Production ${name} returned HTTP ${response.status}`);
    return response.json();
  };
  const marker = await rpc('coco_environment_status', {});
  if (marker.environment !== 'production' || marker.release !== APPROVED || marker.allowed !== true || marker.admin !== false) throw Error('Production environment marker is not the approved initial release');
  const bootstrap = await rpc('gama_storefront', {p_action:'bootstrap',p_data:{}});
  if (bootstrap.paused !== false || bootstrap.total !== 0 || !Array.isArray(bootstrap.featured) || bootstrap.featured.length) throw Error('Initial public production catalogue is not ready and empty');
  const catalog = await rpc('gama_storefront', {p_action:'catalog',p_data:{limit:1}});
  if (catalog.total !== 0 || !Array.isArray(catalog.items) || catalog.items.length) throw Error('Initial public production catalogue contains items');
}

export function cloudflareClient(env = process.env, fetcher = fetch) {
  if (!/^[a-f0-9]{32}$/i.test(env.CLOUDFLARE_ACCOUNT_ID || '') || !env.CLOUDFLARE_API_TOKEN || /\s/.test(env.CLOUDFLARE_API_TOKEN)) throw Error('Configure the two Cloudflare Actions secrets before running this release');
  return async (method = 'GET', body) => {
    const response = await fetcher(`https://api.cloudflare.com/client/v4/accounts/${env.CLOUDFLARE_ACCOUNT_ID}/pages/projects/${PROJECT}`, {
      method, redirect:'error',signal:AbortSignal.timeout(20000), headers:{Authorization:`Bearer ${env.CLOUDFLARE_API_TOKEN}`,'Content-Type':'application/json'},
      ...(body ? {body:JSON.stringify(body)} : {})
    });
    if (!response.ok) throw Error(`Cloudflare existing-project ${method} returned HTTP ${response.status}`);
    const envelope = await response.json();
    if (envelope.success !== true || !envelope.result) throw Error('Cloudflare existing-project request failed');
    const project = envelope.result;
    if (project.name !== PROJECT || project.subdomain !== 'gama-coco.pages.dev' || !project.id || !/^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/.test(project.production_branch || '')) throw Error('Unexpected existing Cloudflare Pages project');
    return project;
  };
}

export function snapshot(project) {
  return {project_id:project.id,production_branch:project.production_branch,bindings_fingerprint:fingerprint(bindings(project)),source_fingerprint:fingerprint(sourceWithoutProductionFlag(project.source))};
}

export function assertUnchanged(project, expected) {
  const current = snapshot(project);
  if (Object.keys(expected).some(key => expected[key] !== current[key])) throw Error('Cloudflare project, branch, preview settings or bindings changed; review before publication');
}

export async function freezeProduction(client, expected) {
  let project = await client();
  assertUnchanged(project, expected);
  if (!project.source) return project; // Existing Direct Upload project has no Git auto-deployment.
  if (!['github','gitlab'].includes(project.source.type) || !project.source.config) throw Error('Unsupported existing Pages source configuration');
  if (project.source.config.production_deployments_enabled !== false) {
    // Edit Project API: keep all returned source settings, changing only this
    // documented flag. Preview branches, PR comments and build paths are retained.
    await client('PATCH', {source:{type:project.source.type,config:{...project.source.config,production_deployments_enabled:false}}});
    project = await client();
  }
  assertUnchanged(project, expected);
  if (project.source.config.production_deployments_enabled !== false) throw Error('Automatic production deployment freeze was not applied');
  return project;
}

async function assertFrozenRef() {
  const response = await fetch('https://api.github.com/repos/lisciandraj/Pro-manager-Gama/git/ref/heads/production', {
    redirect:'error',signal:AbortSignal.timeout(15000),headers:{Accept:'application/vnd.github+json','User-Agent':'coco-initial-catalogue-release',
      ...(process.env.GITHUB_TOKEN ? {Authorization:`Bearer ${process.env.GITHUB_TOKEN}`} : {})}
  });
  if (!response.ok || (await response.json()).object?.sha !== APPROVED) throw Error('Production branch has moved beyond the approved initial release; this bootstrap cannot publish');
}

async function main(command) {
  const runtime = JSON.parse(fs.readFileSync('config/storefront-runtime.json','utf8'));
  if (command === 'receipt') {
    if (runtime.url !== BACKEND) throw Error('Wrong production build backend');
    for (const file of ['dist-storefront/index.html','dist-storefront/_headers']) {
      const text = fs.readFileSync(file,'utf8');
      if (!text.includes(new URL(BACKEND).host) || text.includes(forbiddenBackend)) throw Error('Wrong production asset backend or CSP');
    }
    fs.writeFileSync('dist-storefront/coco-storefront-build.json', JSON.stringify({environment:'production',commit:APPROVED,backend:BACKEND,built_at:new Date().toISOString()},null,2)+'\n');
    return;
  }
  if (command === 'preflight') {
    await assertFrozenRef();
    const client = cloudflareClient();
    const project = await client();
    const expected = snapshot(project);
    fs.writeFileSync(statePath(), JSON.stringify(expected), {mode:0o600});
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `production_branch=${project.production_branch}\n`);
    console.log(`Existing project ${PROJECT}; production branch ${project.production_branch}; Git production auto-deployments ${project.source ? project.source.config?.production_deployments_enabled !== false : false}.`);
    return;
  }
  await assertReady(runtime);
  if (command === 'ready') return;
  await assertFrozenRef();
  const client = cloudflareClient();
  if (command === 'freeze') {
    await freezeProduction(client, JSON.parse(fs.readFileSync(statePath(),'utf8')));
    console.log('Production Git auto-deployments frozen; existing preview configuration and bindings preserved.');
  } else if (command === 'verify') {
    const expected = JSON.parse(fs.readFileSync(statePath(),'utf8'));
    const project = await client();
    assertUnchanged(project, expected);
    if (project.source && project.source.config?.production_deployments_enabled !== false) throw Error('Automatic Git production deployments were re-enabled');
    const deployment = project.canonical_deployment;
    if (deployment?.environment !== 'production' || deployment?.deployment_trigger?.metadata?.commit_hash !== APPROVED || deployment?.deployment_trigger?.metadata?.branch !== expected.production_branch) throw Error('Canonical production deployment is not the approved source');
    const response = await fetch(`${SITE}/?coco_release=${APPROVED}`, {redirect:'error',signal:AbortSignal.timeout(15000),headers:{'Cache-Control':'no-cache'}});
    const html = await response.text();
    const csp = response.headers.get('Content-Security-Policy') || '';
    if (!response.ok || !html.includes(new URL(BACKEND).host) || html.includes(forbiddenBackend) || !csp.includes(new URL(BACKEND).host) || csp.includes(forbiddenBackend)) throw Error('Live catalogue assets or CSP do not use the new production');
    const versionResponse = await fetch(`${SITE}/coco-storefront-build.json?commit=${APPROVED}`,{redirect:'error',signal:AbortSignal.timeout(15000)});
    const version = await versionResponse.json();
    if (!versionResponse.ok || version.commit !== APPROVED || version.environment !== 'production' || version.backend !== BACKEND) throw Error('Live catalogue version receipt mismatch');
    for (const action of ['bootstrap','catalog']) {
      const api = await fetch(`${SITE}/api/storefront`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{'Content-Type':'application/json'},body:JSON.stringify({p_action:action,p_data:{limit:1}})});
      const data = await api.json();
      if (!api.ok || data.total !== 0 || (action === 'bootstrap' ? !Array.isArray(data.featured) || data.featured.length : !Array.isArray(data.items) || data.items.length)) throw Error('Live Pages Functions do not serve the empty production catalogue');
    }
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `Published and verified ${SITE} from approved production commit \`${APPROVED}\`.\n\nCatalogue contains zero products. Existing Cloudflare bindings and preview settings are preserved; automatic Git production deployment is disabled.\n\nProtected submissions and checkout require the independently configured new-production COCO_SITE_TOKEN; this release does not copy or rotate that token.\n`);
    console.log('Live catalogue, version, CSP, production Functions and preserved settings verified.');
  } else throw Error('Unknown initial catalogue release operation');
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv[2]).catch(error => {console.error(error.message);process.exitCode=1;});
}
