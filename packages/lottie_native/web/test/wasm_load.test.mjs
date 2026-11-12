import assert from 'node:assert/strict';
import test from 'node:test';

import { coreOf, fixtureGzip, fixtureJson, skip } from './support/wasm_fixture.mjs';

test('the module loads and reports ABI version 1', { skip }, async () => {
  const core = await coreOf();
  assert.equal(core.abiVersion, 1);
  core.close();
});

test('a JSON file and its gzip load to the same info', { skip }, async () => {
  const core = await coreOf();
  const json = core.load(fixtureJson);
  const gz = core.load(fixtureGzip);
  assert.equal(json.status, 0);
  assert.equal(gz.status, 0);
  const { handle: jsonHandle, ...jsonInfo } = json.info;
  const { handle: gzHandle, ...gzInfo } = gz.info;
  assert.deepEqual(jsonInfo, {
    width: 100,
    height: 100,
    frameCount: 60,
    frameRate: 30,
    features: 0,
  });
  assert.deepEqual(gzInfo, jsonInfo);
  assert.equal(typeof jsonHandle, 'number');
  assert.notEqual(jsonHandle, 0);
  assert.notEqual(jsonHandle, gzHandle);
  core.close();
});

test('garbage and a truncated gzip fail with -3 and never throw', { skip }, async () => {
  const core = await coreOf();
  const garbage = core.load(new TextEncoder().encode('this is not lottie'));
  assert.deepEqual(garbage, { status: -3 });
  const truncated = core.load(fixtureGzip.subarray(0, fixtureGzip.length >> 1));
  assert.deepEqual(truncated, { status: -3 });
  assert.deepEqual(core.load(new Uint8Array(0)), { status: -3 });
  core.close();
});

test('input over the 4 MiB cap is -2', { skip }, async () => {
  const core = await coreOf();
  assert.deepEqual(core.load(new Uint8Array(4 * 1024 * 1024 + 1)), { status: -2 });
  core.close();
});
