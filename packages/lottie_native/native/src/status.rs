//! Status codes of the C ABI. Negative values are failures; the numbers are
//! part of the contract in `include/chat_lottie.h`.

/// Success.
pub const OK: i32 = 0;
/// A null pointer or an otherwise unusable argument.
pub const INVALID_ARGUMENT: i32 = -1;
/// Load: input over a size cap. Render: stride or size arithmetic overflowed.
pub const TOO_LARGE: i32 = -2;
/// Load: not gzip, not JSON, or not a Lottie composition. Also what a panic maps to.
pub const MALFORMED: i32 = -3;
/// Load: a tlottie `Limits` budget was exceeded.
pub const LIMIT_EXCEEDED: i32 = -4;
/// Load: the file parses but has nothing to draw.
pub const UNSUPPORTED: i32 = -5;
/// Render: tlottie failed to draw the frame.
pub const RENDER_FAILED: i32 = -3;
