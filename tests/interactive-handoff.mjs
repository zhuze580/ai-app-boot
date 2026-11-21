// Real local Codex test on the primary monitor at (0,0), as used by the local
// fullscreen regression. Clicks only the editor; never types or sends a message.
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {CDP} from '../src/cdp.mjs';
const state=JSON.parse(await fs.readFile(path.join(process.env.LOCALAPPDATA,'CodexDreamSkin/state.json'),'utf8'));
const origin='http://127.0.0.1:'+state.port;
const targets=await(await fetch(origin+'/json/list')).json();
const main=targets.filter(t=>t.type==='page'&&t.url==='app://-/index.html');
assert.equal(main.length,1);
const cdp=await CDP.open(main[0].webSocketDebuggerUrl);
try {
  const point=await cdp.evaluate(`(()=>{const e=[...document.querySelectorAll('[contenteditable=true],textarea')].find(e=>e.getClientRects().length&&!e.disabled);if(!e)return null;const r=e.getBoundingClientRect();e.blur();return {x:Math.round((r.left+r.width/2)*devicePixelRatio),y:Math.round((r.top+Math.min(r.height/2,20))*devicePixelRatio)};})()`);
  assert.ok(point);
  assert.ok(Number.isInteger(point.x)&&Number.isInteger(point.y));
  execFileSync('powershell.exe',['-NoProfile','-Command',`Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class AppBootClick{[DllImport("user32.dll")]public static extern bool SetProcessDpiAwarenessContext(IntPtr c);[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);}';[AppBootClick]::SetProcessDpiAwarenessContext([IntPtr](-4))|Out-Null;[AppBootClick]::SetCursorPos(${point.x},${point.y})|Out-Null;[AppBootClick]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[AppBootClick]::mouse_event(4,0,0,0,[UIntPtr]::Zero)`],{windowsHide:true});
  await new Promise(r=>setTimeout(r,300));
  assert.equal(await cdp.evaluate(`document.hasFocus()&&!document.hidden&&!!document.activeElement?.closest('[contenteditable=true],textarea')`),true);
  console.log('PASS: physical mouse click focuses live Codex editor after handoff; no text sent');
}finally{cdp.close();}
