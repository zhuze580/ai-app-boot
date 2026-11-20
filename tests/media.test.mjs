import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
test('downloads contain the exact original Codex clip with its audio and duration',async()=>{
  const data=await fs.readFile(new URL('../assets/intro.mp4',import.meta.url));
  const manifest=JSON.parse(await fs.readFile(new URL('../assets/intro.json',import.meta.url),'utf8'));
  assert.equal(createHash('sha256').update(data).digest('hex'),'0d6069a477dd55d97bc724db2dbb8749fbc3508bc2cf8e1d4153f1fa86f0471f');
  assert.equal(data.length,manifest.size);
  assert.equal(manifest.duration,14.2);
  assert.equal(manifest.audio,true);
});
