//! C ABI over tlottie. The contract is `include/chat_lottie.h`.

/// Version of the C ABI; the host checks it right after loading the library.
pub const ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn chat_lottie_abi_version() -> u32 {
    ABI_VERSION
}
