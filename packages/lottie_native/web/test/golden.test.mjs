import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { coreOf, fixtureJson, skip } from './support/wasm_fixture.mjs';

// The reference frame is drawn by the host (native) build and committed, see
// native/tests/golden.rs for how it is made and regenerated. Both wasm builds
// must draw the same frame within one colour level per channel, so a drift
// between the native and web renderers fails here.
const golden = readFileSync(
  new URL('../../native/tests/fixtures/golden_64x64_frame_30.rgba', import.meta.url),
);

for (const [name, file] of [
  ['SIMD', 'chat_lottie.wasm'],
  ['plain', 'chat_lottie.nosimd.wasm'],
]) {
  test(`the ${name} wasm build draws the golden frame within one level`, { skip }, async () => {
    const core = await coreOf(file);
    const { info } = core.load(fixtureJson);
    const [result] = core.renderPixels([{ handle: info.handle, frame: 30, width: 64, height: 64 }]);
    core.close();
    assert.equal(result.status, 0);
    assert.equal(result.pixels.length, golden.length);
    let worst = 0;
    for (let i = 0; i < golden.length; i++) {
      worst = Math.max(worst, Math.abs(result.pixels[i] - golden[i]));
    }
    assert.ok(worst <= 1, `the ${name} build differs from the golden by ${worst} levels`);
  });
}

test('the golden is 64 x 64 premultiplied RGBA with a visible square', () => {
  assert.equal(golden.length, 64 * 64 * 4);
  let visible = 0;
  for (let i = 0; i < golden.length; i += 4) {
    const alpha = golden[i + 3];
    if (alpha > 0) visible++;
    for (let c = 0; c < 3; c++) assert.ok(golden[i + c] <= alpha);
  }
  assert.ok(visible > 0 && visible < 64 * 64);
});
