mod common;
use common::*;

#[test]
fn json_loads_and_reports_its_info() {
    let loaded = load(fixture().as_bytes());
    assert_eq!(loaded.info.width, 100);
    assert_eq!(loaded.info.height, 100);
    assert_eq!(loaded.info.frame_count, 60);
    assert_eq!(loaded.info.frame_rate, 30.0);
    assert_eq!(loaded.info.features, 0);
}

#[test]
fn gzipped_json_loads_the_same() {
    let plain = load(fixture().as_bytes());
    let zipped = load(&gzip(fixture().as_bytes()));
    assert_eq!(zipped.info.width, plain.info.width);
    assert_eq!(zipped.info.frame_count, plain.info.frame_count);
}

#[test]
fn gzip_bomb_stops_at_the_inflated_cap() {
    // 64 MiB of spaces compresses to a few tens of KiB, far under the
    // encoded cap, so only the inflated cap can reject it.
    let bomb = gzip(&vec![b' '; 64 * 1024 * 1024]);
    assert!(bomb.len() < 1024 * 1024);
    assert_eq!(try_load(&bomb).err(), Some(-2));
}

#[test]
fn input_over_the_encoded_cap_is_too_large() {
    let big = vec![b' '; 4 * 1024 * 1024 + 1];
    assert_eq!(try_load(&big).err(), Some(-2));
}

#[test]
fn unusable_bytes_are_malformed_or_unsupported_never_a_panic() {
    let zipped = gzip(fixture().as_bytes());
    let cases: Vec<(&str, Vec<u8>)> = vec![
        ("garbage", vec![0xde, 0xad, 0xbe, 0xef, 0x00, 0x42]),
        ("empty", vec![]),
        ("truncated json", fixture().as_bytes()[..80].to_vec()),
        ("truncated gzip", zipped[..zipped.len() / 2].to_vec()),
        ("gzip magic only", vec![0x1f, 0x8b]),
        ("empty object", b"{}".to_vec()),
    ];
    for (name, bytes) in cases {
        let status = try_load(&bytes).err();
        assert!(matches!(status, Some(-3) | Some(-5)), "{name}: {status:?}");
    }
}

#[test]
fn deeply_nested_file_is_limit_or_malformed() {
    let deep = format!("{}{}", "[".repeat(100_000), "]".repeat(100_000));
    let status = try_load(deep.as_bytes()).err();
    assert!(matches!(status, Some(-4) | Some(-3)), "{status:?}");
}

#[test]
fn no_pixels_is_unsupported() {
    let flat = fixture().replace(r#""w":100"#, r#""w":0"#);
    let status = try_load(flat.as_bytes()).err();
    assert!(
        matches!(status, Some(-5) | Some(-3) | Some(-4)),
        "{status:?}"
    );
}

#[test]
fn null_arguments_are_invalid() {
    use chat_lottie::chat_lottie_load;
    let json = fixture();
    let mut info = chat_lottie::ChatLottieInfo::default();
    let mut handle = std::ptr::null_mut();
    unsafe {
        let p = json.as_ptr();
        assert_eq!(
            chat_lottie_load(std::ptr::null(), 4, &mut info, &mut handle),
            -1
        );
        assert_eq!(
            chat_lottie_load(p, json.len(), std::ptr::null_mut(), &mut handle),
            -1
        );
        assert_eq!(
            chat_lottie_load(p, json.len(), &mut info, std::ptr::null_mut()),
            -1
        );
    }
}

#[test]
fn free_accepts_null() {
    unsafe { chat_lottie::chat_lottie_free(std::ptr::null_mut()) };
}
