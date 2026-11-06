// Module worker around chat_lottie_core.mjs. Start it with
// `new Worker(url, {type: 'module'})`; the core file must sit beside it.
//
// Protocol (structured-clone messages)
//
//   host -> worker   {type: 'init', wasmUrl, wasmNoSimdUrl}
//   worker -> host   {type: 'ready', simd}  |  {type: 'unavailable', reason}
//                    A second `init` closes the previous core first.
//
//   host -> worker   {id, type: 'load', bytes: Uint8Array}
//                    {id, type: 'render', jobs: [{handle, frame, width, height}]}
//                    {id, type: 'dispose', handle}
//                    {id, type: 'close'}
//   worker -> host   {id, ok: true, ...result}  |  {id, ok: false, error}
//
// A message that is not an object with a string `type` (and, but for `init`,
// an integer `id`) is dropped with one `{type: 'error', error}` reply, which
// carries no `id`. A request over the caps below fails as a request
// (`ok: false`); the core itself would still answer `-7` for a bad job.
//
//   load    `bytes` is a Uint8Array of at most MAX_FILE_BYTES (4 MiB)
//   render  at most MAX_JOBS (256) jobs, each `{handle, frame, width, height}`
//           with integer `handle`, finite `frame` and integer edges 1..512
//   dispose an integer `handle`
//
// `load` answers `status` and, on success, `info`; `render` answers `results`,
// one `{status, pixels}` per job. Every `pixels` buffer is transferred, so the
// worker keeps no copy. Requests are served one at a time in arrival order
// (including those that arrive while `init` is still fetching); an exception
// in one request fails that request only. Before `ready`, and after
// `unavailable`, requests answer `ok: false`.

import {
  MAX_EDGE,
  MAX_FILE_BYTES,
  MAX_JOBS,
  createChatLottie,
  selectWasm,
} from './chat_lottie_core.mjs';

/** The message of a thrown value, whatever was thrown. */
function describe(error) {
  return error instanceof Error ? error.message : String(error);
}

const isEdge = (value) => Number.isInteger(value) && value >= 1 && value <= MAX_EDGE;

/** Why [job] cannot be run, or null. */
function problemWithJob(job, index) {
  if (typeof job !== 'object' || job === null) return `jobs[${index}] must be an object`;
  if (!Number.isInteger(job.handle)) return `jobs[${index}].handle must be an integer`;
  if (!Number.isFinite(job.frame)) return `jobs[${index}].frame must be a finite number`;
  if (!isEdge(job.width)) return `jobs[${index}].width must be an integer from 1 to ${MAX_EDGE}`;
  if (!isEdge(job.height)) return `jobs[${index}].height must be an integer from 1 to ${MAX_EDGE}`;
  return null;
}

/**
 * The requests the worker serves, as data: what each one must look like
 * (`check` returns the problem or null) and what it does to the core.
 */
const REQUESTS = {
  load: {
    check: (request) => {
      if (!(request.bytes instanceof Uint8Array)) return 'bytes must be a Uint8Array';
      if (request.bytes.length > MAX_FILE_BYTES) {
        return `bytes is ${request.bytes.length} long, over the ${MAX_FILE_BYTES} byte cap`;
      }
      return null;
    },
    run: (core, request) => ({ ...core.load(request.bytes) }),
  },
  render: {
    check: (request) => {
      if (!Array.isArray(request.jobs)) return 'jobs must be an array';
      if (request.jobs.length > MAX_JOBS) {
        return `${request.jobs.length} jobs is over the cap of ${MAX_JOBS}`;
      }
      for (let i = 0; i < request.jobs.length; i++) {
        const problem = problemWithJob(request.jobs[i], i);
        if (problem !== null) return problem;
      }
      return null;
    },
    run: (core, request) => ({ results: core.renderPixels(request.jobs) }),
  },
  dispose: {
    check: (request) => (Number.isInteger(request.handle) ? null : 'handle must be an integer'),
    run: (core, request) => (core.dispose(request.handle), {}),
  },
  close: {
    check: () => null,
    run: (core) => (core.close(), {}),
  },
};

/**
 * Turns the worker protocol into calls on [core]: returns `handle(request)`,
 * which answers `{reply, transfer}` for the caller to post. It touches no
 * worker API, so tests drive it directly.
 */
