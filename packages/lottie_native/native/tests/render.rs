mod common;
use chat_lottie::{chat_lottie_render_batch, ChatLottie, ChatLottieJob};
use common::*;

const GUARD: u8 = 0xAB;

fn job(
    handle: *mut ChatLottie,
    frame: f32,
    size: u32,
    target: *mut u8,
    stride: usize,
) -> ChatLottieJob {
    ChatLottieJob {
        handle,
        frame,
        width: size,
        height: size,
        target,
        stride_bytes: stride,
    }
}

/// Renders one frame into a tight `size` x `size` buffer.
fn render_tight(loaded: &Loaded, frame: f32, size: u32) -> Vec<u8> {
    let mut pixels = vec![0u8; (size * size * 4) as usize];
    let jobs = [job(
        loaded.handle,
        frame,
        size,
        pixels.as_mut_ptr(),
        (size * 4) as usize,
    )];
    let mut statuses = [99i32];
    let ran = unsafe { chat_lottie_render_batch(jobs.as_ptr(), 1, statuses.as_mut_ptr()) };
    assert_eq!((ran, statuses[0]), (0, 0));
    pixels
}

#[test]
fn pixels_are_premultiplied_rgba() {
    let loaded = load(fixture().as_bytes());
    let pixels = render_tight(&loaded, 0.0, 64);
    let mut partial = 0;
    for px in pixels.as_chunks::<4>().0 {
        let (r, g, b, a) = (px[0], px[1], px[2], px[3]);
        assert!(r <= a && g <= a && b <= a, "channel above alpha: {px:?}");
        if a > 0 && a < 255 {
            partial += 1;
        }
    }
    assert!(
        partial > 0,
        "the 50% fill must produce semi-transparent pixels"
    );
    // Centre of the square: orange (1, .5, .25) at 50% premultiplied is about (128, 64, 32, 128), in R, G, B order.
    let centre = &pixels[(32 * 64 + 32) * 4..][..4];
    assert!((i32::from(centre[3]) - 128).abs() <= 2, "{centre:?}");
    assert!((i32::from(centre[0]) - 128).abs() <= 2, "{centre:?}");
    assert!((i32::from(centre[1]) - 64).abs() <= 2, "{centre:?}");
    assert!((i32::from(centre[2]) - 32).abs() <= 2, "{centre:?}");
}

#[test]
fn render_writes_only_inside_the_slot() {
    let loaded = load(fixture().as_bytes());
    let (page_w, page_h, size) = (80usize, 80usize, 64usize);
    let (x, y) = (8usize, 8usize);
    let stride = page_w * 4;
    let mut page = vec![GUARD; stride * page_h];
    let origin = y * stride + x * 4;
    let jobs = [job(
        loaded.handle,
        10.0,
        size as u32,
        page[origin..].as_mut_ptr(),
        stride,
    )];
    let mut statuses = [99i32];
    let ran = unsafe { chat_lottie_render_batch(jobs.as_ptr(), 1, statuses.as_mut_ptr()) };
    assert_eq!((ran, statuses[0]), (0, 0));

    let expected = render_tight(&loaded, 10.0, size as u32);
    for row in 0..page_h {
        for col in 0..page_w {
            let at = row * stride + col * 4;
            let inside = (y..y + size).contains(&row) && (x..x + size).contains(&col);
            if inside {
                let slot = ((row - y) * size + (col - x)) * 4;
                assert_eq!(
                    page[at..at + 4],
                    expected[slot..slot + 4],
                    "pixel {col},{row}"
                );
            } else {
                assert!(
                    page[at..at + 4].iter().all(|b| *b == GUARD),
                    "guard hit at {col},{row}"
                );
            }
        }
    }
}

