import * as ui from './ui/components.js';
import {icons,moduleIcon} from './ui/icons.js';
import {escapeHtml,format,normalizeError,errorMessage} from './domain/format.js';
import * as data from './data/service.js';
import * as entities from './domain/entities.js';
import {registry,groups,roles,aliases,roleAliases,tabsOf} from './app/registry.js';
import {router,startRouter} from './app/router.js';
import {directory} from './modules/directories.js';
import {installLazyModules,loadModule,loadScript,prepareModule} from './app/loader.js';
window.ArcUI={...ui,icons,moduleIcon,esc:escapeHtml};
window.ArcFormat=format;
window.ArcErrors={normalize:normalizeError,message:errorMessage};
window.ArcData=data;
window.ArcEntities={...entities};
window.ArcModules={registry,groups,roles,aliases,roleAliases,tabsOf,get:id=>registry.find(m=>m.id===(aliases[id]||id))};
window.ArcRouter=router;
window.ArcDirectories={directory};
window.ArcLoad=loadModule;
window.ArcLoadScript=loadScript;
window.ArcPrefetch=prepareModule;
const runtime=document.querySelector('script[data-arc-runtime]');
window.ArcRuntimeLoaded=!runtime;
window.ArcRuntimeReady=runtime?new Promise((resolve,reject)=>{
 runtime.addEventListener('load',()=>{window.ArcRuntimeLoaded=true;resolve()},{once:true});
 runtime.addEventListener('error',()=>{window.ArcRuntimeFailed=true;reject(Error('MODULE_LOAD_FAILED'))},{once:true});
}):Promise.resolve();
window.ArcRuntimeReady.catch(()=>{});
window.ArcEnsureRuntime=()=>window.ArcRuntimeLoaded?Promise.resolve():window.ArcRuntimeFailed?
 loadScript('coco-modules.js',{validate:()=>window.ArcRuntimeLoaded}):window.ArcRuntimeReady;
installLazyModules();
router.onEnter('dashboard',()=>{window.ArchitectDashboard.refresh().catch(()=>{})});
data.startDataEvents();startRouter();

import {startPerformance} from './app/performance.js';
startPerformance();
