//! Status codes of the C ABI. Negative values are failures; the numbers are
//! part of the contract in `include/chat_lottie.h`, and each means one thing
//! across load and render.

/// Success.
pub const OK: i32 = 0;
/// A null pointer or an otherwise unusable argument.
pub const INVALID_ARGUMENT: i32 = -1;
/// Load: encoded input or inflated output over its cap.
pub const TOO_LARGE: i32 = -2;
/// Load: not gzip, not JSON, or not a Lottie composition.
pub const MALFORMED: i32 = -3;
/// Load: a tlottie `Limits` budget was exceeded.
pub const LIMIT_EXCEEDED: i32 = -4;
/// Load: the file parses but has nothing to draw.
pub const UNSUPPORTED: i32 = -5;
/// A panic caught at the boundary: a bug in this library, never the file's fault.
pub const INTERNAL: i32 = -6;
/// Render: zero edge, edge over the cap, stride under the row width, or the
/// byte size overflows.
pub const BAD_SIZE: i32 = -7;
/// Render: tlottie failed to draw the frame.
pub const RENDER_FAILED: i32 = -8;
