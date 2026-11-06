import assert from 'node:assert/strict';
import test from 'node:test';

import { MAX_FILE_BYTES, MAX_JOBS } from '../chat_lottie_core.mjs';
import { createWorkerHandler, installWorker } from '../chat_lottie_worker.js';
import { coreOf, fixtureGzip, skip } from './support/wasm_fixture.mjs';

/** A core that records calls and fails on demand. */
function fakeCore() {
  const calls = [];
  return {
    calls,
    load(bytes) {
      calls.push(['load', bytes.length]);
      if (bytes.length === 13) throw new Error('boom');
      return { status: 0, info: { handle: 7, width: 1, height: 1, frameCount: 1, frameRate: 1, features: 0 } };
    },
    renderPixels(jobs) {
      calls.push(['render', jobs.length]);
      // Handle 99 is an animation the core does not know.
      return jobs.map((job) => ({
        status: job.handle === 99 ? -1 : 0,
        pixels: job.handle === 99 ? null : new Uint8Array(job.width * job.height * 4),
      }));
    },
    dispose(handle) {
      calls.push(['dispose', handle]);
    },
    close() {
      calls.push(['close']);
    },
  };
}

test('a reply carries the request id and the core result', () => {
  const handle = createWorkerHandler(fakeCore());
  const { reply, transfer } = handle({ id: 41, type: 'load', bytes: new Uint8Array(3) });
  assert.equal(reply.id, 41);
  assert.equal(reply.ok, true);
  assert.equal(reply.status, 0);
  assert.equal(reply.info.handle, 7);
  assert.deepEqual(transfer, []);
});

test('render replies list every pixel buffer as transferable, none for failures', () => {
  const handle = createWorkerHandler(fakeCore());
  const { reply, transfer } = handle({
    id: 2,
    type: 'render',
    jobs: [
      { handle: 1, frame: 0, width: 2, height: 2 },
      { handle: 99, frame: 0, width: 2, height: 2 },
      { handle: 1, frame: 1, width: 3, height: 1 },
    ],
  });
  assert.deepEqual(reply.results.map((r) => r.status), [0, -1, 0]);
  assert.equal(transfer.length, 2);
  assert.strictEqual(transfer[0], reply.results[0].pixels.buffer);
  assert.strictEqual(transfer[1], reply.results[2].pixels.buffer);
});

test('an exception fails that request only', () => {
  const core = fakeCore();
  const handle = createWorkerHandler(core);
  const failed = handle({ id: 1, type: 'load', bytes: new Uint8Array(13) });
  assert.deepEqual(failed.reply, { id: 1, ok: false, error: 'boom' });
  assert.deepEqual(failed.transfer, []);
  const next = handle({ id: 2, type: 'load', bytes: new Uint8Array(2) });
  assert.equal(next.reply.ok, true);
  assert.equal(next.reply.id, 2);
});

test('dispose and close reach the core; an unknown type is an error reply', () => {
  const core = fakeCore();
  const handle = createWorkerHandler(core);
  assert.deepEqual(handle({ id: 3, type: 'dispose', handle: 9 }).reply, { id: 3, ok: true });
  assert.deepEqual(handle({ id: 4, type: 'close' }).reply, { id: 4, ok: true });
  assert.deepEqual(core.calls, [['dispose', 9], ['close']]);
  const unknown = handle({ id: 5, type: 'frobnicate' }).reply;
  assert.equal(unknown.ok, false);
  assert.equal(unknown.id, 5);
  assert.match(unknown.error, /frobnicate/);
});

test('a non-Error throw still becomes a string error', () => {
  const core = fakeCore();
  core.close = () => {
    throw 'plain string';
  };
  const { reply } = createWorkerHandler(core)({ id: 6, type: 'close' });
  assert.deepEqual(reply, { id: 6, ok: false, error: 'plain string' });
});

// --- The messaging layer over a fake worker scope --------------------------

function fakeScope() {
  const posted = [];
  return {
    posted,
    postMessage(message, transfer = []) {
      posted.push({ message, transfer });
    },
    send(data) {
      return this.onmessage({ data });
    },
  };
}

