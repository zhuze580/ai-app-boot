import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateConfig,mediaPath} from './core.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let local={};
try {local=JSON.parse((await fs.readFile(path.join(root,'config.local.json'),'utf8')).replace(/^\uFEFF/,''));}
catch(e){if(e.code!=='ENOENT')throw e;}
const app=process.argv[2]||'Codex';
const config=validateConfig({...local,...local.apps?.[app],app});
let file;
if(config.media)file=mediaPath(root,config.media);
else file=mediaPath(root,'intro.mp4');
const media=await fs.readFile(file);
if(media.length<1||media.length>32*1024*1024)throw new Error('Video must be at most 32 MiB');
console.log(JSON.stringify({ok:true,app,node:process.versions.node,media:path.basename(file),bytes:media.length}));
