import {CDP} from './cdp.mjs';
// Optional existing DreamSkin connection only. Native host verifies the listener owner/executable.
export async function codexReady(state) {
  if(!Number.isInteger(state?.port)||state.port<1024||state.port>65535||!/^[a-f0-9-]{36}$/i.test(state.browserId||''))return false;
  let cdp;
  try {
    const origin='http://127.0.0.1:'+state.port;
    const read=async suffix=>{const r=await fetch(origin+suffix,{signal:AbortSignal.timeout(1500),redirect:'error'});if(!r.ok)throw Error();return r.json();};
    const version=await read('/json/version');
    if(version.webSocketDebuggerUrl!==`ws://127.0.0.1:${state.port}/devtools/browser/${state.browserId}`)return false;
    const pages=(await read('/json/list')).filter(t=>t.type==='page'&&t.url==='app://-/index.html');
    if(pages.length!==1)return false;
    const endpoint=new URL(pages[0].webSocketDebuggerUrl);
    if(endpoint.protocol!=='ws:'||endpoint.hostname!=='127.0.0.1'||Number(endpoint.port)!==state.port||!endpoint.pathname.startsWith('/devtools/page/')||endpoint.username||endpoint.password||endpoint.search||endpoint.hash)return false;
    cdp=await CDP.open(endpoint.href);
    return await cdp.evaluate(`(()=>{
      const visible=e=>e.isConnected&&e.getClientRects().length>0&&getComputedStyle(e).visibility!=='hidden'&&getComputedStyle(e).display!=='none';
      const editor=[...document.querySelectorAll('[contenteditable=true],textarea')].some(e=>visible(e)&&!e.disabled&&!e.readOnly&&e.getAttribute('aria-disabled')!=='true');
      const navigation=[...document.querySelectorAll('button,a,[role=button]')].some(e=>visible(e)&&!e.disabled&&/^(New chat|Search|新对话|新建任务|搜索)/i.test(e.getAttribute('aria-label')||e.getAttribute('title')||''));
      return location.origin==='app://-'&&!!document.querySelector('main')&&editor&&navigation;
    })()`,1800)===true;
  }catch{return false;}finally{cdp?.close();}
}