const urls = { wasmUrl: 'a/chat_lottie.wasm', wasmNoSimdUrl: 'a/chat_lottie.nosimd.wasm' };
const settle = () => new Promise((resolve) => setTimeout(resolve, 5));

function install(scope, overrides = {}) {
  const fetched = [];
  installWorker(scope, {
    validate: () => true,
    fetchBytes: async (url) => (fetched.push(url), new Uint8Array([1])),
    createCore: async () => fakeCore(),
    ...overrides,
  });
  return fetched;
}

test('init fetches the SIMD build when the probe validates and reports ready', async () => {
  const scope = fakeScope();
  const fetched = install(scope);
  await scope.send({ type: 'init', ...urls });
  await settle();
  assert.deepEqual(fetched, ['a/chat_lottie.wasm']);
  assert.deepEqual(scope.posted.map((p) => p.message), [{ type: 'ready', simd: true }]);
});

test('init fetches the plain build when the probe fails', async () => {
  const scope = fakeScope();
  const fetched = install(scope, { validate: () => false });
  await scope.send({ type: 'init', ...urls });
  await settle();
  assert.deepEqual(fetched, ['a/chat_lottie.nosimd.wasm']);
  assert.deepEqual(scope.posted[0].message, { type: 'ready', simd: false });
});

test('a SIMD build that will not instantiate falls back to the plain one', async () => {
  const scope = fakeScope();
  let attempts = 0;
  const fetched = install(scope, {
    createCore: async () => {
      if (++attempts === 1) throw new Error('CompileError');
      return fakeCore();
    },
  });
  await scope.send({ type: 'init', ...urls });
  await settle();
  assert.deepEqual(fetched, ['a/chat_lottie.wasm', 'a/chat_lottie.nosimd.wasm']);
  assert.deepEqual(scope.posted[0].message, { type: 'ready', simd: false });
});

test('a failed fetch reports unavailable with the reason', async () => {
  const scope = fakeScope();
  install(scope, {
    validate: () => false,
    fetchBytes: async () => {
      throw new Error('404 for chat_lottie.nosimd.wasm');
    },
  });
  await scope.send({ type: 'init', ...urls });
  await settle();
  assert.equal(scope.posted[0].message.type, 'unavailable');
  assert.match(scope.posted[0].message.reason, /404/);
  // Requests now fail with that reason rather than hanging.
  await scope.send({ id: 1, type: 'load', bytes: new Uint8Array(1) });
  await settle();
  assert.equal(scope.posted[1].message.ok, false);
  assert.match(scope.posted[1].message.error, /404/);
});

test('a request before init is an error reply, not a crash', async () => {
  const scope = fakeScope();
  install(scope);
  await scope.send({ id: 9, type: 'load', bytes: new Uint8Array(1) });
  await settle();
  assert.equal(scope.posted[0].message.id, 9);
  assert.equal(scope.posted[0].message.ok, false);
});

test('requests are served in arrival order, one at a time', async () => {
  const scope = fakeScope();
  install(scope, {
    // A slow init: the requests behind it must still come out in order.
    fetchBytes: async () => {
      await new Promise((resolve) => setTimeout(resolve, 20));
      return new Uint8Array([1]);
    },
  });
  scope.send({ type: 'init', ...urls });
  scope.send({ id: 1, type: 'load', bytes: new Uint8Array(1) });
  scope.send({ id: 2, type: 'render', jobs: [{ handle: 7, frame: 0, width: 1, height: 1 }] });
  scope.send({ id: 3, type: 'dispose', handle: 7 });
  await new Promise((resolve) => setTimeout(resolve, 80));
  assert.deepEqual(
    scope.posted.map((p) => p.message.id ?? p.message.type),
    ['ready', 1, 2, 3],
  );
  assert.equal(scope.posted[2].transfer.length, 1);
});

