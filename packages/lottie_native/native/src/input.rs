//! Bytes in, Lottie JSON out: size caps and the optional gunzip.

use crate::status;
use flate2::read::GzDecoder;
use std::borrow::Cow;
use std::io::Read;

/// Cap on the encoded input. A sticker is tens of KiB; this leaves room for
/// the largest legitimate file while keeping an upload from pinning memory.
pub const MAX_ENCODED_BYTES: usize = 4 * 1024 * 1024;

/// Cap on the inflated JSON. Matches the reference web client; it sits under
/// tlottie's own 16 MiB input limit, so the gunzip cap is the binding one.
pub const MAX_INFLATED_BYTES: usize = 8 * 1024 * 1024;

const GZIP_MAGIC: [u8; 2] = [0x1f, 0x8b];

/// Returns the JSON bytes: `data` itself, or its gunzipped form for a TGS.
pub fn lottie_json(data: &[u8]) -> Result<Cow<'_, [u8]>, i32> {
    if data.len() > MAX_ENCODED_BYTES {
        return Err(status::TOO_LARGE);
    }
    if !data.starts_with(&GZIP_MAGIC) {
        return Ok(Cow::Borrowed(data));
    }
    // Read one byte past the cap: a bomb is caught at the cap instead of
    // after inflating all of it, and exactly-at-cap output still passes.
    let mut inflated = Vec::new();
    let read = GzDecoder::new(data)
        .take(MAX_INFLATED_BYTES as u64 + 1)
        .read_to_end(&mut inflated);
    if read.is_err() {
        return Err(status::MALFORMED);
    }
    if inflated.len() > MAX_INFLATED_BYTES {
        return Err(status::TOO_LARGE);
    }
    Ok(Cow::Owned(inflated))
}
