import assert from 'node:assert/strict';
import test from 'node:test';

import { coreOf, fixtureGzip, fixtureJson, skip } from './support/wasm_fixture.mjs';

function loaded(core) {
  const { status, info } = core.load(fixtureJson);
  assert.equal(status, 0);
  return info;
}

function opaqueBytes(pixels) {
  let sum = 0;
  for (let i = 0; i < pixels.length; i += 4) sum += pixels[i + 3];
  return sum;
}

test('a frame renders tightly packed premultiplied RGBA', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const [result] = core.renderPixels([{ handle, frame: 0, width: 64, height: 48 }]);
  assert.equal(result.status, 0);
  assert.ok(result.pixels instanceof Uint8Array);
  assert.equal(result.pixels.length, 64 * 48 * 4);
  assert.ok(opaqueBytes(result.pixels) > 0, 'the square is visible');
  for (let i = 0; i < result.pixels.length; i += 4) {
    const alpha = result.pixels[i + 3];
    for (let c = 0; c < 3; c++) {
      assert.ok(result.pixels[i + c] <= alpha, `channel ${c} of pixel ${i / 4} is above alpha`);
    }
  }
  core.close();
});

test('the fill colour comes out as [R, G, B, A] in that order', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const [{ pixels }] = core.renderPixels([{ handle, frame: 0, width: 100, height: 100 }]);
  // The centre of the square: orange (1, .5, .25) at 50% alpha, premultiplied.
  const at = (50 * 100 + 50) * 4;
  const [r, g, b, a] = pixels.subarray(at, at + 4);
  assert.ok(Math.abs(a - 128) <= 2, `alpha ${a}`);
  assert.ok(r > g && g > b, `red ${r} > green ${g} > blue ${b}`);
  assert.ok(Math.abs(r - 128) <= 2 && Math.abs(g - 64) <= 2 && Math.abs(b - 32) <= 2);
  core.close();
});

test('a bad job gets -7 and the rest of the batch still renders', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const results = core.renderPixels([
    { handle, frame: 0, width: 32, height: 32 },
    { handle, frame: 0, width: 0, height: 32 },
    { handle, frame: 0, width: 513, height: 32 },
    { handle, frame: 10, width: 16, height: 16 },
  ]);
  assert.deepEqual(results.map((r) => r.status), [0, -7, -7, 0]);
  assert.equal(results[1].pixels, null);
  assert.equal(results[2].pixels, null);
  assert.equal(results[0].pixels.length, 32 * 32 * 4);
  assert.equal(results[3].pixels.length, 16 * 16 * 4);
  core.close();
});

test('a job larger than any frame is -7 without reserving it', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const [result] = core.renderPixels([{ handle, frame: 0, width: 2 ** 31, height: 2 ** 31 }]);
  assert.equal(result.status, -7);
  core.close();
});

test('results are copies: a later render does not change an earlier one', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const [first] = core.renderPixels([{ handle, frame: 0, width: 40, height: 40 }]);
  const kept = first.pixels.slice();
  core.renderPixels([{ handle, frame: 30, width: 40, height: 40 }]);
  assert.deepEqual(first.pixels, kept);
  assert.notEqual(first.pixels.buffer, core.exports.memory.buffer);
  core.close();
});

test('jobs of one size in one batch get separate regions', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const [a, b] = core.renderPixels([
    { handle, frame: 0, width: 40, height: 40 },
    { handle, frame: 59, width: 40, height: 40 },
  ]);
  assert.notDeepEqual(a.pixels, b.pixels);
  core.close();
});

test('both wasm builds draw the same frame within one colour level', { skip }, async () => {
  const simd = await coreOf('chat_lottie.wasm');
  const plain = await coreOf('chat_lottie.nosimd.wasm');
  const a = loaded(simd);
  const b = loaded(plain);
  for (const frame of [0, 17, 45]) {
    const [x] = simd.renderPixels([{ handle: a.handle, frame, width: 96, height: 96 }]);
    const [y] = plain.renderPixels([{ handle: b.handle, frame, width: 96, height: 96 }]);
    assert.equal(x.status, 0);
    assert.equal(y.status, 0);
    let worst = 0;
    for (let i = 0; i < x.pixels.length; i++) {
      worst = Math.max(worst, Math.abs(x.pixels[i] - y.pixels[i]));
    }
    assert.ok(worst <= 1, `frame ${frame} differs by ${worst}`);
  }
  simd.close();
  plain.close();
});

test('scratch regions are reused: memory is stable over 200 renders', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const job = { handle, frame: 0, width: 128, height: 128 };
  // The module's own allocator (tlottie's per-frame working set) settles over
  // the first few passes through the animation: warm up past that, then any
  // growth left is ours.
  for (let i = 0; i < 240; i++) core.renderPixels([{ ...job, frame: i % 60 }]);
  const settled = core.exports.memory.buffer.byteLength;
  for (let i = 0; i < 200; i++) {
    const [result] = core.renderPixels([{ ...job, frame: i % 60 }]);
    assert.equal(result.status, 0);
  }
  assert.equal(core.exports.memory.buffer.byteLength, settled);
  core.close();
});

