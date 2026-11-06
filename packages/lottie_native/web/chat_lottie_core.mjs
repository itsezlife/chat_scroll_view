// The JavaScript side of the chat_lottie wasm module: no DOM, so it runs in a
// worker, in Node and in a window. Contract: native/include/chat_lottie.h.

// --- Choosing the build ---------------------------------------------------

/**
 * A module with one function that executes `i8x16.splat`. A runtime that
 * validates it can run the build compiled with `+simd128`; one that does not
 * would fail to compile that build at all, so the probe is the only safe
 * test (there is no feature flag to read).
 */
export const SIMD_PROBE_BYTES = new Uint8Array([
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, // magic, version
  0x01, 0x04, 0x01, 0x60, 0x00, 0x00, // type section: () -> ()
  0x03, 0x02, 0x01, 0x00, // function section: one function of type 0
  0x0a, 0x09, 0x01, 0x07, 0x00, // code section: one body of 7 bytes, no locals
  0x41, 0x00, // i32.const 0
  0xfd, 0x0f, // i8x16.splat
  0x1a, // drop
  0x0b, // end
]);

/**
 * Picks the wasm build for this runtime. [validate] is `WebAssembly.validate`
 * (a parameter so the choice is tested without a runtime); [urls] names both
 * builds as `{simd, noSimd}`.
 */
export function selectWasm(validate, urls) {
  let simd = false;
  try {
    simd = validate(SIMD_PROBE_BYTES) === true;
  } catch {
    // No WebAssembly at all, or a validator that cannot take the probe: the
    // plain build is the one that can still work.
  }
  return simd ? { url: urls.simd, simd } : { url: urls.noSimd, simd };
}

// --- Memory layout of the header's structs on wasm32 ----------------------

/** Largest frame edge the module draws (`MAX_FRAME_EDGE` in the crate). */
export const MAX_EDGE = 512;

/**
 * Most jobs one `render` request may carry. A page of stickers is a few dozen
 * frames; the cap bounds the job table and the scratch a request can make the
 * module reserve (the worst case, 256 frames of 512 x 512, is 256 MiB of
 * module memory, which a real page stays far below and memory never shrinks).
 */
export const MAX_JOBS = 256;

/** Largest encoded file one `load` request may carry: the crate's own cap. */
export const MAX_FILE_BYTES = 4 * 1024 * 1024;

/**
 * The statuses of `native/include/chat_lottie.h`, by the names the header
 * gives them without the `CHAT_LOTTIE_` prefix. `status.test.mjs` parses the
 * header and fails if a number or a name drifts.
 */
export const STATUS = Object.freeze({
  OK: 0,
  INVALID_ARGUMENT: -1,
  TOO_LARGE: -2,
  MALFORMED: -3,
  LIMIT_EXCEEDED: -4,
  UNSUPPORTED: -5,
  INTERNAL: -6,
  BAD_SIZE: -7,
  RENDER_FAILED: -8,
});

/**
 * Byte offsets of the fields of `ChatLottieInfo` and `ChatLottieJob` in module
 * memory. On wasm32 every field is 4 bytes wide, pointers and `size_t`
 * included. `layout.test.mjs` derives the same numbers from the header, so a
 * drift in either fails a test instead of corrupting memory.
 */
export const LAYOUT = Object.freeze({
  info: Object.freeze({
    width: 0,
    height: 4,
    frameCount: 8,
    frameRate: 12,
    features: 16,
    size: 20,
  }),
  job: Object.freeze({
    handle: 0,
    frame: 4,
    width: 8,
    height: 12,
    target: 16,
    strideBytes: 20,
    size: 24,
  }),
});

// --- The module in use ----------------------------------------------------

/**
 * Most bytes of idle scratch regions a core keeps for reuse. A batch of
 * sticker-sized frames fits many times over; a burst of large ones is freed
 * on return instead of pinning module memory (which never shrinks) for good.
 */
const POOL_LIMIT_BYTES = 16 * 1024 * 1024;

/**
 * A job whose size the module will refuse still needs a non-null target: the
 * module checks the pointer before the size, and the size check is the answer
 * the caller should get (-7). Four bytes is never written.
 */
const PLACEHOLDER_BYTES = 4;

/**
 * Written to a status slot before the call, so a slot the module never wrote
 * reads as the bug it is (`INTERNAL`) and not as success.
 */
const UNSET_SLOT = STATUS.INTERNAL;

/** The ABI version this file was written against (`chat_lottie_abi_version`). */
const ABI_VERSION = 1;

/**
 * What a call into the module throws when the Rust side panicked or touched
 * memory it must not. wasm32 has no unwinding, so `catch_unwind` in the crate
 * cannot turn a panic into `INTERNAL`: it is a trap, and the instance is in an
 * unknown state afterwards.
 */
const isTrap = (error) => error instanceof WebAssembly.RuntimeError;

