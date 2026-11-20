/* Local, disposable video overlay. This file never reads the chat or changes its theme. */
(function () {
  'use strict';
  if(window.CodexStartup?.version===2||window.CodexStartup?.status?.().active)return;
  const ROOT='codex-reference-startup';
  let session=null,last={phase:'idle',reason:null};

  function status(){
    if(!session)return {...last,active:false};
    return {active:true,phase:session.phase,currentTime:session.video.currentTime||0,
      duration:session.video.duration||session.duration,muted:session.video.muted,
      reason:null,hasFrame:session.video.readyState>=2};
  }

  function dispose(s,reason){
    if(session!==s)return;
    for(const timer of s.timers)clearTimeout(timer);
    s.video.pause();
    s.video.removeAttribute('src');s.video.load();
    if(s.url)URL.revokeObjectURL(s.url);
    s.abort.abort();
    const restoreFocus=document.activeElement===s.host||document.activeElement===document.body;
    s.host.remove();
    session=null;last={phase:'finished',reason};
    if(restoreFocus&&s.previousFocus?.isConnected)s.previousFocus.focus({preventScroll:true});
  }

  function hold(s){
    if(session!==s||s.phase==='closing')return;
    s.phase='holding';
    s.video.pause();
    try{if(Number.isFinite(s.video.duration)&&s.video.duration>0)s.video.currentTime=Math.max(0,s.video.duration-.05);}catch{}
    s.shell.classList.add('ready');
  }

  function stop(reason='skipped',immediate=false){
    const s=session;if(!s||s.phase==='closing')return status();
    s.phase='closing';s.video.pause();
    // Remove the overlay in the same frame. A fade exposes the Codex page and
    // creates the flashing transition the user sees at the handoff.
    dispose(s,reason);
    return status();
  }

  async function mount(options={}){
    if(session)return {ok:true,duplicate:true,...status()};
    if(document.getElementById(ROOT))return {ok:false,error:'existing-overlay'};
    const duration=Number(options.duration);
    if(!Number.isFinite(duration)||duration<1||duration>60)return {ok:false,error:'duration'};
    const host=document.createElement('div');host.id=ROOT;
    host.tabIndex=-1;
    Object.assign(host.style,{position:'fixed',inset:'0',zIndex:'2147483500',display:'block',
      pointerEvents:'auto',isolation:'isolate'});
    const shadow=host.attachShadow({mode:'open'});
    shadow.innerHTML=`<style>
      :host{all:initial;color-scheme:dark}
      *{box-sizing:border-box}
      .shell{position:absolute;inset:0;background:#06060d;opacity:1;overflow:hidden}
      .shell.ready{opacity:1}.shell.closing{opacity:1}
      video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;background:#06060d;display:block}
      .tools,.hint{display:none!important}
      button{font:12px 'Microsoft YaHei UI',sans-serif;color:#eee8ff;background:rgba(24,17,36,.76);
        border:1px solid rgba(216,195,255,.3);border-radius:6px;padding:8px 12px;cursor:pointer}
      button:focus-visible{outline:2px solid #c5a5f2;outline-offset:3px}
      .hint{position:absolute;left:24px;bottom:16px;font:11px 'Microsoft YaHei UI',sans-serif;
        color:rgba(223,213,240,.45);pointer-events:none}
      @media(prefers-reduced-motion:reduce){.shell,.shell.closing{transition:none}}
    </style><div class="shell"><video playsinline preload="auto"></video>
      <div class="tools"><button type="button" class="mute" aria-label="关闭动画声音">声音：开</button>
      <button type="button" class="skip" aria-label="跳过启动动画">跳过 · Esc</button></div>
      <div class="hint">启动片头 · Esc 可跳过</div></div>`;
    const shell=shadow.querySelector('.shell'),video=shadow.querySelector('video');
    const abort=new AbortController();
    const s=session={host,shadow,shell,video,abort,timers:[],duration,url:null,phase:'loading',previousFocus:document.activeElement};
    video.volume=Math.max(0,Math.min(1,Number(options.volume??0.65)));
    video.muted=!!options.muted;
    const mute=shadow.querySelector('.mute');
    function muteLabel(){mute.textContent=video.muted?'声音：关':'声音：开';mute.setAttribute('aria-label',video.muted?'打开动画声音':'关闭动画声音');}
    muteLabel();
    shadow.querySelector('.skip').addEventListener('click',()=>stop('skipped'),{signal:abort.signal});
    mute.addEventListener('click',()=>{video.muted=!video.muted;muteLabel();},{signal:abort.signal});
    const skip=shadow.querySelector('.skip');
    window.addEventListener('keydown',e=>{
      e.preventDefault();e.stopImmediatePropagation();
      if(e.key==='Escape')stop('escape');
      else if(e.key==='Tab'){
        const buttons=[mute,skip],index=buttons.indexOf(shadow.activeElement);
        buttons[(index+(e.shiftKey?-1:1)+buttons.length)%buttons.length].focus({preventScroll:true});
      }else if(e.key==='Enter'||e.key===' '){
        const control=shadow.activeElement;
        if(control===mute||control===skip)control.click();
      }
    },{capture:true,signal:abort.signal});
    document.addEventListener('focusin',()=>{
      if(session===s&&s.phase!=='closing'&&document.activeElement!==host)skip.focus({preventScroll:true});
    },{capture:true,signal:abort.signal});
    video.addEventListener('ended',()=>options.holdAtEnd?hold(s):stop('ended'),{signal:abort.signal});
    video.addEventListener('error',()=>stop('media-error',true),{signal:abort.signal});
    s.timers.push(setTimeout(()=>{if(session===s&&s.phase==='loading')stop('load-timeout',true);},8000));
    document.documentElement.appendChild(host);
    host.focus({preventScroll:true});
    try{
      if(options.base64){
        const text=atob(options.base64),bytes=new Uint8Array(text.length);
        for(let i=0;i<text.length;i++)bytes[i]=text.charCodeAt(i);
        s.url=URL.createObjectURL(new Blob([bytes],{type:options.mime||'video/mp4'}));
        video.src=s.url;
      }else if(options.url){
        // Standalone local preview only. Runtime injection always supplies verified bytes.
        const url=new URL(options.url,location.href);
        if(!['file:','http:'].includes(url.protocol)||url.protocol==='http:'&&!['127.0.0.1','localhost'].includes(url.hostname))throw new Error('url');
        video.src=url.href;
      }else throw new Error('media');
      video.addEventListener('canplay',async()=>{
        if(session!==s||s.phase!=='loading')return;
        try{
          if(!Number.isFinite(video.duration)||video.duration<1||video.duration>60){stop('media-duration',true);return;}
          const budget=Math.min(duration,video.duration)+10;
          s.timers.push(setTimeout(()=>{
            if(session===s&&s.phase!=='holding')stop('playback-timeout',true);
          },Math.ceil(budget*1000)));
          try{await video.play();}
          catch{video.muted=true;muteLabel();await video.play();}
          if(session!==s||s.phase!=='loading')return;
          s.phase='playing';shell.classList.add('ready');
        }catch{stop('play-rejected',true);}
      },{once:true,signal:abort.signal});
      video.load();
      return {ok:true,...status()};
    }catch{stop('media-error',true);return {ok:false,error:'media'};}
  }
  window.CodexStartup={version:2,mount,stop,status};
})();
