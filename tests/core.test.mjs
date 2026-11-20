import test from 'node:test';
import assert from 'node:assert/strict';
import {validateConfig,shouldFinish,parseRange,mediaPath} from '../src/core.mjs';

test('both real applications are supported without machine-specific configuration',()=>{
  for(const app of ['Codex','WorkBuddy']) {
    const config=validateConfig({app});
    assert.equal(config.app,app);
    assert.equal(config.volume,0.65);
  }
  assert.throws(()=>validateConfig({app:'Other'}));
  assert.throws(()=>validateConfig({app:'Codex',volume:2}));
  assert.throws(()=>validateConfig({app:'Codex',readyMode:'timer'}));
});

test('an early ready page never truncates the film, and a late page holds the last frame',()=>{
  assert.equal(shouldFinish({appReady:true,filmEnded:false}),false);
  assert.equal(shouldFinish({appReady:false,filmEnded:true}),false);
  assert.equal(shouldFinish({appReady:false,filmEnded:false}),false);
  assert.equal(shouldFinish({appReady:true,filmEnded:true}),true);
});

test('media stays within assets and supports Unicode filenames',()=>{
  assert.ok(mediaPath('/project','开场.mp4').endsWith('开场.mp4'));
  for(const name of ['../secret','a/b.mp4','a\\b.mp4','C:\\file.mp4','',null])
    assert.throws(()=>mediaPath('/project',name));
});

test('byte ranges are bounded, including suffixes and malformed requests',()=>{
  assert.deepEqual(parseRange(undefined,100),{start:0,end:99,partial:false});
  assert.deepEqual(parseRange('bytes=10-',100),{start:10,end:99,partial:true});
  assert.deepEqual(parseRange('bytes=10-999',100),{start:10,end:99,partial:true});
  assert.deepEqual(parseRange('bytes=-10',100),{start:90,end:99,partial:true});
  for(const value of ['bytes=100-','bytes=20-10','bytes=foo','bytes=0-1,4-5','bytes=-0'])
    assert.throws(()=>parseRange(value,100));
});