test('over the real wasm: load, render, transfer, dispose', { skip }, async () => {
  const core = await coreOf();
  const handle = createWorkerHandler(core);
  const loaded = handle({ id: 1, type: 'load', bytes: fixtureGzip }).reply;
  assert.equal(loaded.ok, true);
  assert.equal(loaded.info.width, 100);
  const { reply, transfer } = handle({
    id: 2,
    type: 'render',
    jobs: [{ handle: loaded.info.handle, frame: 3, width: 20, height: 10 }],
  });
  assert.equal(reply.results[0].pixels.length, 20 * 10 * 4);
  assert.deepEqual(transfer, [reply.results[0].pixels.buffer]);
  assert.equal(reply.results[0].pixels.buffer.byteLength, 20 * 10 * 4);
  assert.equal(handle({ id: 3, type: 'dispose', handle: loaded.info.handle }).reply.ok, true);
  handle({ id: 4, type: 'close' });
});

test('a reply that cannot be posted becomes an error reply and the queue lives on', async () => {
  const scope = fakeScope();
  let first = true;
  const post = scope.postMessage.bind(scope);
  scope.postMessage = (message, transfer) => {
    if (first && message.ok === true) {
      first = false;
      throw new Error('DataCloneError');
    }
    post(message, transfer);
  };
  install(scope);
  await scope.send({ type: 'init', ...urls });
  await scope.send({ id: 1, type: 'load', bytes: new Uint8Array(1) });
  await scope.send({ id: 2, type: 'load', bytes: new Uint8Array(1) });
  await settle();
  const replies = scope.posted.map((p) => p.message).filter((m) => m.id !== undefined);
  assert.deepEqual(replies.map((m) => [m.id, m.ok]), [[1, false], [2, true]]);
  assert.match(replies[0].error, /DataCloneError/);
});

// --- Message validation ----------------------------------------------------

test('a message that is not a request is dropped with one error reply', async () => {
  const scope = fakeScope();
  install(scope);
  await scope.send({ type: 'init', ...urls });
  const bad = [
    null,
    undefined,
    42,
    'load',
    [],
    {},
    { id: 1 },
    { type: 7, id: 1 },
    { type: 'load' },
    { type: 'load', id: 1.5 },
    { type: 'load', id: '1' },
    { type: 'load', id: NaN },
  ];
  for (const message of bad) await scope.send(message);
  await settle();
  const replies = scope.posted.map((p) => p.message).slice(1);
  assert.equal(replies.length, bad.length, 'exactly one reply per bad message');
  for (const reply of replies) {
    assert.equal(reply.type, 'error');
    assert.equal(typeof reply.error, 'string');
    assert.equal('id' in reply, false);
  }
  // The queue is not poisoned: the next valid request is answered.
  await scope.send({ id: 5, type: 'load', bytes: new Uint8Array(2) });
  await settle();
  assert.deepEqual(scope.posted.at(-1).message.id, 5);
  assert.equal(scope.posted.at(-1).message.ok, true);
});

test('an init without its urls is an error reply, not a half-started worker', async () => {
  const scope = fakeScope();
  install(scope);
  await scope.send({ type: 'init', wasmUrl: 'a.wasm' });
  await scope.send({ type: 'init', wasmUrl: 1, wasmNoSimdUrl: 2 });
  await settle();
  assert.deepEqual(scope.posted.map((p) => p.message.type), ['error', 'error']);
});

test('the queue survives a reply that cannot even be reported', async () => {
  const scope = fakeScope();
  const post = scope.postMessage.bind(scope);
  let failures = 2;
  scope.postMessage = (message, transfer) => {
    if (failures-- > 0) throw new Error('port closed');
    post(message, transfer);
  };
  install(scope);
  await scope.send({ type: 'init', ...urls });
  await scope.send({ id: 1, type: 'load', bytes: new Uint8Array(1) });
  await scope.send({ id: 2, type: 'load', bytes: new Uint8Array(1) });
  await settle();
  assert.equal(scope.posted.at(-1).message.id, 2);
});

test('a second init closes the core of the first', async () => {
  const scope = fakeScope();
  const cores = [];
  install(scope, {
    createCore: async () => {
      const core = fakeCore();
      cores.push(core);
      return core;
    },
  });
  await scope.send({ type: 'init', ...urls });
  await scope.send({ type: 'init', ...urls });
  await settle();
  assert.equal(cores.length, 2);
  assert.deepEqual(cores[0].calls, [['close']]);
  assert.deepEqual(cores[1].calls, []);
});

