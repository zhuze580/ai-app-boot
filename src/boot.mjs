import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import {randomUUID,randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {CDP} from './cdp.mjs';
import {codexReady} from './codex-ready.mjs';
import {validateConfig,shouldFinish,parseRange,mediaPath} from './core.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const app=process.argv[2]||'Codex';
const preview=process.argv.includes('--preview');
let local={},configurationError;
let config=validateConfig({app});
try {
  try {local=JSON.parse((await fs.readFile(path.join(root,'config.local.json'),'utf8')).replace(/^\uFEFF/,''));}
  catch(error){if(error.code!=='ENOENT')throw error;}
  config=validateConfig({...local,...local.apps?.[app],app});
} catch {configurationError=true;}
const pathIndex=process.argv.indexOf('--app-path');
if(pathIndex>=0){if(!process.argv[pathIndex+1])throw new Error('--app-path requires a value');config.appPath=process.argv[pathIndex+1];}
if(process.argv.includes('--muted'))config.muted=true;
const runtime=path.join(process.env.LOCALAPPDATA||os.tmpdir(),'AIAppBoot');
const sessionRoot=path.join(runtime,'sessions',randomUUID());
const profile=path.join(sessionRoot,'chrome-profile');
const statusFile=path.join(sessionRoot,'status.json');
const controlFile=path.join(sessionRoot,'active');
await fs.mkdir(profile,{recursive:true});
await fs.writeFile(controlFile,'active');
const trace={app,preview,startedAt:new Date().toISOString(),phase:'preparing'};
const logFile=path.join(runtime,'last-'+app.toLowerCase()+'.json');
let saves=Promise.resolve();
const save=()=>{const snapshot=JSON.stringify(trace,null,2);saves=saves.then(()=>fs.writeFile(logFile,snapshot));return saves;};
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let browser,cdp,server,host,hostDone=Promise.resolve(),started=false,completed=false,filmEnded=false,appReady=preview;
let heartbeatTimer,lastHeartbeat=Date.now();
let finish;
const complete=new Promise(resolve=>{finish=reason=>{if(!completed){completed=true;resolve(reason);}};});
const finishWhenReady=()=>{if(shouldFinish({appReady,filmEnded}))finish('ready-after-film');};
const hostArgs=['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'scripts/host.ps1'),'-App',app];
if(config.appPath)hostArgs.push('-AppPath',config.appPath);
function launch(fallback=false) {
  if(started||preview)return;
  started=true;trace.appLaunchRequestedAt=new Date().toISOString();void save();
  const args=fallback?[...hostArgs,'-LaunchOnly']:[...hostArgs,'-StatusFile',statusFile,'-ControlFile',controlFile,'-ChromePid',String(browser.pid),'-ProfilePath',profile];
  host=spawn('powershell.exe',args,{windowsHide:true,stdio:['ignore','ignore','pipe']});
  // Never log raw child output: it may include application or user-specific paths.
  host.stderr.on('data',()=>{});
  hostDone=new Promise(resolve=>{
    host.once('error',()=>{trace.launchFailed=true;resolve();});
    host.once('exit',code=>{if(code!==0)trace.launchFailed=true;resolve();});
  });
}
async function watchApp() {
  while(!completed) {
    try {
      const status=JSON.parse(await fs.readFile(statusFile,'utf8'));
      if(status.failed)trace.launchFailed=true;
      if(status.window)trace.window={x:status.x,y:status.y,width:status.width,height:status.height};
      const testDelay=Math.min(30000,Math.max(0,Number(process.env.APP_BOOT_TEST_READY_DELAY_MS)||0));
      const verifiedReady=status.ready||(!appReady&&app==='Codex'&&status.window&&status.codexConnection&&await codexReady(status.codexConnection));
      if(verifiedReady&&!appReady&&Date.now()-Date.parse(trace.appLaunchRequestedAt)>=testDelay) {
        appReady=true;trace.appReadyAt=new Date().toISOString();await save();finishWhenReady();
      }
    }catch{}
    await delay(150);
  }
}
try {
  if(configurationError)throw new Error('Invalid config.local.json; run Check to inspect configuration');
  let video;
  if(config.media)video=mediaPath(root,config.media);
  else video=mediaPath(root,'intro.mp4');
  const media=await fs.readFile(video);
  if(media.length<1||media.length>32*1024*1024)throw new Error('Media must be 1 byte to 32 MiB');
  const player=await fs.readFile(path.join(root,'src/player.js'));
  let chrome;
  for(const base of [process.env.LOCALAPPDATA,process.env.PROGRAMFILES,process.env['PROGRAMFILES(X86)']]) {
    if(!base)continue;const candidate=path.join(base,'Google/Chrome/Application/chrome.exe');
    try {await fs.access(candidate);chrome=candidate;break;}catch{}
  }
  if(!chrome)throw new Error('Google Chrome is required');
  const token='/'+randomBytes(24).toString('hex');
  const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>${app} · 启动动画</title>
  <style>html,body{margin:0;background:#06060d;overflow:hidden}</style><body>
  <script src="${token}/player.js"></script><script>
  (async()=>{
    await CodexStartup.mount({url:'${token}/video',duration:60,volume:${config.volume},muted:${config.muted},holdAtEnd:true});
    let first=false,held=false,busy=false,lastPing=0;
    setInterval(async()=>{
      if(busy)return;busy=true;
      try {
        const s=CodexStartup.status();
        if(s.phase==='playing'&&!first){first=true;await fetch('${token}/first',{method:'POST'});}
        if(s.phase==='holding'&&!held){held=true;await fetch('${token}/ended',{method:'POST'});}
        if(!s.active)await fetch('${token}/done?reason='+encodeURIComponent(s.reason||'closed'),{method:'POST'});
        if(Date.now()-lastPing>1000) {
          lastPing=Date.now();
          const result=await(await fetch('${token}/status')).json();
          const hint=document.getElementById('codex-reference-startup')?.shadowRoot.querySelector('.hint');
          if(hint&&s.phase==='holding')hint.textContent=result.failed?'应用启动未完成 · 按 Esc 退出后查看终端检查结果':'等待 ${app} 内部页面就绪 · Esc 跳过';
        }
      }catch{}finally{busy=false;}
    },100);
  })();</script></body></html>`;
  server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://127.0.0.1');
    res.setHeader('Cache-Control','no-store');
    if(req.method==='POST'&&url.pathname===token+'/first') {
      if(!trace.firstFrameAt){trace.firstFrameAt=new Date().toISOString();trace.phase='playing';launch();void watchApp();void save();}
      res.end('ok');
    } else if(req.method==='POST'&&url.pathname===token+'/ended') {
      if(!filmEnded){filmEnded=true;trace.filmEndedAt=new Date().toISOString();trace.phase='holding';void save();}
      res.end('ok');finishWhenReady();
    } else if(req.method==='POST'&&url.pathname===token+'/done') {
      res.end('ok');finish(url.searchParams.get('reason')||'skipped');
    } else if(req.method==='GET'&&url.pathname===token+'/status') {
      lastHeartbeat=Date.now();
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify({failed:!!trace.launchFailed}));
    } else if(req.method==='GET'&&url.pathname===token) {
      res.setHeader('Content-Type','text/html;charset=utf-8');res.end(html);
    } else if(req.method==='GET'&&url.pathname===token+'/player.js') {
      res.setHeader('Content-Type','text/javascript');res.end(player);
    } else if(req.method==='GET'&&url.pathname===token+'/video') {
      let range;try {range=parseRange(req.headers.range,media.length);}catch {res.writeHead(416,{'Content-Range':'bytes */'+media.length});res.end();return;}
      res.setHeader('Content-Type','video/mp4');res.setHeader('Accept-Ranges','bytes');
      const {start,end,partial}=range;
      res.setHeader('Content-Length',end-start+1);
      if(partial)res.writeHead(206,{'Content-Range':`bytes ${start}-${end}/${media.length}`});
      res.end(media.subarray(start,end+1));
    } else {res.writeHead(404);res.end();}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  const url=`http://127.0.0.1:${server.address().port}${token}`;
  browser=spawn(chrome,['--no-first-run','--no-default-browser-check','--disable-extensions','--disable-background-networking','--disable-sync',
    '--disable-features=ChromeSignin,SigninIntercept','--disable-background-mode','--autoplay-policy=no-user-gesture-required',
    '--remote-debugging-port=0','--user-data-dir='+profile,'--app='+url,'--window-size=1280,800'],{windowsHide:false,stdio:'ignore'});
  trace.splashPid=browser.pid;
  lastHeartbeat=Date.now();
  heartbeatTimer=setInterval(()=>{if(Date.now()-lastHeartbeat>12000)finish('renderer-unresponsive');},500);
  browser.once('error',()=>finish('browser-error'));
  browser.once('exit',()=>finish('window-closed'));
  const connection=(async()=>{
    const deadline=Date.now()+10000;
    while(!completed&&Date.now()<deadline) {
      try {
        const [port,endpoint]=(await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).trim().split(/\r?\n/);
        if(!/^\d+$/.test(port)||!/^\/devtools\/browser\/[a-f0-9-]+$/i.test(endpoint))throw new Error('Invalid endpoint');
        cdp=await CDP.open(`ws://127.0.0.1:${port}${endpoint}`);
        cdp.ws.addEventListener('message',event=>{
          try {if(JSON.parse(event.data).method==='Target.targetCrashed')finish('renderer-crashed');}catch{}
        });
        try {await cdp.call('Target.setDiscoverTargets',{discover:true});}catch{}
        cdp.ws.addEventListener('close',()=>finish('window-closed'),{once:true});return;
      }catch {await delay(100);}
    }
    if(!completed)finish('splash-connection-unavailable');
  })();
  trace.reason=await complete;
  await connection;
} catch(error) {
  trace.reason='splash-unavailable';
  console.error('Startup animation unavailable: '+error.message);
} finally {
  completed=true;
  clearInterval(heartbeatTimer);
  if(!started&&!preview)launch(true);
  if(cdp){try {await cdp.call('Browser.close',{},2000);}catch{}cdp.close();}
  if(browser&&!browser.killed)browser.kill();
  if(server){server.closeAllConnections();server.close();}
  await fs.rm(controlFile,{force:true});
  // Give the helper time to activate the verified app window. Never terminate the target app.
  let hostTimer;
  try {await Promise.race([hostDone,new Promise(resolve=>{hostTimer=setTimeout(resolve,5000);})]);}
  finally {clearTimeout(hostTimer);}
  if(host&&host.exitCode===null)host.kill();
  try {if(path.dirname(profile)===sessionRoot)await fs.rm(profile,{recursive:true,force:true});}catch{}
  trace.finishedAt=new Date().toISOString();trace.phase='finished';await save();
}
console.log(JSON.stringify({app,reason:trace.reason,launchFailed:!!trace.launchFailed}));
if(trace.launchFailed)process.exitCode=1;
