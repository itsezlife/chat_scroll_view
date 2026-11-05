//! What a file uses that tlottie does not render. Informational only.

pub const LAYER_EFFECTS: u32 = 1;
pub const EXPRESSIONS: u32 = 2;
pub const IMAGES: u32 = 4;
pub const TEXT: u32 = 8;

/// Bitmask of unrendered features in `json`; `0` when the scan cannot run.
pub fn scan(_json: &[u8]) -> u32 {
    0
}