export function createWorkerHandler(core) {
  return function handle(request) {
    try {
      const entry = Object.hasOwn(REQUESTS, request.type) ? REQUESTS[request.type] : null;
      if (entry === null) throw new Error(`unknown request type "${request.type}"`);
      const problem = entry.check(request);
      if (problem !== null) throw new Error(problem);
      const result = entry.run(core, request);
      const transfer = (result.results ?? [])
        .filter((entry) => entry.pixels !== null)
        .map((entry) => entry.pixels.buffer);
      return { reply: { id: request.id, ok: true, ...result }, transfer };
    } catch (error) {
      return { reply: { id: request.id, ok: false, error: describe(error) }, transfer: [] };
    }
  };
}

/**
 * Why [message] is not a message of the protocol, or null: an object with a
 * string `type` and, but for `init` (which has no request to answer), an
 * integer `id`.
 */
function problemWithMessage(message) {
  if (typeof message !== 'object' || message === null || Array.isArray(message)) {
    return 'a message must be an object';
  }
  if (typeof message.type !== 'string') return 'message.type must be a string';
  if (message.type === 'init') {
    return typeof message.wasmUrl === 'string' && typeof message.wasmNoSimdUrl === 'string'
      ? null
      : 'init needs the strings wasmUrl and wasmNoSimdUrl';
  }
  return Number.isInteger(message.id) ? null : 'message.id must be an integer';
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
  // The core in use and the handler over it; both null before `init`, after a
  // failed `init`, and while a new one is being fetched.
  let current = null;
  let unavailable = 'chat_lottie is not ready: no init message yet';
  let queue = Promise.resolve();

  /**
   * Posts [message], never throwing: a closed port must not stop the queue.
   * Returns why it failed, or null.
   */
  function post(message, transfer = []) {
    try {
      scope.postMessage(message, transfer);
      return null;
    } catch (error) {
      return error;
    }
  }

  function closeCurrent() {
    const previous = current;
    current = null;
    try {
      previous?.core.close();
    } catch {
      // A core that cannot close is dropped all the same.
    }
  }

  async function init({ wasmUrl, wasmNoSimdUrl }) {
    // A second init replaces the core: the old one's animations and memory
    // are released first, and a failure below must not leave it serving.
    closeCurrent();
    const choice = selectWasm(validate, { simd: wasmUrl, noSimd: wasmNoSimdUrl });
    const attempts = choice.simd
      ? [choice, { url: wasmNoSimdUrl, simd: false }]
      : [choice];
    let lastError;
    for (const attempt of attempts) {
      try {
        const core = await createCore(await fetchBytes(attempt.url));
        current = { core, handle: createWorkerHandler(core) };
        post({ type: 'ready', simd: attempt.simd });
        return;
      } catch (error) {
        // A runtime can validate the probe and still refuse the whole SIMD
        // module: the plain build is then the answer, not a dead worker.
        lastError = error;
      }
    }
    unavailable = describe(lastError);
    post({ type: 'unavailable', reason: unavailable });
  }

  async function serve(message) {
    if (message.type === 'init') return init(message);
    if (current === null) {
      post({ id: message.id, ok: false, error: unavailable });
      return undefined;
    }
    const { reply, transfer } = current.handle(message);
    // Posting itself can fail (a reply that cannot be cloned): answer with the
    // reason so the host's request settles.
    const failure = post(reply, transfer);
    if (failure !== null) post({ id: message.id, ok: false, error: describe(failure) });
    return undefined;
  }

  scope.onmessage = (event) => {
    const message = event.data;
    const problem = problemWithMessage(message);
    if (problem !== null) {
      // Dropped: it names no request, so the reply carries no id.
      post({ type: 'error', error: problem });
      return queue;
    }
    // Chained so a request that arrives during `init` waits for it, and never
    // rejecting: whatever `serve` throws is the end of that request only.
    queue = queue.then(() => serve(message)).catch((error) => {
      post({ id: message.id, ok: false, error: describe(error) });
    });
    return queue;
  };
}

if (typeof WorkerGlobalScope !== 'undefined' && globalThis instanceof WorkerGlobalScope) {
  installWorker(globalThis);
}