test('dispose is safe, idempotent, and a disposed handle fails softly', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  core.dispose(handle);
  core.dispose(handle);
  core.dispose(123456); // never issued
  const [result] = core.renderPixels([{ handle, frame: 0, width: 32, height: 32 }]);
  assert.equal(result.status, -1);
  assert.equal(result.pixels, null);
  // The module is still healthy.
  const again = loaded(core);
  assert.equal(core.renderPixels([{ handle: again.handle, frame: 0, width: 8, height: 8 }])[0].status, 0);
  core.close();
});

test('close frees every handle and the core refuses further calls', { skip }, async () => {
  const core = await coreOf();
  loaded(core);
  core.close();
  core.close();
  assert.throws(() => core.load(fixtureGzip), /closed/);
  assert.throws(() => core.renderPixels([]), /closed/);
});

test('an empty batch is an empty result', { skip }, async () => {
  const core = await coreOf();
  assert.deepEqual(core.renderPixels([]), []);
  core.close();
});

test('compress then decompress a region is exact', { skip }, async () => {
  const core = await coreOf();
  const wasm = core.exports;
  const [width, height] = [37, 29];
  const size = width * height * 4;
  const source = new Uint8Array(size).map((_, i) => (i * 31 + (i >> 5)) & 0xff);
  const bound = wasm.chat_lottie_lz4_bound(width, height);
  assert.ok(bound >= size);
  const src = wasm.chat_lottie_alloc(size);
  const dst = wasm.chat_lottie_alloc(bound);
  const lenPtr = wasm.chat_lottie_alloc(4);
  const back = wasm.chat_lottie_alloc(size);
  new Uint8Array(wasm.memory.buffer).set(source, src);
  assert.equal(wasm.chat_lottie_compress_region(src, width * 4, width, height, dst, bound, lenPtr), 0);
  const packed = new DataView(wasm.memory.buffer).getUint32(lenPtr, true);
  assert.equal(wasm.chat_lottie_decompress_region(dst, packed, back, width * 4, width, height), 0);
  assert.deepEqual(new Uint8Array(wasm.memory.buffer, back, size).slice(), source);
  // A corrupt stream is -3 and leaves the region as it was.
  new Uint8Array(wasm.memory.buffer, dst, packed).fill(0xff);
  new Uint8Array(wasm.memory.buffer, back, size).fill(7);
  assert.equal(wasm.chat_lottie_decompress_region(dst, packed, back, width * 4, width, height), -3);
  assert.ok(new Uint8Array(wasm.memory.buffer, back, size).every((v) => v === 7));
  core.close();
});

test('the allocator refuses 0 and over 16 MiB, and gives 16 MiB itself', { skip }, async () => {
  const core = await coreOf();
  const cap = 16 * 1024 * 1024;
  assert.equal(core.exports.chat_lottie_alloc(0), 0);
  assert.equal(core.exports.chat_lottie_alloc(cap + 1), 0);
  const whole = core.exports.chat_lottie_alloc(cap);
  assert.notEqual(whole, 0);
  core.exports.chat_lottie_dealloc(whole, cap);
  core.close();
});

test('idle scratch is kept by size, bounded, and freed on close', { skip }, async () => {
  const core = await coreOf();
  const { handle } = loaded(core);
  const job = { handle, frame: 0, width: 128, height: 128 };
  core.renderPixels([job]);
  const kept = core.pooledBytes;
  assert.ok(kept >= 128 * 128 * 4, `kept ${kept}`);
  for (let i = 0; i < 50; i++) core.renderPixels([job]);
  assert.equal(core.pooledBytes, kept, 'the same regions are borrowed again');
  // Many distinct big frames in one batch would exceed the idle limit.
  const big = Array.from({ length: 40 }, () => ({ ...job, width: 512, height: 512 }));
  core.renderPixels(big);
  assert.ok(core.pooledBytes <= 16 * 1024 * 1024);
  core.close();
  assert.equal(core.pooledBytes, 0);
});

// --- Opaque handles --------------------------------------------------------

test('handles are small increasing integers, never the module pointers', { skip }, async () => {
  const core = await coreOf();
  const ids = [loaded(core).handle, loaded(core).handle, loaded(core).handle];
  assert.deepEqual(ids, [1, 2, 3]);
  core.close();
});

test('a freed id is never reused: a stale id cannot reach a later animation', { skip }, async () => {
  const core = await coreOf();
  const stale = loaded(core).handle;
  core.dispose(stale);
  // The module is free to hand the same memory to the next load; the id
  // must still differ, or the stale id would draw the new animation.
  const fresh = loaded(core).handle;
  assert.notEqual(fresh, stale);
  const before = core.renderPixels([{ handle: fresh, frame: 7, width: 24, height: 24 }]);
  const [result] = core.renderPixels([{ handle: stale, frame: 7, width: 24, height: 24 }]);
  assert.equal(result.status, -1);
  assert.equal(result.pixels, null);
  const after = core.renderPixels([{ handle: fresh, frame: 7, width: 24, height: 24 }]);
  assert.deepEqual(after[0].pixels, before[0].pixels, 'the new animation is untouched');
  // Disposing the stale id again must not free the new animation either.
  core.dispose(stale);
  assert.equal(core.renderPixels([{ handle: fresh, frame: 7, width: 24, height: 24 }])[0].status, 0);
  core.close();
});
