use chat_lottie::{
    chat_lottie_compress_region, chat_lottie_decompress_region, chat_lottie_lz4_bound,
};

const GUARD: u8 = 0xAB;
const BAD_ARG: i32 = -1;
const TOO_SMALL: i32 = -2;
const MALFORMED: i32 = -3;
const BAD_SIZE: i32 = -7;

/// A premultiplied-looking gradient with varying alpha, tight rows.
fn gradient(w: u32, h: u32) -> Vec<u8> {
    let mut px = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let a = (255 * (x + y) / (w + h - 2).max(1)) as u8;
            px.extend_from_slice(&[a / 2, a / 3, a / 4, a]);
        }
    }
    px
}

fn noise(len: usize) -> Vec<u8> {
    let mut state = 0x2545_F491_4F6C_DD1Du64;
    (0..len)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            (state >> 32) as u8
        })
        .collect()
}

/// A page of `GUARD` bytes with `pixels` (tight, `w` x `h`) copied into the
/// slot at (`x0`, `y0`); returns the page and its stride.
fn page_with(pixels: &[u8], w: u32, h: u32, x0: usize, y0: usize) -> (Vec<u8>, usize) {
    let stride = (w as usize + 2 * x0) * 4 + 8;
    let mut page = vec![GUARD; stride * (h as usize + 2 * y0)];
    for y in 0..h as usize {
        let at = (y0 + y) * stride + x0 * 4;
        page[at..at + w as usize * 4]
            .copy_from_slice(&pixels[y * w as usize * 4..][..w as usize * 4]);
    }
    (page, stride)
}

fn compress(target: &[u8], stride: usize, w: u32, h: u32) -> Vec<u8> {
    let mut dst = vec![0u8; chat_lottie_lz4_bound(w, h)];
    let mut len = 0usize;
    let status = unsafe {
        chat_lottie_compress_region(
            target.as_ptr(),
            stride,
            w,
            h,
            dst.as_mut_ptr(),
            dst.len(),
            &mut len,
        )
    };
    assert_eq!(status, 0);
    dst.truncate(len);
    dst
}

fn decompress(src: &[u8], target: &mut [u8], stride: usize, w: u32, h: u32) -> i32 {
    unsafe {
        chat_lottie_decompress_region(src.as_ptr(), src.len(), target.as_mut_ptr(), stride, w, h)
    }
}

fn round_trip(pixels: &[u8], w: u32, h: u32) -> Vec<u8> {
    let (src_page, src_stride) = page_with(pixels, w, h, 3, 2);
    let packed = compress(&src_page[2 * src_stride + 12..], src_stride, w, h);
    let (mut out_page, out_stride) = page_with(&vec![0; pixels.len()], w, h, 5, 1);
    let guarded_before = out_page.clone();
    let status = decompress(&packed, &mut out_page[out_stride + 20..], out_stride, w, h);
    assert_eq!(status, 0);
    // Everything outside the slot is as it was.
    for (i, (a, b)) in out_page.iter().zip(&guarded_before).enumerate() {
        let (y, x) = (i / out_stride, (i % out_stride) / 4);
        let inside = (1..1 + h as usize).contains(&y) && (5..5 + w as usize).contains(&x);
        if !inside {
            assert_eq!(a, b, "byte {i} outside the slot changed");
        }
    }
    let mut got = Vec::new();
    for y in 0..h as usize {
        got.extend_from_slice(&out_page[(1 + y) * out_stride + 20..][..w as usize * 4]);
    }
    got
}

#[test]
fn a_gradient_with_alpha_round_trips_byte_exact_and_shrinks() {
    let px = gradient(64, 48);
    assert_eq!(round_trip(&px, 64, 48), px);
    let (page, stride) = page_with(&px, 64, 48, 0, 0);
    assert!(compress(&page, stride, 64, 48).len() < px.len());
}

#[test]
fn an_all_transparent_region_round_trips_and_shrinks() {
    let px = vec![0u8; 64 * 64 * 4];
    assert_eq!(round_trip(&px, 64, 64), px);
    let (page, stride) = page_with(&px, 64, 64, 0, 0);
    assert!(compress(&page, stride, 64, 64).len() < px.len() / 10);
}

#[test]
fn noise_round_trips_and_never_exceeds_the_bound() {
    for (w, h) in [(1, 1), (7, 5), (33, 17), (512, 512)] {
        let px = noise((w * h * 4) as usize);
        assert_eq!(round_trip(&px, w, h), px);
        let (page, stride) = page_with(&px, w, h, 0, 0);
        assert!(compress(&page, stride, w, h).len() <= chat_lottie_lz4_bound(w, h));
    }
}

#[test]
fn the_bound_covers_the_raw_size_and_is_zero_for_a_bad_size() {
    assert!(chat_lottie_lz4_bound(10, 10) >= 400);
    assert_eq!(chat_lottie_lz4_bound(0, 10), 0);
    assert_eq!(chat_lottie_lz4_bound(513, 10), 0);
}

#[test]
fn compress_reads_only_the_region() {
    // Rows past the described region are unreadable poison: a read of them
    // would change the output.
    let px = gradient(8, 4);
    let (mut page, stride) = page_with(&px, 8, 4, 0, 0);
    let clean = compress(&page, stride, 8, 4);
    for y in 0..4 {
        for b in &mut page[y * stride + 32..(y + 1) * stride] {
            *b = 0x11; // the gap between rows
        }
    }
    assert_eq!(compress(&page, stride, 8, 4), clean);
}

