import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import { builtWasm, findDart, runBuildTool } from './support/built_wasm.mjs';

const built = builtWasm();
const skip = built.skip;

test('the tool writes both wasm builds and the JS files', { skip }, () => {
  for (const name of [
    'chat_lottie.wasm',
    'chat_lottie.nosimd.wasm',
    'chat_lottie_core.mjs',
    'chat_lottie_worker.js',
  ]) {
    assert.ok(existsSync(join(built.dir, name)), `${name} was written`);
    assert.ok(statSync(join(built.dir, name)).size > 0, `${name} is not empty`);
  }
});

test('both builds validate, export the allocator and import nothing', { skip }, () => {
  for (const name of ['chat_lottie.wasm', 'chat_lottie.nosimd.wasm']) {
    const module = new WebAssembly.Module(readFileSync(join(built.dir, name)));
    const exports = WebAssembly.Module.exports(module).map((e) => e.name);
    for (const symbol of ['memory', 'chat_lottie_alloc', 'chat_lottie_dealloc', 'chat_lottie_load']) {
      assert.ok(exports.includes(symbol), `${name} exports ${symbol}`);
    }
    assert.deepEqual(WebAssembly.Module.imports(module), []);
  }
});

// The dart launcher is a shell script that needs the system directories, so
// the PATH keeps those and dart's own directory; cargo is in none of them
// unless the system packages installed it (then there is nothing to test).
const systemCargo = ['/usr/bin/cargo', '/bin/cargo'].some(existsSync);
const noCargoSkip = (!findDart() && 'dart is not on PATH') || (systemCargo && 'cargo is a system binary');

test('without cargo the tool says how to get it and exits non-zero', { skip: noCargoSkip }, () => {
  const home = mkdtempSync(join(tmpdir(), 'no_cargo_home_'));
  const out = mkdtempSync(join(tmpdir(), 'no_cargo_out_'));
  const run = runBuildTool(out, { HOME: home, PATH: `${dirname(findDart())}:/usr/bin:/bin` });
  assert.notEqual(run.status, 0);
  assert.match(run.stdout + run.stderr, /cargo was not found[\s\S]*rustup\.rs/);
});
