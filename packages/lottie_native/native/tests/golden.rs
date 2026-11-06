//! The cross-build golden: one frame of the hand-authored fixture, drawn by
//! the host build, must stay within one colour level per channel of
//! `fixtures/golden_64x64_frame_30.rgba`. The Node tests hold the two wasm
//! builds (SIMD and plain) to the same file, so the native and web builds
//! cannot drift apart unnoticed.
//!
//! The file is premultiplied `[R, G, B, A]`, 64 x 64, tightly packed (16384
//! bytes). It draws the repository's own fixture (`common::fixture`, mirrored
//! in `web/test/fixture.json`), so it is redistributable. To regenerate it
//! after a deliberate change of the renderer, from this directory:
//!
//!     CHAT_LOTTIE_UPDATE_GOLDEN=1 cargo test --test golden
//!
//! and review the diff of the fixture like any other change.
mod common;
use chat_lottie::{chat_lottie_render_batch, ChatLottieJob};
use common::*;

const FRAME: f32 = 30.0;
const EDGE: u32 = 64;
const GOLDEN: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/tests/fixtures/golden_64x64_frame_30.rgba"
);

fn render() -> Vec<u8> {
    let loaded = load(fixture().as_bytes());
    let mut pixels = vec![0u8; (EDGE * EDGE * 4) as usize];
    let jobs = [ChatLottieJob {
        handle: loaded.handle,
        frame: FRAME,
        width: EDGE,
        height: EDGE,
        target: pixels.as_mut_ptr(),
        stride_bytes: (EDGE * 4) as usize,
    }];
    let mut status = [99i32];
    let ran = unsafe { chat_lottie_render_batch(jobs.as_ptr(), 1, status.as_mut_ptr()) };
    assert_eq!((ran, status[0]), (0, 0));
    pixels
}

#[test]
fn the_host_build_draws_the_golden_frame_within_one_level() {
    let drawn = render();
    if std::env::var_os("CHAT_LOTTIE_UPDATE_GOLDEN").is_some() {
        std::fs::write(GOLDEN, &drawn).expect("write the golden");
        return;
    }
    let golden = std::fs::read(GOLDEN).unwrap_or_else(|e| {
        panic!(
            "{GOLDEN}: {e}; regenerate with CHAT_LOTTIE_UPDATE_GOLDEN=1 cargo test --test golden"
        )
    });
    assert_eq!(golden.len(), drawn.len(), "the golden is 64 x 64 RGBA");
    let worst = golden
        .iter()
        .zip(&drawn)
        .map(|(a, b)| a.abs_diff(*b))
        .max()
        .unwrap_or(0);
    assert!(
        worst <= 1,
        "the host build differs from the golden by {worst} levels"
    );
}

#[test]
fn the_golden_is_a_visible_premultiplied_frame() {
    let golden = std::fs::read(GOLDEN).expect("the golden file");
    let (quads, _) = golden.as_chunks::<4>();
    assert!(quads.iter().any(|p| p[3] > 0), "the square is visible");
    assert!(
        quads.iter().any(|p| p[3] == 0),
        "the corners are transparent"
    );
    for p in quads {
        assert!(
            p[0] <= p[3] && p[1] <= p[3] && p[2] <= p[3],
            "{p:?} is not premultiplied"
        );
    }
}
