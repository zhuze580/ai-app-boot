// Real Chromium media/lifecycle integration, using an isolated Edge profile and local assets.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {CDP} from '../src/cdp.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const profile=await fs.mkdtemp(path.join(os.tmpdir(),'codex-startup-browser-'));
const video=await fs.readFile(path.join(root,'assets/intro.mp4'));
const player=await fs.readFile(path.join(root,'src/player.js'),'utf8');
const server=http.createServer((req,res)=>{
  if(req.url==='/intro.mp4'){
    res.setHeader('Content-Type','video/mp4');res.setHeader('Accept-Ranges','bytes');
    const range=/bytes=(\d+)-(\d*)/.exec(req.headers.range||'');
    if(range){const start=Number(range[1]),end=range[2]?Math.min(Number(range[2]),video.length-1):video.length-1;
      res.writeHead(206,{'Content-Range':`bytes ${start}-${end}/${video.length}`,'Content-Length':end-start+1});res.end(video.subarray(start,end+1));}
    else{res.writeHead(200,{'Content-Length':video.length});res.end(video);}
  }else{res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html><head><title>Startup test</title></head><body><button id="sentinel">Native page remains</button><input id="draft"></body></html>');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin='http://127.0.0.1:'+server.address().port;
const candidates=[process.env.PROGRAMFILES+'\\Microsoft\\Edge\\Application\\msedge.exe',
  process.env['PROGRAMFILES(X86)']+'\\Microsoft\\Edge\\Application\\msedge.exe'];
let edge;for(const f of candidates){try{await fs.access(f);edge=f;break;}catch{}}
if(!edge)throw new Error('Microsoft Edge is required for real-browser integration tests');
const browser=spawn(edge,['--headless=new','--no-first-run','--disable-background-networking',
  '--autoplay-policy=no-user-gesture-required','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],
  {windowsHide:true,stdio:'ignore'});
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let cdp;
async function until(expression,timeout=6000){
  const end=Date.now()+timeout;
  while(Date.now()<end){const v=await cdp.evaluate(expression);if(v)return v;await delay(70);}
  throw new Error('Browser condition timed out: '+expression);
}
try{
  let port;
  for(let i=0;i<100;i++){
    try{port=Number((await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0]);break;}catch{await delay(120);}
  }
  assert.ok(port,'isolated browser opened its debugger');
  const targets=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  cdp=await CDP.open(targets.find(t=>t.type==='page').webSocketDebuggerUrl);
  await cdp.call('Page.navigate',{url:origin});
  await until('!!document.getElementById("sentinel")');
  await cdp.evaluate(player);
  await cdp.evaluate('document.getElementById("draft").focus();window.hiddenKeys=0;document.addEventListener("keydown",()=>window.hiddenKeys++)');
  const mount=async(options={})=>cdp.evaluate(`window.CodexStartup.mount(${JSON.stringify({url:origin+'/intro.mp4',duration:14.2,muted:true,...options})})`);
  const status=()=>cdp.evaluate('window.CodexStartup.status()');
  const gone=()=>until('!window.CodexStartup.status().active && !document.getElementById("codex-reference-startup")');
  assert.equal((await mount()).ok,true);
  await until('window.CodexStartup.status().phase==="playing"');
  assert.equal(await cdp.evaluate('getComputedStyle(document.getElementById("codex-reference-startup").shadowRoot.querySelector(".tools")).display'),'none');
  assert.equal(await cdp.evaluate('getComputedStyle(document.getElementById("codex-reference-startup").shadowRoot.querySelector(".hint")).display'),'none');
  assert.equal(await cdp.evaluate('getComputedStyle(document.getElementById("codex-reference-startup").shadowRoot.querySelector("video")).objectFit'),'cover');
  const s=await status();assert.ok(s.duration>14&&s.duration<14.4);assert.ok(s.hasFrame);
  assert.equal((await mount()).duplicate,true);
  assert.equal(await cdp.evaluate('document.querySelectorAll("#codex-reference-startup").length'),1);
  console.log('PASS: real H.264 decoded, duration confirmed, duplicate mount refused');
  assert.equal(await cdp.evaluate('document.activeElement.id'),'codex-reference-startup');
  await cdp.call('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',text:'a'});
  await cdp.call('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA'});
  assert.equal(await cdp.evaluate('document.getElementById("draft").value'),'');
  assert.equal(await cdp.evaluate('window.hiddenKeys'),0);
  await cdp.call('Input.dispatchKeyEvent',{type:'keyDown',key:'Tab',code:'Tab'});
  assert.equal(await cdp.evaluate('document.activeElement.id'),'codex-reference-startup');
  console.log('PASS: focus stays in player and typing cannot reach underlying chat or handlers');
  await cdp.evaluate('document.dispatchEvent(new KeyboardEvent("keydown",{key:"Escape",bubbles:true,cancelable:true}))');
  await gone();assert.equal((await status()).reason,'escape');
  assert.equal(await cdp.evaluate('document.activeElement.id'),'draft');
  assert.equal(await cdp.evaluate('document.getElementById("sentinel").textContent'),'Native page remains');
  console.log('PASS: Escape removes overlay and preserves underlying page');
  await mount();await until('window.CodexStartup.status().phase==="playing"');
  await cdp.evaluate('document.getElementById("codex-reference-startup").shadowRoot.querySelector("video").currentTime=13.9');
  await gone();assert.equal((await status()).reason,'ended');
  console.log('PASS: natural media ended event cleans up');
  await mount({holdAtEnd:true,duration:1});await until('window.CodexStartup.status().phase==="playing"');
  await cdp.evaluate('document.getElementById("codex-reference-startup").shadowRoot.querySelector("video").currentTime=13.9');
  await until('window.CodexStartup.status().phase==="holding"');
  assert.equal((await status()).active,true);assert.ok((await status()).currentTime>14);
  await delay(11200);assert.equal((await status()).phase,'holding');assert.equal((await status()).hasFrame,true);
  await cdp.evaluate('window.CodexStartup.stop("codex-ready",true)');await gone();
  console.log('PASS: startup holds last decoded frame until explicitly released by app readiness');
  await mount({base64:'dGhpcyBpcyBub3QgYSB2aWRlbw=='});
  await gone();assert.equal((await status()).reason,'media-error');
  console.log('PASS: corrupt media fails open');
  await mount();await until('window.CodexStartup.status().phase==="playing"');
  await cdp.evaluate('document.getElementById("codex-reference-startup").shadowRoot.querySelector(".skip").click()');
  await gone();assert.equal((await status()).reason,'skipped');
  console.log('PASS: skip control cleans up');
  await mount({duration:1});await until('window.CodexStartup.status().phase==="playing"');
  await cdp.evaluate('document.getElementById("codex-reference-startup").shadowRoot.querySelector("video").loop=true');
  await goneWithTimeout();
  assert.equal((await status()).reason,'playback-timeout');
  console.log('PASS: independent wall-clock timeout releases a looping player');
  await mount({duration:1,holdAtEnd:true});await until('window.CodexStartup.status().phase==="playing"');
  await cdp.evaluate('document.getElementById("codex-reference-startup").shadowRoot.querySelector("video").loop=true');
  await goneWithTimeout();
  assert.equal((await status()).reason,'playback-timeout');
  console.log('PASS: production hold mode still releases a stalled or looping film');
  async function goneWithTimeout(){await until('!window.CodexStartup.status().active',13000);}
  assert.equal(await cdp.evaluate('document.querySelectorAll("#codex-reference-startup").length'),0);
  console.log('PASS: no residual overlay; browser integration complete');
}finally{
  if(cdp){try{await cdp.call('Browser.close',{},1500);}catch{}cdp.close();}
  browser.kill();server.close();
}