test('a second init that fails leaves no core behind to serve requests', async () => {
  const scope = fakeScope();
  let attempts = 0;
  install(scope, {
    createCore: async () => {
      if (++attempts > 1) throw new Error('no wasm today');
      return fakeCore();
    },
    validate: () => false,
  });
  await scope.send({ type: 'init', ...urls });
  await scope.send({ type: 'init', ...urls });
  await scope.send({ id: 1, type: 'load', bytes: new Uint8Array(1) });
  await settle();
  const last = scope.posted.at(-1).message;
  assert.equal(last.ok, false);
  assert.match(last.error, /no wasm today/);
});

// --- Request size caps -----------------------------------------------------

const job = { handle: 1, frame: 0, width: 4, height: 4 };

test('the caps are the documented ones', () => {
  assert.equal(MAX_JOBS, 256);
  assert.equal(MAX_FILE_BYTES, 4 * 1024 * 1024);
});

test('a render of MAX_JOBS jobs runs and one more is refused whole', () => {
  const core = fakeCore();
  const handle = createWorkerHandler(core);
  const ok = handle({ id: 1, type: 'render', jobs: Array(MAX_JOBS).fill(job) }).reply;
  assert.equal(ok.ok, true);
  const refused = handle({ id: 2, type: 'render', jobs: Array(MAX_JOBS + 1).fill(job) }).reply;
  assert.equal(refused.ok, false);
  assert.match(refused.error, /jobs/);
  assert.deepEqual(core.calls, [['render', MAX_JOBS]], 'the core never saw the big batch');
});

test('a job edge outside 1..512 or not an integer refuses the request', () => {
  const handle = createWorkerHandler(fakeCore());
  for (const edge of [0, -1, 513, 1.5, NaN, '8', 2 ** 31]) {
    for (const key of ['width', 'height']) {
      const reply = handle({ id: 1, type: 'render', jobs: [{ ...job, [key]: edge }] }).reply;
      assert.equal(reply.ok, false, `${key} ${String(edge)}`);
      assert.match(reply.error, new RegExp(key));
    }
  }
  for (const edge of [1, 512]) {
    assert.equal(handle({ id: 1, type: 'render', jobs: [{ ...job, width: edge }] }).reply.ok, true);
  }
});

test('a job without an integer handle or a finite frame refuses the request', () => {
  const handle = createWorkerHandler(fakeCore());
  for (const bad of [{ handle: 1.5 }, { handle: '1' }, { frame: NaN }, { frame: Infinity }]) {
    assert.equal(handle({ id: 1, type: 'render', jobs: [{ ...job, ...bad }] }).reply.ok, false);
  }
  assert.equal(handle({ id: 1, type: 'render', jobs: 'nope' }).reply.ok, false);
  assert.equal(handle({ id: 1, type: 'render', jobs: [null] }).reply.ok, false);
});

test('a file of MAX_FILE_BYTES loads and one byte more is refused', () => {
  const core = fakeCore();
  const handle = createWorkerHandler(core);
  assert.equal(handle({ id: 1, type: 'load', bytes: new Uint8Array(MAX_FILE_BYTES) }).reply.ok, true);
  const refused = handle({ id: 2, type: 'load', bytes: new Uint8Array(MAX_FILE_BYTES + 1) }).reply;
  assert.equal(refused.ok, false);
  assert.match(refused.error, /bytes/);
  assert.deepEqual(core.calls, [['load', MAX_FILE_BYTES]]);
});

test('bytes that are not a Uint8Array refuse the load', () => {
  const handle = createWorkerHandler(fakeCore());
  for (const bytes of [undefined, null, 'text', [1, 2], new ArrayBuffer(4), { length: 3 }]) {
    assert.equal(handle({ id: 1, type: 'load', bytes }).reply.ok, false);
  }
});

test('a dispose needs an integer handle', () => {
  const handle = createWorkerHandler(fakeCore());
  assert.equal(handle({ id: 1, type: 'dispose', handle: 'x' }).reply.ok, false);
  assert.equal(handle({ id: 1, type: 'dispose' }).reply.ok, false);
});
