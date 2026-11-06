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

/** Statuses the core itself reports; the rest come from the module. */
const TOO_LARGE = -2;

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

/** Written to a status slot before the call, so an unwritten slot is visible. */
const INTERNAL_UNSET = -6;

/** The ABI version this file was written against (`chat_lottie_abi_version`). */
const ABI_VERSION = 1;

/**
 * Instantiates the module from [wasmBytes] and returns the handle over it:
 * `load`, `renderPixels`, `dispose` and `close`. One core serves one caller at
 * a time (a worker handles requests in order). The `handle` of a loaded
 * animation is an opaque id (1, 2, 3, ...), not an address in the module.
 *
 * Every call into the module can grow its memory, which detaches the old
 * `ArrayBuffer`; views are therefore made right before each use and never kept.
 */
export async function createChatLottie(wasmBytes) {
  const { instance } = await WebAssembly.instantiate(wasmBytes, {});
  const wasm = instance.exports;
  const version = wasm.chat_lottie_abi_version();
  if (version !== ABI_VERSION) {
    throw new Error(`chat_lottie wasm has ABI version ${version}, expected ${ABI_VERSION}`);
  }

  const bytes = () => new Uint8Array(wasm.memory.buffer);
  const words = () => new DataView(wasm.memory.buffer);
  let closed = false;
  // Handles given to callers are ids, never module pointers. A freed pointer
  // is handed out again by the allocator, so a caller holding a stale pointer
  // would have drawn (or freed) whatever animation was loaded next; an id is
  // never reissued, so a stale one just misses in this map. The ids are
  // module-independent too, which is what lets a rebuilt module fail every
  // older one (see `recover`).
  let nextId = 1;
  /** id -> pointer of the live animations. */
  const live = new Map();

  // Out-parameters of `load`: allocated once, reused by every call.
  const infoPtr = allocate(LAYOUT.info.size);
  const handlePtr = allocate(4);

  function allocate(length) {
    const pointer = wasm.chat_lottie_alloc(length);
    if (pointer === 0) throw new Error(`chat_lottie_alloc(${length}) failed`);
    return pointer;
  }

  // Scratch regions by size, handed out and taken back around each batch.
  const pool = new Map();
  let pooledBytes = 0;

  function borrow(size) {
    const idle = pool.get(size);
    if (idle?.length) {
      pooledBytes -= size;
      return idle.pop();
    }
    return allocate(size);
  }

  function giveBack(pointer, size) {
    if (pooledBytes + size > POOL_LIMIT_BYTES) {
      wasm.chat_lottie_dealloc(pointer, size);
      return;
    }
    pooledBytes += size;
    const idle = pool.get(size);
    if (idle) idle.push(pointer);
    else pool.set(size, [pointer]);
  }

  function ensureOpen() {
    if (closed) throw new Error('the chat_lottie core is closed');
  }

  function load(input) {
    ensureOpen();
    // The module refuses an empty region, and an empty file is a malformed
    // one: give it one byte and the true length 0.
    const pointer = wasm.chat_lottie_alloc(Math.max(input.length, 1));
    if (pointer === 0) return { status: TOO_LARGE };
    try {
      bytes().set(input, pointer);
      const status = wasm.chat_lottie_load(pointer, input.length, infoPtr, handlePtr);
      if (status !== 0) return { status };
      const view = words();
      const id = nextId++;
      live.set(id, view.getUint32(handlePtr, true));
      return {
        status,
        info: {
          handle: id,
          width: view.getUint32(infoPtr + LAYOUT.info.width, true),
          height: view.getUint32(infoPtr + LAYOUT.info.height, true),
          frameCount: view.getUint32(infoPtr + LAYOUT.info.frameCount, true),
          frameRate: view.getFloat32(infoPtr + LAYOUT.info.frameRate, true),
          features: view.getUint32(infoPtr + LAYOUT.info.features, true),
        },
      };
    } finally {
      wasm.chat_lottie_dealloc(pointer, Math.max(input.length, 1));
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
    const regions = jobs.map((job) => {
      const fits = fitsFrame(job.width) && fitsFrame(job.height);
      const size = fits ? job.width * job.height * 4 : PLACEHOLDER_BYTES;
      return { size, stride: fits ? job.width * 4 : PLACEHOLDER_BYTES };
    });
    const tableBytes = jobs.length * (LAYOUT.job.size + 4);
    const table = borrow(tableBytes);
    const borrowed = [];
    try {
      for (const region of regions) {
        region.pointer = borrow(region.size);
        borrowed.push(region);
      }
      // Every allocation above may have grown memory: take the view now.
      const view = words();
      const statusesAt = table + jobs.length * LAYOUT.job.size;
      jobs.forEach((job, i) => {
        const at = table + i * LAYOUT.job.size;
        // An id that was disposed or never issued is passed as null, which
        // the module answers with -1; a freed animation must never reach it.
        view.setUint32(at + LAYOUT.job.handle, live.get(job.handle) ?? 0, true);
        view.setFloat32(at + LAYOUT.job.frame, job.frame, true);
        view.setUint32(at + LAYOUT.job.width, job.width, true);
        view.setUint32(at + LAYOUT.job.height, job.height, true);
        view.setUint32(at + LAYOUT.job.target, regions[i].pointer, true);
        view.setUint32(at + LAYOUT.job.strideBytes, regions[i].stride, true);
        view.setInt32(statusesAt + i * 4, INTERNAL_UNSET, true);
      });
      const code = wasm.chat_lottie_render_batch(table, jobs.length, statusesAt);
      if (code !== 0) throw new Error(`chat_lottie_render_batch failed with ${code}`);
      // The call may have grown memory too: fresh views.
      const after = words();
      const memory = bytes();
      return regions.map((region, i) => {
        const status = after.getInt32(statusesAt + i * 4, true);
        if (status !== 0) return { status, pixels: null };
        return { status, pixels: memory.slice(region.pointer, region.pointer + region.size) };
      });
    } finally {
      for (const region of borrowed) giveBack(region.pointer, region.size);
      giveBack(table, tableBytes);
    }
  }

  function dispose(handle) {
    const pointer = live.get(handle);
    if (pointer === undefined) return;
    live.delete(handle);
    wasm.chat_lottie_free(pointer);
  }

  function close() {
    if (closed) return;
    for (const pointer of live.values()) wasm.chat_lottie_free(pointer);
    live.clear();
    for (const [size, idle] of pool) {
      for (const pointer of idle) wasm.chat_lottie_dealloc(pointer, size);
    }
    pool.clear();
    pooledBytes = 0;
    wasm.chat_lottie_dealloc(infoPtr, LAYOUT.info.size);
    wasm.chat_lottie_dealloc(handlePtr, 4);
    closed = true;
  }

  return {
    abiVersion: version,
    /** Bytes of idle scratch kept for reuse (observable so reuse is testable). */
    get pooledBytes() {
      return pooledBytes;
    },
    exports: wasm,
    load,
    renderPixels,
    dispose,
    close,
  };
}
