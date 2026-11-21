import test from 'node:test';
import assert from 'node:assert/strict';
import {restoreTheme} from '../src/theme-session.mjs';
test('theme reconnect rejects invalid identities before opening files or starting a watcher',async()=>{
  for(const value of [null,{}, {port:80,browserId:'a'.repeat(36)}, {port:9335,browserId:'../../other'}, {port:'9335',browserId:'a'.repeat(36)}])
    assert.equal(await restoreTheme(value),false);
});
