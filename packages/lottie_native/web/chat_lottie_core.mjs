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
const INVALID_ARGUMENT = -1;

/** The ABI version this file was written against (`chat_lottie_abi_version`). */
const ABI_VERSION = 1;

/**
 * Instantiates the module from [wasmBytes] and returns the handle over it:
 * `load`, `renderPixels`, `dispose` and `close`. One core serves one caller at
 * a time (a worker handles requests in order).
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
  const live = new Set();

  // Out-parameters of `load`: allocated once, reused by every call.
  const infoPtr = allocate(LAYOUT.info.size);
  const handlePtr = allocate(4);

  function allocate(length) {
    const pointer = wasm.chat_lottie_alloc(length);
    if (pointer === 0) throw new Error(`chat_lottie_alloc(${length}) failed`);
    return pointer;
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
      const handle = view.getUint32(handlePtr, true);
      live.add(handle);
      return {
        status,
        info: {
          handle,
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

  function dispose(handle) {
    if (!live.delete(handle)) return;
    wasm.chat_lottie_free(handle);
  }

  function close() {
    if (closed) return;
    for (const handle of live) wasm.chat_lottie_free(handle);
    live.clear();
    wasm.chat_lottie_dealloc(infoPtr, LAYOUT.info.size);
    wasm.chat_lottie_dealloc(handlePtr, 4);
    closed = true;
  }

  return {
    abiVersion: version,
    exports: wasm,
    load,
    dispose,
    close,
  };
}
