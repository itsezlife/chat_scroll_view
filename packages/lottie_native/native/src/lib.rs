//! C ABI over tlottie. The contract is `include/chat_lottie.h`.

mod features;
mod frame_codec;
mod input;
mod status;
#[cfg(any(target_arch = "wasm32", test))]
mod wasm_alloc;

pub use frame_codec::{
    chat_lottie_compress_region, chat_lottie_decompress_region, chat_lottie_lz4_bound,
};

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
///
/// The panic payload is dropped on purpose: there is no channel to the host
/// to carry it, and panics are denied by lint, so one is a bug. The distinct
/// `status::INTERNAL` is the signal.
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
    if composition.width == 0
        || composition.height == 0
        || frame_count == 0
        || !frame_rate.is_finite()
        || frame_rate <= 0.0
    {
        return Err(status::UNSUPPORTED);
    }
    // The scan runs after tlottie accepted the file and can only add info:
    // informational, so a panic in it falls back to no features.
    let features = guarded(0, || features::scan(&json));
    let info = ChatLottieInfo {
        width: composition.width,
        height: composition.height,
        frame_count,
        frame_rate,
        features,
    };
    Ok((
        info,
        ChatLottie {
            renderer: CPURenderer::new(composition),
        },
    ))
}

#[no_mangle]
pub extern "C" fn chat_lottie_abi_version() -> u32 {
    ABI_VERSION
}

/// # Safety
/// `data..data+len` must be readable; `out_info` and `out_handle` writable.
#[no_mangle]
pub unsafe extern "C" fn chat_lottie_load(
    data: *const u8,
    len: usize,
    out_info: *mut ChatLottieInfo,
    out_handle: *mut *mut ChatLottie,
) -> i32 {
    guarded(status::INTERNAL, || {
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

/// Largest frame edge a batch accepts. Stickers are drawn at a few hundred
/// pixels at most; the cap bounds the scratch buffer a hostile job can force.
pub const MAX_FRAME_EDGE: u32 = 512;

/// One frame to draw into a slot of page memory.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ChatLottieJob {
    pub handle: *mut ChatLottie,
    pub frame: f32,
    pub width: u32,
    pub height: u32,
    /// Top-left pixel of the slot; rows are `stride_bytes` apart.
    pub target: *mut u8,
    pub stride_bytes: usize,
}

/// Draws `job` into its slot, premultiplied `[R, G, B, A]`, touching only the
/// first `width * 4` bytes of each of `height` rows.
///
/// # Safety
/// The job's pointers must satisfy the contract in `chat_lottie.h`.
unsafe fn render_job(job: &ChatLottieJob, scratch: &mut Vec<u32>) -> i32 {
    let Some(animation) = (unsafe { job.handle.as_mut() }) else {
        return status::INVALID_ARGUMENT;
    };
    if job.target.is_null() {
        return status::INVALID_ARGUMENT;
    }
    if job.width == 0
        || job.height == 0
        || job.width > MAX_FRAME_EDGE
        || job.height > MAX_FRAME_EDGE
    {
        return status::BAD_SIZE;
    }
    let (width, height) = (job.width as usize, job.height as usize);
    let row_bytes = width * 4;
    // The last row ends at (height - 1) * stride + row_bytes; it must be addressable.
    let extent = (height - 1)
        .checked_mul(job.stride_bytes)
        .and_then(|n| n.checked_add(row_bytes));
    if job.stride_bytes < row_bytes || extent.is_none_or(|n| n > isize::MAX as usize) {
        return status::BAD_SIZE;
    }
    scratch.clear();
    scratch.resize(width * height, 0);
    let options = tlottie::RenderOptions::default();
    if animation
        .renderer
        .render(job.frame, scratch, job.width, job.height, options)
        .is_err()
    {
        return status::RENDER_FAILED;
    }
    for (y, row) in scratch.chunks_exact(width).enumerate() {
        // SAFETY: extent above proved row y lies inside the caller's slot.
        let out = unsafe {
            std::slice::from_raw_parts_mut(job.target.add(y * job.stride_bytes), row_bytes)
        };
        let (quads, _) = out.as_chunks_mut::<4>();
        for (bytes, pixel) in quads.iter_mut().zip(row) {
            // tlottie's RGBA word is 0xAABBGGRR; little-endian bytes are [R, G, B, A].
            *bytes = pixel.to_le_bytes();
        }
    }
    status::OK
}

/// # Safety
/// `jobs` and `statuses` must each point to `count` valid elements.
#[no_mangle]
pub unsafe extern "C" fn chat_lottie_render_batch(
    jobs: *const ChatLottieJob,
    count: usize,
    statuses: *mut i32,
) -> i32 {
    if count == 0 {
        return status::OK;
    }
    if jobs.is_null() || statuses.is_null() {
        return status::INVALID_ARGUMENT;
    }
    let jobs = unsafe { std::slice::from_raw_parts(jobs, count) };
    let statuses = unsafe { std::slice::from_raw_parts_mut(statuses, count) };
    let mut scratch = Vec::new();
    for (job, slot) in jobs.iter().zip(statuses) {
        // A panic in one job is that job's failure, not the batch's.
        *slot = guarded(status::INTERNAL, || unsafe {
            render_job(job, &mut scratch)
        });
    }
    status::OK
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_caught_panic_is_internal_not_malformed() {
        let caught = guarded(status::INTERNAL, || -> i32 { panic!("a bug") });
        assert_eq!(caught, -6);
        assert_ne!(caught, status::MALFORMED);
    }
}
