//! The frame cache's lz4 codec over regions of page memory.
//!
//! It lives in the wrapper, not in Dart, so the web build shares it
//! (ADR 042). A region is `height` rows of `width * 4` bytes, rows
//! `stride_bytes` apart; it is packed as one lz4 block of the tight pixels.

use crate::guarded;
use crate::status;
use crate::MAX_FRAME_EDGE;
use lz4_flex::block::{compress_into, decompress_into, get_maximum_output_size};

/// The row width and `width * height * 4`, or `BAD_SIZE` for a zero edge, an
/// edge over the cap, a stride under the row width, or a last row that is
/// not addressable.
fn region_size(width: u32, height: u32, stride_bytes: usize) -> Result<(usize, usize), i32> {
    if width == 0 || height == 0 || width > MAX_FRAME_EDGE || height > MAX_FRAME_EDGE {
        return Err(status::BAD_SIZE);
    }
    let row_bytes = width as usize * 4;
    // The last row ends at (height - 1) * stride + row_bytes; it must be addressable.
    let extent = (height as usize - 1)
        .checked_mul(stride_bytes)
        .and_then(|n| n.checked_add(row_bytes));
    if stride_bytes < row_bytes || extent.is_none_or(|n| n > isize::MAX as usize) {
        return Err(status::BAD_SIZE);
    }
    Ok((row_bytes, row_bytes * height as usize))
}

/// The most bytes a compressed `width` x `height` RGBA region can take, or 0
/// when the size is not one the codec accepts (zero edge, edge over 512).
#[no_mangle]
pub extern "C" fn chat_lottie_lz4_bound(width: u32, height: u32) -> usize {
    guarded(0, || match region_size(width, height, width as usize * 4) {
        Ok((_, raw)) => get_maximum_output_size(raw),
        Err(_) => 0,
    })
}

/// # Safety
/// `target` must be readable for the region described by the other
/// arguments, `dst..dst+dst_cap` writable, and `out_len` writable.
#[no_mangle]
pub unsafe extern "C" fn chat_lottie_compress_region(
    target: *const u8,
    stride_bytes: usize,
    width: u32,
    height: u32,
    dst: *mut u8,
    dst_cap: usize,
    out_len: *mut usize,
) -> i32 {
    guarded(status::INTERNAL, || {
        if target.is_null() || dst.is_null() || out_len.is_null() {
            return status::INVALID_ARGUMENT;
        }
        // No buffer is longer than isize::MAX bytes; a larger capacity is a
        // lie about the caller's memory, so it is a bad size, not "plenty".
        if dst_cap > isize::MAX as usize {
            return status::BAD_SIZE;
        }
        let (row_bytes, raw) = match region_size(width, height, stride_bytes) {
            Ok(sizes) => sizes,
            Err(code) => return code,
        };
        let mut tight = Vec::with_capacity(raw);
        for y in 0..height as usize {
            // SAFETY: region_size proved row y lies inside the caller's region.
            tight.extend_from_slice(unsafe {
                std::slice::from_raw_parts(target.add(y * stride_bytes), row_bytes)
            });
        }
        // Compress into a scratch of the worst case, then fit: the encoder
        // wants slack past the final size, so compressing straight into
        // `dst` would refuse a destination that is exactly big enough.
        let mut packed = vec![0u8; get_maximum_output_size(raw)];
        let Ok(len) = compress_into(&tight, &mut packed) else {
            return status::INTERNAL;
        };
        if len > dst_cap {
            return status::TOO_LARGE;
        }
        // SAFETY: the caller owns dst..dst+dst_cap and len <= dst_cap.
        unsafe {
            std::ptr::copy_nonoverlapping(packed.as_ptr(), dst, len);
            *out_len = len;
        }
        status::OK
    })
}

/// # Safety
/// `src..src+src_len` must be readable and `target` writable for the region
/// described by the other arguments.
#[no_mangle]
pub unsafe extern "C" fn chat_lottie_decompress_region(
    src: *const u8,
    src_len: usize,
    target: *mut u8,
    stride_bytes: usize,
    width: u32,
    height: u32,
) -> i32 {
    guarded(status::INTERNAL, || {
        if src.is_null() || target.is_null() {
            return status::INVALID_ARGUMENT;
        }
        // Checked before from_raw_parts: no slice is longer than isize::MAX.
        if src_len > isize::MAX as usize {
            return status::BAD_SIZE;
        }
        let (row_bytes, raw) = match region_size(width, height, stride_bytes) {
            Ok(sizes) => sizes,
            Err(code) => return code,
        };
        // SAFETY: the caller owns src..src+src_len.
        let packed = unsafe { std::slice::from_raw_parts(src, src_len) };
        // Decode into a temporary first: a corrupt stream must leave the
        // region untouched, and a short one must not leave half a frame.
        let mut tight = vec![0u8; raw];
        match decompress_into(packed, &mut tight) {
            Ok(len) if len == raw => {}
            _ => return status::MALFORMED,
        }
        for (y, row) in tight.chunks_exact(row_bytes).enumerate() {
            // SAFETY: region_size proved row y lies inside the caller's region.
            unsafe {
                std::ptr::copy_nonoverlapping(row.as_ptr(), target.add(y * stride_bytes), row_bytes)
            };
        }
        status::OK
    })
}