#[test]
fn bad_job_gets_its_status_and_the_others_render() {
    let loaded = load(fixture().as_bytes());
    let expected = render_tight(&loaded, 5.0, 32);
    let mut a = vec![0u8; 32 * 32 * 4];
    let mut b = vec![0u8; 32 * 32 * 4];
    let mut unused = vec![GUARD; 32 * 32 * 4];
    let jobs = [
        job(loaded.handle, 5.0, 32, a.as_mut_ptr(), 128),
        job(std::ptr::null_mut(), 5.0, 32, unused.as_mut_ptr(), 128),
        job(loaded.handle, 5.0, 32, unused.as_mut_ptr(), 100), // stride below width * 4
        job(loaded.handle, 5.0, 513, unused.as_mut_ptr(), 513 * 4), // over the size cap
        job(loaded.handle, 5.0, 0, unused.as_mut_ptr(), 0),
        job(loaded.handle, 5.0, 32, std::ptr::null_mut(), 128),
        job(loaded.handle, 5.0, 32, b.as_mut_ptr(), 128),
    ];
    let mut statuses = [99i32; 7];
    let ran = unsafe { chat_lottie_render_batch(jobs.as_ptr(), jobs.len(), statuses.as_mut_ptr()) };
    assert_eq!(ran, 0);
    assert_eq!(statuses, [0, -1, -7, -7, -7, -1, 0]);
    assert_eq!(a, expected);
    assert_eq!(b, expected);
    assert!(
        unused.iter().all(|v| *v == GUARD),
        "a rejected job must not write"
    );
}

#[test]
fn stride_smaller_than_a_row_is_rejected() {
    let loaded = load(fixture().as_bytes());
    let mut buf = vec![GUARD; 64 * 64 * 4];
    let jobs = [job(loaded.handle, 0.0, 64, buf.as_mut_ptr(), 64 * 4 - 1)];
    let mut statuses = [99i32];
    unsafe { chat_lottie_render_batch(jobs.as_ptr(), 1, statuses.as_mut_ptr()) };
    assert_eq!(statuses[0], -7);
}

#[test]
fn edge_over_the_cap_and_zero_edge_are_bad_size() {
    let loaded = load(fixture().as_bytes());
    let mut buf = vec![GUARD; 8];
    for (w, h) in [(0, 8), (8, 0), (513, 8), (8, 513)] {
        let mut j = job(loaded.handle, 0.0, 8, buf.as_mut_ptr(), 4096);
        j.width = w;
        j.height = h;
        let mut statuses = [99i32];
        unsafe { chat_lottie_render_batch(&j, 1, statuses.as_mut_ptr()) };
        assert_eq!(statuses[0], -7, "{w}x{h}");
    }
}

#[test]
fn byte_size_overflow_is_bad_size() {
    let loaded = load(fixture().as_bytes());
    let mut buf = vec![GUARD; 8];
    let j = job(loaded.handle, 0.0, 8, buf.as_mut_ptr(), usize::MAX);
    let mut statuses = [99i32];
    unsafe { chat_lottie_render_batch(&j, 1, statuses.as_mut_ptr()) };
    assert_eq!(statuses[0], -7);
}

#[test]
fn null_batch_arguments() {
    let mut status = [99i32];
    unsafe {
        assert_eq!(
            chat_lottie_render_batch(std::ptr::null(), 1, status.as_mut_ptr()),
            -1
        );
        let loaded = load(fixture().as_bytes());
        let mut buf = vec![0u8; 16 * 16 * 4];
        let jobs = [job(loaded.handle, 0.0, 16, buf.as_mut_ptr(), 64)];
        assert_eq!(
            chat_lottie_render_batch(jobs.as_ptr(), 1, std::ptr::null_mut()),
            -1
        );
        assert_eq!(
            chat_lottie_render_batch(std::ptr::null(), 0, std::ptr::null_mut()),
            0
        );
    }
}

#[test]
fn two_handles_on_two_threads_match_serial_output() {
    let json = fixture();
    let frames: Vec<f32> = (0..30).map(|i| i as f32 * 2.0).collect();
    let serial = load(json.as_bytes());
    let expected: Vec<Vec<u8>> = frames
        .iter()
        .map(|f| render_tight(&serial, *f, 48))
        .collect();

    let workers: Vec<_> = (0..2)
        .map(|_| {
            let handle = load(json.as_bytes());
            let frames = frames.clone();
            std::thread::spawn(move || {
                frames
                    .iter()
                    .map(|f| render_tight(&handle, *f, 48))
                    .collect::<Vec<_>>()
            })
        })
        .collect();
    for worker in workers {
        assert_eq!(worker.join().unwrap(), expected);
    }
}
