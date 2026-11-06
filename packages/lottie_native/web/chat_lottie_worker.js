// Module worker around chat_lottie_core.mjs. Start it with
// `new Worker(url, {type: 'module'})`; the core file must sit beside it.
//
// Protocol (structured-clone messages)
//
//   host -> worker   {type: 'init', wasmUrl, wasmNoSimdUrl}
//   worker -> host   {type: 'ready', simd}  |  {type: 'unavailable', reason}
//
//   host -> worker   {id, type: 'load', bytes: Uint8Array}
//                    {id, type: 'render', jobs: [{handle, frame, width, height}]}
//                    {id, type: 'dispose', handle}
//                    {id, type: 'close'}
//   worker -> host   {id, ok: true, ...result}  |  {id, ok: false, error}
//
// `load` answers `status` and, on success, `info`; `render` answers `results`,
// one `{status, pixels}` per job. Every `pixels` buffer is transferred, so the
// worker keeps no copy. Requests are served one at a time in arrival order
// (including those that arrive while `init` is still fetching); an exception
// in one request fails that request only. Before `ready`, and after
// `unavailable`, requests answer `ok: false`.

import { createChatLottie, selectWasm } from './chat_lottie_core.mjs';

/** The message of a thrown value, whatever was thrown. */
function describe(error) {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Turns the worker protocol into calls on [core]: returns `handle(request)`,
 * which answers `{reply, transfer}` for the caller to post. It touches no
 * worker API, so tests drive it directly.
 */
export function createWorkerHandler(core) {
  const requests = {
    load: (request) => ({ ...core.load(request.bytes) }),
    render: (request) => ({ results: core.renderPixels(request.jobs) }),
    dispose: (request) => (core.dispose(request.handle), {}),
    close: () => (core.close(), {}),
  };
  return function handle(request) {
    try {
      const run = Object.hasOwn(requests, request.type) ? requests[request.type] : null;
      if (run === null) throw new Error(`unknown request type "${request.type}"`);
      const result = run(request);
      const transfer = (result.results ?? [])
        .filter((entry) => entry.pixels !== null)
        .map((entry) => entry.pixels.buffer);
      return { reply: { id: request.id, ok: true, ...result }, transfer };
    } catch (error) {
      return { reply: { id: request.id, ok: false, error: describe(error) }, transfer: [] };
    }
  };
}

async function fetchWasm(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`fetching ${url} failed with HTTP ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

/**
 * Wires [scope] (a worker's global scope) to the protocol. The options exist
 * for tests: `validate` is `WebAssembly.validate`, `fetchBytes` loads a wasm
 * file, `createCore` instantiates it.
 */
export function installWorker(
  scope,
  {
    validate = (bytes) => WebAssembly.validate(bytes),
    fetchBytes = fetchWasm,
    createCore = createChatLottie,
  } = {},
) {
  let handle = null;
  let unavailable = 'chat_lottie is not ready: no init message yet';
  let queue = Promise.resolve();

  async function init({ wasmUrl, wasmNoSimdUrl }) {
    const choice = selectWasm(validate, { simd: wasmUrl, noSimd: wasmNoSimdUrl });
    const attempts = choice.simd
      ? [choice, { url: wasmNoSimdUrl, simd: false }]
      : [choice];
    let lastError;
    for (const attempt of attempts) {
      try {
        handle = createWorkerHandler(await createCore(await fetchBytes(attempt.url)));
        scope.postMessage({ type: 'ready', simd: attempt.simd });
        return;
      } catch (error) {
        // A runtime can validate the probe and still refuse the whole SIMD
        // module: the plain build is then the answer, not a dead worker.
        lastError = error;
      }
    }
    unavailable = describe(lastError);
    scope.postMessage({ type: 'unavailable', reason: unavailable });
  }

  scope.onmessage = (event) => {
    const message = event.data;
    // Chained so a request that arrives during `init` waits for it.
    queue = queue.then(async () => {
      try {
        if (message.type === 'init') return await init(message);
        if (handle === null) {
          scope.postMessage({ id: message.id, ok: false, error: unavailable });
          return undefined;
        }
        const { reply, transfer } = handle(message);
        scope.postMessage(reply, transfer);
      } catch (error) {
        // Posting itself failed (a reply that cannot be cloned): answer with
        // the reason so the host's request settles, and keep the queue alive.
        scope.postMessage({ id: message.id, ok: false, error: describe(error) });
      }
      return undefined;
    });
    return queue;
  };
}

if (typeof WorkerGlobalScope !== 'undefined' && globalThis instanceof WorkerGlobalScope) {
  installWorker(globalThis);
}