/**
 * Instantiates the module from [wasmBytes] and returns the handle over it:
 * `load`, `renderPixels`, `dispose` and `close`. One core serves one caller at
 * a time (a worker handles requests in order). The `handle` of a loaded
 * animation is an opaque id (1, 2, 3, ...), not an address in the module.
 *
 * Every call into the module can grow its memory, which detaches the old
 * `ArrayBuffer`; views are therefore made right before each use and never kept.
 *
 * **A trap is recovered, not propagated.** When a call traps
 * (`WebAssembly.RuntimeError`) the core drops that instance, builds a fresh one
 * from the module it already compiled and answers the request that hit the trap
 * with `STATUS.INTERNAL` (for every job of a batch). Everything the old
 * instance held is gone: every id handed out before is unknown to the new one
 * and fails with `INVALID_ARGUMENT`, so the caller reloads what it still needs.
 * Ids keep counting up across the restart, which is what keeps an old id from
 * ever naming a new animation. `restarts` counts them.
 *
 * [options.wrapExports] receives each instance's exports and returns what the
 * core calls instead; it exists for tests, to put a fault on the call path.
 */
export async function createChatLottie(wasmBytes, { wrapExports = (exports) => exports } = {}) {
  const { module, instance } = await WebAssembly.instantiate(wasmBytes, {});

  /** Everything that belongs to one instance, so a restart replaces it whole. */
  function boot(fresh) {
    const wasm = wrapExports(fresh.exports);
    const version = wasm.chat_lottie_abi_version();
    if (version !== ABI_VERSION) {
      throw new Error(`chat_lottie wasm has ABI version ${version}, expected ${ABI_VERSION}`);
    }
    const state = {
      wasm,
      version,
      /** id -> pointer of the animations loaded into this instance. */
      live: new Map(),
      /** Scratch regions by size, handed out and taken back around each batch. */
      pool: new Map(),
      pooledBytes: 0,
      infoPtr: 0,
      handlePtr: 0,
    };
    // Out-parameters of `load`: allocated once, reused by every call.
    state.infoPtr = allocate(state, LAYOUT.info.size);
    state.handlePtr = allocate(state, 4);
    return state;
  }

  const bytes = (state) => new Uint8Array(state.wasm.memory.buffer);
  const words = (state) => new DataView(state.wasm.memory.buffer);

  function allocate(state, length) {
    const pointer = state.wasm.chat_lottie_alloc(length);
    if (pointer === 0) throw new Error(`chat_lottie_alloc(${length}) failed`);
    return pointer;
  }

  function borrow(state, size) {
    const idle = state.pool.get(size);
    if (idle?.length) {
      state.pooledBytes -= size;
      return idle.pop();
    }
    return allocate(state, size);
  }

  function giveBack(state, pointer, size) {
    if (state.pooledBytes + size > POOL_LIMIT_BYTES) {
      state.wasm.chat_lottie_dealloc(pointer, size);
      return;
    }
    state.pooledBytes += size;
    const idle = state.pool.get(size);
    if (idle) idle.push(pointer);
    else state.pool.set(size, [pointer]);
  }

  let state = boot(instance);
  let closed = false;
  /** Why the core cannot serve any more, when a restart itself failed. */
  let brokenBy = null;
  let restarts = 0;
  // Ids given to callers are never module pointers. A freed pointer is handed
  // out again by the allocator, so a caller holding a stale pointer would have
  // drawn (or freed) whatever animation was loaded next; an id is never
  // reissued, so a stale one just misses in `state.live`. The counter lives
  // outside the instance: a restarted module continues it.
  let nextId = 1;

  function ensureOpen() {
    if (closed) {
      throw new Error(
        brokenBy === null
          ? 'the chat_lottie core is closed'
          : `the chat_lottie core is closed: it could not restart after a trap (${brokenBy})`,
      );
    }
  }

  /** Replaces the instance [trapped] ran in with a fresh one. */
  function restart(trapped) {
    // Already replaced by an earlier trap of the same request, or closing.
    if (closed || trapped !== state) return;
    try {
      state = boot(new WebAssembly.Instance(module, {}));
      restarts++;
    } catch (error) {
      closed = true;
      brokenBy = error instanceof Error ? error.message : String(error);
    }
  }

  /**
   * Handles an error thrown while [used] was in use: a trap restarts the core
   * (and returns, for the caller to fail its request), anything else is a bug
   * of this file and is thrown on.
   */
  function recoverFrom(used, error) {
    if (!isTrap(error)) throw error;
    restart(used);
  }

  /** Runs cleanup on [used], unless a restart already discarded it. */
  function release(used, cleanup) {
    if (used !== state) return;
    try {
      cleanup();
    } catch (error) {
      recoverFrom(used, error);
    }
  }

  function load(input) {
    ensureOpen();
    const used = state;
    // The module refuses an empty region, and an empty file is a malformed
    // one: give it one byte and the true length 0.
    const length = Math.max(input.length, 1);
    let pointer = 0;
    try {
      pointer = used.wasm.chat_lottie_alloc(length);
      if (pointer === 0) return { status: STATUS.TOO_LARGE };
      bytes(used).set(input, pointer);
      const status = used.wasm.chat_lottie_load(pointer, input.length, used.infoPtr, used.handlePtr);
      if (status !== STATUS.OK) return { status };
      const view = words(used);
      const id = nextId++;
      used.live.set(id, view.getUint32(used.handlePtr, true));
      return {
        status,
        info: {
          handle: id,
          width: view.getUint32(used.infoPtr + LAYOUT.info.width, true),
          height: view.getUint32(used.infoPtr + LAYOUT.info.height, true),
          frameCount: view.getUint32(used.infoPtr + LAYOUT.info.frameCount, true),
          frameRate: view.getFloat32(used.infoPtr + LAYOUT.info.frameRate, true),
          features: view.getUint32(used.infoPtr + LAYOUT.info.features, true),
        },
      };
    } catch (error) {
      recoverFrom(used, error);
      return { status: STATUS.INTERNAL };
    } finally {
      if (pointer !== 0) release(used, () => used.wasm.chat_lottie_dealloc(pointer, length));
    }
  }

  const fitsFrame = (edge) => Number.isInteger(edge) && edge >= 1 && edge <= MAX_EDGE;

  /**
   * Draws every job in one module call. [jobs] is `[{handle, frame, width,
   * height}]`; the result has one `{status, pixels}` per job, `pixels` a
   * tightly packed premultiplied RGBA copy (null when the status is not 0).
   */
  function renderPixels(jobs) {
    ensureOpen();
    if (jobs.length === 0) return [];
    const used = state;
    const regions = jobs.map((job) => {
      const fits = fitsFrame(job.width) && fitsFrame(job.height);
      const size = fits ? job.width * job.height * 4 : PLACEHOLDER_BYTES;
      return { size, stride: fits ? job.width * 4 : PLACEHOLDER_BYTES };
    });
    const tableBytes = jobs.length * (LAYOUT.job.size + 4);
    let table = 0;
    const borrowed = [];
    try {
      table = borrow(used, tableBytes);
      for (const region of regions) {
        region.pointer = borrow(used, region.size);
        borrowed.push(region);
      }
      // Every allocation above may have grown memory: take the view now.
      const view = words(used);
      const statusesAt = table + jobs.length * LAYOUT.job.size;
      jobs.forEach((job, i) => {
        const at = table + i * LAYOUT.job.size;
        // An id that was disposed or never issued is passed as null, which
        // the module answers with -1; a freed animation must never reach it.
        view.setUint32(at + LAYOUT.job.handle, used.live.get(job.handle) ?? 0, true);
        view.setFloat32(at + LAYOUT.job.frame, job.frame, true);
        view.setUint32(at + LAYOUT.job.width, job.width, true);
        view.setUint32(at + LAYOUT.job.height, job.height, true);
        view.setUint32(at + LAYOUT.job.target, regions[i].pointer, true);
        view.setUint32(at + LAYOUT.job.strideBytes, regions[i].stride, true);
        view.setInt32(statusesAt + i * 4, UNSET_SLOT, true);
      });
      const code = used.wasm.chat_lottie_render_batch(table, jobs.length, statusesAt);
      if (code !== STATUS.OK) throw new Error(`chat_lottie_render_batch failed with ${code}`);
      // The call may have grown memory too: fresh views.
      const after = words(used);
      const memory = bytes(used);
      return regions.map((region, i) => {
        const status = after.getInt32(statusesAt + i * 4, true);
        if (status !== STATUS.OK) return { status, pixels: null };
        return { status, pixels: memory.slice(region.pointer, region.pointer + region.size) };
      });
    } catch (error) {
      recoverFrom(used, error);
      return jobs.map(() => ({ status: STATUS.INTERNAL, pixels: null }));
    } finally {
      release(used, () => {
        for (const region of borrowed) giveBack(used, region.pointer, region.size);
        if (table !== 0) giveBack(used, table, tableBytes);
      });
    }
  }

  function dispose(handle) {
    const used = state;
    const pointer = used.live.get(handle);
    if (pointer === undefined) return;
    used.live.delete(handle);
    release(used, () => used.wasm.chat_lottie_free(pointer));
  }

  function close() {
    if (closed) return;
    // Closed first: a trap while releasing must not start a new instance.
    closed = true;
    const used = state;
    try {
      for (const pointer of used.live.values()) used.wasm.chat_lottie_free(pointer);
      for (const [size, idle] of used.pool) {
        for (const pointer of idle) used.wasm.chat_lottie_dealloc(pointer, size);
      }
      used.wasm.chat_lottie_dealloc(used.infoPtr, LAYOUT.info.size);
      used.wasm.chat_lottie_dealloc(used.handlePtr, 4);
    } catch (error) {
      // The instance is being dropped; a trap while tidying it changes nothing.
      if (!isTrap(error)) throw error;
    } finally {
      used.live.clear();
      used.pool.clear();
      used.pooledBytes = 0;
    }
  }

  return {
    abiVersion: ABI_VERSION,
    /** Bytes of idle scratch kept for reuse (observable so reuse is testable). */
    get pooledBytes() {
      return state.pooledBytes;
    },
    /** How many times a trap made the core build a fresh instance. */
    get restarts() {
      return restarts;
    },
    /** The exports of the instance in use (it changes after a restart). */
    get exports() {
      return state.wasm;
    },
    load,
    renderPixels,
    dispose,
    close,
  };
}
