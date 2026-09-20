import {defineConfig} from 'vite';
export default defineConfig({build:{lib:{entry:'src/main.js',name:'ArchitectCore',formats:['iife'],fileName:()=> 'architect-core.js'},outDir:'.build/client',emptyOutDir:true,minify:false,sourcemap:false}});
