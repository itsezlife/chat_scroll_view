import assert from 'node:assert/strict';
import test from 'node:test';

import { SIMD_PROBE_BYTES, selectWasm } from '../chat_lottie_core.mjs';

const urls = { simd: 'chat_lottie.wasm', noSimd: 'chat_lottie.nosimd.wasm' };

test('picks the SIMD build only when the probe module validates', () => {
  const seen = [];
  const picked = selectWasm((bytes) => (seen.push(bytes), true), urls);
  assert.deepEqual(picked, { url: 'chat_lottie.wasm', simd: true });
  assert.deepEqual(seen, [SIMD_PROBE_BYTES]);
});

test('falls back to the no-SIMD build when validation fails', () => {
  assert.deepEqual(
    selectWasm(() => false, urls),
    { url: 'chat_lottie.nosimd.wasm', simd: false },
  );
});

test('a validator that throws counts as no SIMD', () => {
  const picked = selectWasm(() => {
    throw new Error('no WebAssembly');
  }, urls);
  assert.equal(picked.simd, false);
});

test('the probe is a real v128 module: this runtime validates it', () => {
  assert.equal(WebAssembly.validate(SIMD_PROBE_BYTES), true);
});

test('the probe is rejected when its v128 opcode is damaged', () => {
  const damaged = SIMD_PROBE_BYTES.slice();
  damaged[damaged.indexOf(0xfd)] = 0xfe; // an opcode prefix that does not exist
  assert.equal(WebAssembly.validate(damaged), false);
});
