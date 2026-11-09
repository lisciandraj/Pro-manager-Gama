const fs=require('node:fs'),path=require('node:path');
const {verifyManifest}=require('./lib/release.cjs');
const directory=path.resolve(process.argv[2]||'dist'),manifest=JSON.parse(fs.readFileSync(path.join(directory,'release-manifest.json'),'utf8'));
if(process.env.GITHUB_SHA&&manifest.source_commit!==process.env.GITHUB_SHA)throw Error('RELEASE_REVISION_MISMATCH');
if(process.env.GITHUB_ACTIONS==='true'&&manifest.source_dirty)throw Error('RELEASE_DIRTY_SOURCE');
verifyManifest(directory,manifest);console.log('Release provenance and public artifact hashes verified.');
