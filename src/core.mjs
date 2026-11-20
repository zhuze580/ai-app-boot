import path from 'node:path';

export function validateConfig(input={}) {
  const result={app:'Codex',volume:0.65,muted:false,readyMode:'accessible',...input};
  if(!['Codex','WorkBuddy'].includes(result.app))throw new Error('Unsupported app');
  if(!Number.isFinite(result.volume)||result.volume<0||result.volume>1)throw new Error('Invalid volume');
  if(result.readyMode!=='accessible')throw new Error('Ready mode must be accessible');
  if(typeof result.muted!=='boolean')throw new Error('Invalid muted setting');
  if(result.appPath!==undefined&&typeof result.appPath!=='string')throw new Error('Invalid appPath');
  if(result.media!==undefined)mediaPath('.',result.media);
  return result;
}

export function shouldFinish({appReady,filmEnded}) { return appReady===true&&filmEnded===true; }

export function mediaPath(root,name) {
  if(typeof name!=='string'||!name||name.includes('..')||/[\\/:\x00]/.test(name))throw new Error('Media must be a filename inside assets');
  return path.resolve(root,'assets',name);
}

export function parseRange(header,size) {
  if(!Number.isSafeInteger(size)||size<1)throw new Error('Empty media');
  if(header===undefined)return {start:0,end:size-1,partial:false};
  const match=/^bytes=(\d*)-(\d*)$/.exec(header);
  if(!match||(!match[1]&&!match[2]))throw new Error('Invalid range');
  const start=match[1]?Number(match[1]):Math.max(0,size-Number(match[2]));
  const end=match[1]&&match[2]?Math.min(Number(match[2]),size-1):size-1;
  if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start>end||start>=size)throw new Error('Invalid range');
  return {start,end,partial:true};
}
