import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {CDP} from './cdp.mjs';

// Called only with a connection whose listening process has been verified by host.ps1.
export async function restoreTheme(connection,watcherAlive=false) {
  if(!Number.isInteger(connection?.port)||connection.port<1024||connection.port>65535||!/^[a-f0-9-]{36}$/i.test(connection.browserId||''))return false;
  const root=path.join(process.env.LOCALAPPDATA,'CodexDreamSkin');
  const file=path.join(root,'state.json');
  let page;
  try {
    const state=JSON.parse((await fs.readFile(file,'utf8')).replace(/^\uFEFF/,''));
    if(state.port!==connection.port)return false;
    try{await fs.access(path.join(root,'paused'));return true;}catch{}
    const origin='http://127.0.0.1:'+connection.port;
    const read=async suffix=>{const r=await fetch(origin+suffix,{signal:AbortSignal.timeout(2000),redirect:'error'});if(!r.ok)throw Error();return r.json();};
    const version=await read('/json/version');
    if(version.webSocketDebuggerUrl!==`ws://127.0.0.1:${connection.port}/devtools/browser/${connection.browserId}`)return false;
    const pages=(await read('/json/list')).filter(t=>t.type==='page'&&t.url==='app://-/index.html');
    if(pages.length!==1)return false;
    const endpoint=new URL(pages[0].webSocketDebuggerUrl);
    if(endpoint.origin!==`ws://127.0.0.1:${connection.port}`||!endpoint.pathname.startsWith('/devtools/page/')||endpoint.username||endpoint.password||endpoint.search||endpoint.hash)return false;
    page=await CDP.open(endpoint.href);
    const injector=path.join(root,'engine/scripts/injector.mjs');
    const {loadPayload}=await import(pathToFileURL(injector));
    const payload=await loadPayload(state.themeDir);
    await page.evaluate(payload.payload,15000);
    const applied=await page.evaluate(`(()=>{const s=window.__CODEX_DREAM_SKIN_STATE__;return !!s&&s.themeId===${JSON.stringify(payload.theme.id)}&&(s.styleMode==='adopted'?[...document.adoptedStyleSheets].includes(s.styleSheet):!!s.styleNode?.isConnected);})()`);
    if(!applied)return false;
    const current=JSON.parse((await fs.readFile(file,'utf8')).replace(/^\uFEFF/,''));
    current.browserId=connection.browserId;
    if(!watcherAlive||state.browserId!==connection.browserId) {
      const child=spawn(path.join(root,'engine/runtime/node/node.exe'),[injector,'--watch','--port',String(connection.port),'--browser-id',connection.browserId,'--theme-dir',state.themeDir,'--pause-file',path.join(root,'paused')],{detached:true,windowsHide:true,stdio:'ignore'});
      await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject);});
      current.injectorPid=child.pid;child.unref();
    }
    await fs.writeFile(file,JSON.stringify(current,null,2));
    return true;
  }catch{return false;}finally{page?.close();}
}
