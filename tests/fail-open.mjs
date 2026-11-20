// Local integration checks: requires an installed, logged-in WorkBuddy.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {CDP} from '../src/cdp.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const run=(env)=>{
  const child=spawn(process.execPath,[path.join(root,'src/boot.mjs'),'WorkBuddy','--muted'],{env,windowsHide:true,stdio:'ignore'});
  const done=new Promise((resolve,reject)=>{child.once('exit',resolve);child.once('error',reject);});
  return {child,done};
};
const fake=await fs.mkdtemp(path.join(os.tmpdir(),'ai-app-boot-fallback-'));
try {
  const {child,done}=run({...process.env,LOCALAPPDATA:fake,PROGRAMFILES:fake,'PROGRAMFILES(X86)':fake});
  try {
    const code=await Promise.race([done,delay(15000).then(()=>{throw new Error('Missing-browser fallback hung');})]);
    assert.equal(code,0);
    const trace=JSON.parse(await fs.readFile(path.join(fake,'AIAppBoot/last-workbuddy.json'),'utf8'));
    assert.equal(trace.reason,'splash-unavailable');
    assert.ok(trace.appLaunchRequestedAt);
    assert.equal(!!trace.launchFailed,false);
    console.log('PASS: missing Chrome still hands off to native WorkBuddy');
  } finally {if(child.exitCode===null)child.kill();}
} finally {
  if(path.dirname(fake)===path.resolve(os.tmpdir()))await fs.rm(fake,{recursive:true,force:true});
}
const runtime=path.join(process.env.LOCALAPPDATA,'AIAppBoot');
const sessions=path.join(runtime,'sessions');
let before=[];try{before=await fs.readdir(sessions);}catch{}
const {child,done}=run(process.env);
let page;
try {
  const deadline=Date.now()+10000;
  while(!page&&Date.now()<deadline) {
    try {
      const session=(await fs.readdir(sessions)).find(name=>!before.includes(name));
      const port=Number((await fs.readFile(path.join(sessions,session,'chrome-profile/DevToolsActivePort'),'utf8')).split(/\r?\n/)[0]);
      const targets=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const target=targets.find(t=>t.type==='page'&&t.url.startsWith('http://127.0.0.1:'));
      if(target)page=await CDP.open(target.webSocketDebuggerUrl);
    }catch{}
    if(!page)await delay(100);
  }
  assert.ok(page,'owned splash page opened');
  // Branded Chrome may refuse Page.crash. A real blocked JS thread exercises the heartbeat deadline.
  void page.evaluate('while(true){}',1000).catch(()=>{});
  const code=await Promise.race([done,delay(22000).then(()=>{throw new Error('Renderer hang fallback hung');})]);
  assert.equal(code,0);
  const trace=JSON.parse(await fs.readFile(path.join(runtime,'last-workbuddy.json'),'utf8'));
  assert.ok(['renderer-crashed','renderer-unresponsive'].includes(trace.reason),trace.reason);
  assert.ok(trace.appLaunchRequestedAt);
  console.log('PASS: an unresponsive splash renderer closes and still hands off to native WorkBuddy');
} finally {page?.close();if(child.exitCode===null)child.kill();}
