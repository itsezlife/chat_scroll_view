//! Allocation exports for the WebAssembly build.
//!
//! JavaScript cannot write into a module's memory without owning a region of
//! it, and the module has no imports to ask the host with, so the module hands
//! out its own allocator. The pair is web-only (`target_arch = "wasm32"`); the
//! layout rule is compiled on every target so the host test suite covers it.

use std::alloc::Layout;

/// Largest region JavaScript may ask for: 256 MiB. Encoded input is capped at
/// 4 MiB and a frame at 1 MiB, so the cap is generous; it only bounds what a
/// confused or hostile caller can make the module reserve.
pub const MAX_ALLOC_BYTES: usize = 256 * 1024 * 1024;

/// The layout of a `len`-byte region, or `None` for 0 and for sizes over
/// [`MAX_ALLOC_BYTES`]. Bytes need no alignment beyond 1; the header's
/// structs are filled by JavaScript field by field, and 4 keeps them aligned
/// for the module's own reads.
pub fn layout_for(len: usize) -> Option<Layout> {
    if len == 0 || len > MAX_ALLOC_BYTES {
        return None;
    }
    Layout::from_size_align(len, 4).ok()
}

#[cfg(target_arch = "wasm32")]
mod exports {
    use super::layout_for;
    use crate::guarded;

    /// Reserves `len` bytes of module memory; null for 0 and for sizes over
    /// the cap. The caller returns it with `chat_lottie_dealloc` and the same
    /// `len`.
    #[no_mangle]
    pub extern "C" fn chat_lottie_alloc(len: usize) -> *mut u8 {
        guarded(std::ptr::null_mut(), || match layout_for(len) {
            // SAFETY: the layout has a non-zero size.
            Some(layout) => unsafe { std::alloc::alloc(layout) },
            None => std::ptr::null_mut(),
        })
    }

    /// # Safety
    /// `ptr` is null or came from `chat_lottie_alloc(len)` with this `len` and
    /// is not freed yet.
    #[no_mangle]
    pub unsafe extern "C" fn chat_lottie_dealloc(ptr: *mut u8, len: usize) {
        if ptr.is_null() {
            return;
        }
        if let Some(layout) = layout_for(len) {
            // SAFETY: the caller's contract above; the layout is the one alloc used.
            guarded((), || unsafe { std::alloc::dealloc(ptr, layout) });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_bytes_has_no_layout() {
        assert!(layout_for(0).is_none());
    }

    #[test]
    fn the_cap_is_inclusive_and_one_past_it_is_refused() {
        assert_eq!(
            layout_for(256 * 1024 * 1024).map(|l| l.size()),
            Some(268_435_456)
        );
        assert!(layout_for(256 * 1024 * 1024 + 1).is_none());
        assert!(layout_for(usize::MAX).is_none());
    }

    #[test]
    fn an_ordinary_size_keeps_its_length() {
        assert_eq!(layout_for(1).map(|l| l.size()), Some(1));
        assert_eq!(layout_for(4096).map(|l| l.size()), Some(4096));
    }
}
