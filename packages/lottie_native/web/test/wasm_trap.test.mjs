import assert from 'node:assert/strict';
import test from 'node:test';

import { STATUS } from '../chat_lottie_core.mjs';
import { createWorkerHandler } from '../chat_lottie_worker.js';
import { coreOf, fixtureGzip, fixtureJson, skip } from './support/wasm_fixture.mjs';

// wasm32 cannot unwind, so a Rust panic is a trap: `WebAssembly.RuntimeError`,
// not a status. A real trap is forced by calling the real export with an
// address outside the module's memory, from the call path the core uses.
const OUTSIDE_MEMORY = 0xfffffff0;

/**
 * A core whose next call of [exportName] traps for real, once. Returns the
 * core and `arm()`, which makes the next call trap.
 */
async function coreThatCanTrap(exportName) {
  let armed = false;
  const core = await coreOf('chat_lottie.wasm', {
    wrapExports: (exports) => ({
      ...exports,
      [exportName]: (...args) => {
        if (!armed) return exports[exportName](...args);
        armed = false;
        return exports[exportName](...args.map(() => OUTSIDE_MEMORY));
      },
    }),
  });
  return { core, arm: () => (armed = true) };
}

function loaded(core) {
  const { status, info } = core.load(fixtureJson);
  assert.equal(status, 0);
  return info;
}

const job = (handle, frame = 3) => ({ handle, frame, width: 32, height: 32 });

test('the forced trap really is a WebAssembly.RuntimeError from the module', { skip }, async () => {
  const core = await coreOf();
  assert.throws(
    () => core.exports.chat_lottie_render_batch(OUTSIDE_MEMORY, 1, OUTSIDE_MEMORY),
    WebAssembly.RuntimeError,
  );
});

test('a trap in render fails that batch with INTERNAL and the next request works', { skip }, async () => {
  const { core, arm } = await coreThatCanTrap('chat_lottie_render_batch');
  const before = loaded(core);
  const memoryBefore = core.exports.memory;
  assert.equal(core.renderPixels([job(before.handle)])[0].status, 0);

  arm();
  const trapped = core.renderPixels([job(before.handle), job(before.handle, 9)]);

  assert.deepEqual(trapped, [
    { status: STATUS.INTERNAL, pixels: null },
    { status: STATUS.INTERNAL, pixels: null },
  ]);
  assert.equal(core.restarts, 1);
  assert.notEqual(core.exports.memory, memoryBefore, 'a fresh instance, not the dead one');

  // Everything loaded before the trap is gone: the old id fails softly...
  const stale = core.renderPixels([job(before.handle)])[0];
  assert.deepEqual(stale, { status: STATUS.INVALID_ARGUMENT, pixels: null });
  // ...and the caller can load again and draw on the fresh instance.
  const again = loaded(core);
  assert.ok(again.handle > before.handle, 'ids keep counting: an old id never names a new animation');
  const [fresh] = core.renderPixels([job(again.handle)]);
  assert.equal(fresh.status, 0);
  assert.ok(fresh.pixels.some((byte) => byte !== 0));
  core.close();
});

test('a trap in load fails that load with INTERNAL and recovers', { skip }, async () => {
  const { core, arm } = await coreThatCanTrap('chat_lottie_load');
  arm();

  assert.deepEqual(core.load(fixtureGzip), { status: STATUS.INTERNAL });
  assert.equal(core.restarts, 1);

  const info = loaded(core);
  assert.equal(core.renderPixels([job(info.handle)])[0].status, 0);
  core.close();
});

test('a trap does not repeat: later requests do not restart again', { skip }, async () => {
  const { core, arm } = await coreThatCanTrap('chat_lottie_render_batch');
  arm();
  core.renderPixels([job(loaded(core).handle)]);
  const { handle } = loaded(core);
  for (let i = 0; i < 5; i++) assert.equal(core.renderPixels([job(handle, i)])[0].status, 0);
  assert.equal(core.restarts, 1);
  core.close();
});

test('a trap while disposing is absorbed', { skip }, async () => {
  const { core, arm } = await coreThatCanTrap('chat_lottie_free');
  const { handle } = loaded(core);
  arm();
  core.dispose(handle);
  assert.equal(core.restarts, 1);
  assert.equal(core.renderPixels([job(handle)])[0].status, STATUS.INVALID_ARGUMENT);
  core.close();
});

test('the worker answers the trapped request and serves the next one', { skip }, async () => {
  const { core, arm } = await coreThatCanTrap('chat_lottie_render_batch');
  const handle = createWorkerHandler(core);
  const { reply: first } = handle({ id: 1, type: 'load', bytes: fixtureGzip });
  arm();
  const { reply, transfer } = handle({ id: 2, type: 'render', jobs: [job(first.info.handle)] });
  assert.equal(reply.ok, true);
  assert.equal(reply.results[0].status, STATUS.INTERNAL);
  assert.deepEqual(transfer, []);
  const { reply: reloaded } = handle({ id: 3, type: 'load', bytes: fixtureGzip });
  assert.equal(reloaded.status, 0);
  const next = handle({ id: 4, type: 'render', jobs: [job(reloaded.info.handle)] });
  assert.equal(next.reply.results[0].status, 0);
  core.close();
});

test('a core that was closed stays closed, trap or not', { skip }, async () => {
  const { core } = await coreThatCanTrap('chat_lottie_render_batch');
  core.close();
  assert.throws(() => core.load(fixtureJson), /closed/);
  assert.equal(core.restarts, 0);
});