#[test]
fn dst_cap_one_byte_short_is_too_small_and_exact_fits() {
    let px = gradient(16, 16);
    let (page, stride) = page_with(&px, 16, 16, 0, 0);
    let need = compress(&page, stride, 16, 16).len();
    let mut dst = vec![0u8; need + 1];
    let mut len = 77usize;
    let short = unsafe {
        chat_lottie_compress_region(
            page.as_ptr(),
            stride,
            16,
            16,
            dst.as_mut_ptr(),
            need - 1,
            &mut len,
        )
    };
    assert_eq!(short, TOO_SMALL);
    assert_eq!(len, 77, "out_len is untouched on failure");
    assert_eq!(dst[need], 0, "nothing past dst_cap is written");
    let exact = unsafe {
        chat_lottie_compress_region(
            page.as_ptr(),
            stride,
            16,
            16,
            dst.as_mut_ptr(),
            need,
            &mut len,
        )
    };
    assert_eq!((exact, len), (0, need));
}

#[test]
fn compress_rejects_null_and_bad_sizes() {
    let px = gradient(8, 8);
    let (page, stride) = page_with(&px, 8, 8, 0, 0);
    let mut dst = vec![0u8; 1024];
    let mut len = 0usize;
    let call = |t: *const u8, s: usize, w: u32, h: u32, d: *mut u8, o: *mut usize| unsafe {
        chat_lottie_compress_region(t, s, w, h, d, 1024, o)
    };
    assert_eq!(
        call(std::ptr::null(), stride, 8, 8, dst.as_mut_ptr(), &mut len),
        BAD_ARG
    );
    assert_eq!(
        call(page.as_ptr(), stride, 8, 8, std::ptr::null_mut(), &mut len),
        BAD_ARG
    );
    assert_eq!(
        call(
            page.as_ptr(),
            stride,
            8,
            8,
            dst.as_mut_ptr(),
            std::ptr::null_mut()
        ),
        BAD_ARG
    );
    assert_eq!(
        call(page.as_ptr(), stride, 0, 8, dst.as_mut_ptr(), &mut len),
        BAD_SIZE
    );
    assert_eq!(
        call(page.as_ptr(), stride, 8, 0, dst.as_mut_ptr(), &mut len),
        BAD_SIZE
    );
    assert_eq!(
        call(page.as_ptr(), stride, 513, 8, dst.as_mut_ptr(), &mut len),
        BAD_SIZE
    );
    assert_eq!(
        call(page.as_ptr(), 31, 8, 8, dst.as_mut_ptr(), &mut len),
        BAD_SIZE
    );
    assert_eq!(
        call(page.as_ptr(), usize::MAX, 8, 8, dst.as_mut_ptr(), &mut len),
        BAD_SIZE
    );
}

#[test]
fn decompress_rejects_null_and_bad_sizes_without_writing() {
    let px = gradient(8, 8);
    let (page, stride) = page_with(&px, 8, 8, 0, 0);
    let packed = compress(&page, stride, 8, 8);
    let mut target = vec![GUARD; 8 * 8 * 4];
    let call = |s: *const u8, t: *mut u8, stride: usize, w: u32, h: u32| unsafe {
        chat_lottie_decompress_region(s, packed.len(), t, stride, w, h)
    };
    assert_eq!(
        call(std::ptr::null(), target.as_mut_ptr(), 32, 8, 8),
        BAD_ARG
    );
    assert_eq!(
        call(packed.as_ptr(), std::ptr::null_mut(), 32, 8, 8),
        BAD_ARG
    );
    assert_eq!(
        call(packed.as_ptr(), target.as_mut_ptr(), 32, 0, 8),
        BAD_SIZE
    );
    assert_eq!(
        call(packed.as_ptr(), target.as_mut_ptr(), 32, 513, 8),
        BAD_SIZE
    );
    assert_eq!(
        call(packed.as_ptr(), target.as_mut_ptr(), 31, 8, 8),
        BAD_SIZE
    );
    assert!(target.iter().all(|&b| b == GUARD));
}

#[test]
fn truncated_and_bit_flipped_streams_are_malformed_and_write_nothing() {
    let px = gradient(16, 16);
    let (page, stride) = page_with(&px, 16, 16, 0, 0);
    let packed = compress(&page, stride, 16, 16);
    let mut bad: Vec<Vec<u8>> = vec![
        Vec::new(),
        packed[..packed.len() / 2].to_vec(),
        packed[..packed.len() - 1].to_vec(),
    ];
    for i in 0..packed.len().min(40) {
        let mut flipped = packed.clone();
        flipped[i] ^= 0xFF;
        bad.push(flipped);
    }
    // A valid stream for another size: right format, wrong byte count.
    let (small, small_stride) = page_with(&px[..8 * 8 * 4], 8, 8, 0, 0);
    bad.push(compress(&small, small_stride, 8, 8));
    let mut checked = 0;
    for stream in &bad {
        let mut target = vec![GUARD; 16 * 16 * 4];
        let status = decompress(stream, &mut target, 16 * 4, 16, 16);
        if status == 0 {
            // A flip inside literal bytes is still a well-formed stream of the
            // right length; that is not corruption lz4 can see.
            continue;
        }
        checked += 1;
        assert_eq!(status, MALFORMED);
        assert!(
            target.iter().all(|&b| b == GUARD),
            "a failed decompress wrote"
        );
    }
    assert!(
        checked >= 5,
        "too few corrupt streams were rejected: {checked}"
    );
}

#[test]
fn a_stream_for_another_size_is_malformed() {
    let px = gradient(8, 8);
    let (page, stride) = page_with(&px, 8, 8, 0, 0);
    let packed = compress(&page, stride, 8, 8);
    let mut target = vec![GUARD; 16 * 8 * 4];
    assert_eq!(decompress(&packed, &mut target, 16 * 4, 16, 8), MALFORMED);
    assert!(target.iter().all(|&b| b == GUARD));
}
