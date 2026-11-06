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
