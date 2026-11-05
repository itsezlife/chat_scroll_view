//! C ABI over tlottie. The contract is `include/chat_lottie.h`.

mod features;
mod input;
mod status;

use std::panic::{catch_unwind, AssertUnwindSafe};
use tlottie::{CPURenderer, Composition, Error, Limits};

/// Version of the C ABI; the host checks it right after loading the library.
pub const ABI_VERSION: u32 = 1;

/// What the host learns about a loaded animation.
#[repr(C)]
#[derive(Debug, Default, Clone, Copy)]
pub struct ChatLottieInfo {
    pub width: u32,
    pub height: u32,
    pub frame_count: u32,
    pub frame_rate: f32,
    /// Bitmask of unrendered features the file uses; see `features`.
    pub features: u32,
}

/// An opaque animation handle: used by one thread at a time.
pub struct ChatLottie {
    renderer: CPURenderer,
}

/// Runs `body`; a panic becomes `fallback` so it never unwinds into C.
fn guarded<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(fallback)
}

fn status_of(error: &Error) -> i32 {
    match error {
        Error::LimitExceeded(_) => status::LIMIT_EXCEEDED,
        Error::Empty => status::UNSUPPORTED,
        _ => status::MALFORMED,
    }
}

fn load(data: &[u8]) -> Result<(ChatLottieInfo, ChatLottie), i32> {
    let json = input::lottie_json(data)?;
    let composition = Composition::parse(&json, &Limits::default()).map_err(|e| status_of(&e))?;
    let frame_count = composition.frame_count();
    let frame_rate = composition.frame_rate;
    if composition.width == 0 || composition.height == 0 || frame_count == 0 || !frame_rate.is_finite() || frame_rate <= 0.0 {
        return Err(status::UNSUPPORTED);
    }
    // The scan runs after tlottie accepted the file and can only add info.
    let features = guarded(0, || features::scan(&json));
    let info = ChatLottieInfo {
        width: composition.width,
        height: composition.height,
        frame_count,
        frame_rate,
        features,
    };
    Ok((info, ChatLottie { renderer: CPURenderer::new(composition) }))
}

#[no_mangle]
pub extern "C" fn chat_lottie_abi_version() -> u32 {
    ABI_VERSION
}

/// # Safety
/// `data..data+len` must be readable; `out_info` and `out_handle` writable.
#[no_mangle]
pub unsafe extern "C" fn chat_lottie_load(data: *const u8, len: usize, out_info: *mut ChatLottieInfo, out_handle: *mut *mut ChatLottie) -> i32 {
    guarded(status::MALFORMED, || {
        if data.is_null() || out_info.is_null() || out_handle.is_null() {
            return status::INVALID_ARGUMENT;
        }
        unsafe { *out_handle = std::ptr::null_mut() };
        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        match load(bytes) {
            Ok((info, handle)) => {
                unsafe {
                    *out_info = info;
                    *out_handle = Box::into_raw(Box::new(handle));
                }
                status::OK
            }
            Err(code) => code,
        }
    })
}

/// # Safety
/// `handle` is null or came from `chat_lottie_load` and is not freed yet.
#[no_mangle]
pub unsafe extern "C" fn chat_lottie_free(handle: *mut ChatLottie) {
    if !handle.is_null() {
        // A panicking drop must not unwind into C either.
        guarded((), || drop(unsafe { Box::from_raw(handle) }));
    }
}
