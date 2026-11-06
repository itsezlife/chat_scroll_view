//! Long, seeded fuzz of the C ABI. Slice 11 of the native media plan.
//!
//! The corpus replay (`replay.rs`) runs on every pull request and is fixed;
//! this one runs for as long as `CHAT_LOTTIE_FUZZ_SECONDS` says, nightly, and
//! is `#[ignore]` so a plain `cargo test` never waits for it:
//!
//!     cargo test --release --test fuzz_long -- --ignored --nocapture
//!
//! The guarantee under test is the one the header makes: whatever the bytes,
//! the library answers with a documented status, never `-6` (a panic caught at
//! the boundary is a bug, not the file's fault), never hangs, and leaves the
//! out handle null on failure.
mod common;

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::mpsc;
use std::time::{Duration, Instant};

// ---------------------------------------------------------------------------
// Observations and verdicts
// ---------------------------------------------------------------------------

/// One ABI call and the status it returned.
#[derive(Debug, Clone, PartialEq)]
struct Call {
    name: &'static str,
    status: i32,
}

/// What a driver saw while pushing one input through the ABI. The driver
/// records; `judge` decides, so a fake driver can plant a defect.
#[derive(Debug, Default)]
struct Trace {
    calls: Vec<Call>,
    /// Violations only the driver can see (a non-null handle after a failed
    /// load, a pixel brighter than its alpha, bytes written outside a slot).
    anomalies: Vec<String>,
}

#[derive(Debug, PartialEq)]
enum Finding {
    /// `-6`: a panic inside tlottie or the wrapper.
    Internal(Call),
    /// A status the header does not document for that call.
    Undocumented(Call),
    /// A violation the driver reported.
    Anomaly(String),
    /// The input did not finish within the limit.
    Hang,
    /// The driver itself panicked, which also means a call panicked across
    /// the boundary, or a harness assertion failed.
    DriverPanicked(String),
}

type Driver = fn(&[u8]) -> Trace;

/// Statuses the header documents per call; `-6` is deliberately in none.
fn documented(name: &str) -> &'static [i32] {
    match name {
        "load" => &[0, -1, -2, -3, -4, -5],
        "render" => &[0, -1, -7, -8],
        "compress" => &[0, -1, -2, -7],
        "decompress" => &[0, -1, -3, -7],
        _ => &[],
    }
}

/// Anomalies first (they name the cause), then the first bad status.
fn judge(trace: &Trace) -> Option<Finding> {
    if let Some(anomaly) = trace.anomalies.first() {
        return Some(Finding::Anomaly(anomaly.clone()));
    }
    for call in &trace.calls {
        if call.status == -6 {
            return Some(Finding::Internal(call.clone()));
        }
        if !documented(call.name).contains(&call.status) {
            return Some(Finding::Undocumented(call.clone()));
        }
    }
    None
}

/// Runs `driver` over `input` on a worker thread with a deadline. A hung
/// worker is abandoned (it cannot be killed); the caller stops after a hang.
fn run_case(driver: Driver, input: &[u8], limit: Duration) -> Result<Trace, Finding> {
    let (done, finished) = mpsc::channel();
    let owned = input.to_vec();
    std::thread::spawn(move || {
        let outcome = catch_unwind(AssertUnwindSafe(|| driver(&owned)));
        // The receiver is gone after a timeout; a late answer is dropped.
        let _ = done.send(outcome);
    });
    match finished.recv_timeout(limit) {
        Ok(Ok(trace)) => match judge(&trace) {
            Some(finding) => Err(finding),
            None => Ok(trace),
        },
        Ok(Err(payload)) => Err(Finding::DriverPanicked(panic_message(payload.as_ref()))),
        Err(_) => Err(Finding::Hang),
    }
}

fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    payload
        .downcast_ref::<&str>()
        .map(|s| (*s).to_owned())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "non-string panic payload".into())
}

// ---------------------------------------------------------------------------
// The harness detects what it exists to detect
// ---------------------------------------------------------------------------

fn clean(_: &[u8]) -> Trace {
    Trace {
        calls: vec![Call {
            name: "load",
            status: -3,
        }],
        anomalies: vec![],
    }
}

fn answers_internal(_: &[u8]) -> Trace {
    Trace {
        calls: vec![
            Call {
                name: "load",
                status: 0,
            },
            Call {
                name: "render",
                status: -6,
            },
        ],
        anomalies: vec![],
    }
}

fn answers_undocumented(_: &[u8]) -> Trace {
    Trace {
        calls: vec![Call {
            name: "load",
            status: -7,
        }],
        anomalies: vec![],
    }
}

fn reports_anomaly(_: &[u8]) -> Trace {
    Trace {
        calls: vec![],
        anomalies: vec!["handle not null after failure".into()],
    }
}

fn hangs(_: &[u8]) -> Trace {
    std::thread::sleep(Duration::from_secs(3));
    Trace::default()
}

fn panics(_: &[u8]) -> Trace {
    panic!("planted")
}

const LIMIT: Duration = Duration::from_millis(150);

#[test]
fn a_clean_trace_passes() {
    assert!(run_case(clean, b"", LIMIT).is_ok());
}

#[test]
fn a_caught_panic_status_is_a_finding() {
    let found = run_case(answers_internal, b"", LIMIT).unwrap_err();
    assert_eq!(
        found,
        Finding::Internal(Call {
            name: "render",
            status: -6
        })
    );
}

#[test]
fn a_status_the_header_does_not_document_is_a_finding() {
    let found = run_case(answers_undocumented, b"", LIMIT).unwrap_err();
    assert_eq!(
        found,
        Finding::Undocumented(Call {
            name: "load",
            status: -7
        })
    );
}

#[test]
fn a_driver_anomaly_is_a_finding() {
    let found = run_case(reports_anomaly, b"", LIMIT).unwrap_err();
    assert!(matches!(found, Finding::Anomaly(_)), "{found:?}");
}

#[test]
fn a_hang_is_a_finding_and_does_not_wait_for_the_hung_call() {
    let started = Instant::now();
    let found = run_case(hangs, b"", LIMIT).unwrap_err();
    assert_eq!(found, Finding::Hang);
    assert!(
        started.elapsed() < Duration::from_secs(2),
        "waited for the hang"
    );
}

#[test]
fn a_panicking_driver_is_a_finding() {
    let found = run_case(panics, b"", LIMIT).unwrap_err();
    assert!(matches!(found, Finding::DriverPanicked(_)), "{found:?}");
}

// ---------------------------------------------------------------------------
// The generator
// ---------------------------------------------------------------------------

type Json = serde_json::Value;

/// xorshift64* behind a splitmix64 seed scramble: a small PRNG of our own, so
/// a seed replays the same cases on any machine and no crate is added.
struct Rng(u64);

impl Rng {
    fn new(seed: u64) -> Self {
        let mut z = seed.wrapping_add(0x9E37_79B9_7F4A_7C15);
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        Rng((z ^ (z >> 31)) | 1)
    }

    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// Uniform enough in `0..n`; `n` must be positive.
    fn below(&mut self, n: usize) -> usize {
        (self.next() >> 11) as usize % n
    }

    fn chance(&mut self, one_in: usize) -> bool {
        self.below(one_in) == 0
    }

    fn pick<'a, T>(&mut self, items: &'a [T]) -> &'a T {
        &items[self.below(items.len())]
    }
}

/// One generated input and the recipe that made it, for the failure report.
struct Case {
    recipe: String,
    bytes: Vec<u8>,
}

const PRECOMP_LAYER: &str = r#""ty":0,"refId":"a","w":100,"h":100,"ks":{},"ip":0,"op":60,"st":0"#;

/// Hand-authored seeds: the fixture and a few shapes that reach different
/// tlottie paths (features it skips, a precomp, a precomp that includes
/// itself, masks and mattes). Mutations start from these, not from nothing.
fn base_documents() -> Vec<String> {
    use common::{fixture, fixture_with};
    let features = fixture_with(
        r#","ef":[{"ty":5,"nm":"Blur","en":1,"ef":[]}]"#,
        r#","x":"time * 20""#,
        r#",{"ddd":0,"ind":2,"ty":5,"nm":"t","ks":{},"ip":0,"op":60,"st":0,"t":{}}"#,
        r#"{"id":"img_0","w":4,"h":4,"u":"","p":"data:image/png;base64,AAAA","e":1}"#,
    );
    let outer = format!(r#",{{"ddd":0,"ind":2,{PRECOMP_LAYER}}}"#);
    let inner = format!(r#"{{"ddd":0,"ind":1,{PRECOMP_LAYER}}}"#);
    let precomp = fixture_with("", "", &outer, r#"{"id":"a","layers":[]}"#);
    let self_including = fixture_with(
        "",
        "",
        &outer,
        &format!(r#"{{"id":"a","layers":[{inner}]}}"#),
    );
    let mask = fixture_with(
        r#","hasMask":true,"masksProperties":[{"inv":false,"mode":"a","pt":{"a":0,"k":{"i":[[0,0],[0,0],[0,0]],"o":[[0,0],[0,0],[0,0]],"v":[[0,0],[100,0],[50,100]],"c":true}},"o":{"a":0,"k":100},"x":{"a":0,"k":0}}]"#,
        "",
        r#",{"ddd":0,"ind":2,"ty":4,"nm":"m","tt":1,"ks":{},"shapes":[],"ip":0,"op":60,"st":0}"#,
        "",
    );
    vec![fixture(), features, precomp, self_including, mask]
}

/// Values a field is replaced with: the edges of every numeric type the JSON
/// reaches, and each other JSON type.
fn interesting_values() -> Vec<Json> {
    use serde_json::json;
    let mut out: Vec<Json> = [
        0.0,
        -1.0,
        1.0,
        0.5,
        255.0,
        65_535.0,
        65_536.0,
        2_147_483_647.0,
        2_147_483_648.0,
        4_294_967_295.0,
        4_294_967_296.0,
        1e9,
        1e18,
        1e38,
        1e308,
        -1e308,
        1e-45,
        1e-320,
    ]
    .iter()
    .map(|n| json!(n))
    .collect();
    out.extend([
        json!(null),
        json!(true),
        json!(""),
        json!("x"),
        json!([]),
        json!({}),
        json!([0]),
        json!([[[[[[[[0]]]]]]]]),
        json!({"k": {"k": {"k": 0}}}),
    ]);
    out
}

/// Keys the Lottie schema (and tlottie) look at, for rename and insert edits.
const KEYS: [&str; 24] = [
    "ty", "ks", "shapes", "layers", "assets", "it", "refId", "parent", "tm", "ef", "tt", "td", "w",
    "h", "fr", "ip", "op", "st", "sr", "k", "a", "s", "e", "o",
];

/// Top-level scalars worth hitting on purpose: a random node rarely is one.
const ROOT_SCALARS: [&str; 6] = ["w", "h", "fr", "ip", "op", "ddd"];

fn node_count(value: &Json) -> usize {
    1 + match value {
        Json::Array(items) => items.iter().map(node_count).sum(),
        Json::Object(map) => map.values().map(node_count).sum(),
        _ => 0,
    }
}

/// The `n`th node in pre-order, `n` below `node_count`.
fn nth_node(value: &mut Json, mut n: usize) -> &mut Json {
    if n == 0 {
        return value;
    }
    n -= 1;
    let children: Vec<&mut Json> = match value {
        Json::Array(items) => items.iter_mut().collect(),
        Json::Object(map) => map.values_mut().collect(),
        _ => Vec::new(),
    };
    for child in children {
        let size = node_count(child);
        if n < size {
            return nth_node(child, n);
        }
        n -= size;
    }
    unreachable!("n was below node_count")
}

fn some_key(map: &serde_json::Map<String, Json>, rng: &mut Rng) -> String {
    map.keys()
        .nth(rng.below(map.len()))
        .cloned()
        .unwrap_or_default()
}

/// One structure-aware edit of a parsed document; returns what it did.
fn edit_structure(root: &mut Json, rng: &mut Rng) -> String {
    use serde_json::json;
    let values = interesting_values();
    if rng.chance(4) {
        let key = *rng.pick(&ROOT_SCALARS);
        let value = rng.pick(&values).clone();
        if let Some(map) = root.as_object_mut() {
            map.insert(key.into(), value.clone());
        }
        return format!("root {key} = {value}");
    }
    let at = rng.below(node_count(root));
    let node = nth_node(root, at);
    match node {
        Json::Object(map) if !map.is_empty() => match rng.below(4) {
            0 => {
                let key = some_key(map, rng);
                map.remove(&key);
                format!("delete key {key}")
            }
            1 => {
                let from = some_key(map, rng);
                let to = (*rng.pick(&KEYS)).to_owned();
                if let Some(value) = map.remove(&from) {
                    map.insert(to.clone(), value);
                }
                format!("rename {from} to {to}")
            }
            2 => {
                let key = (*rng.pick(&KEYS)).to_owned();
                map.insert(key.clone(), rng.pick(&values).clone());
                format!("insert key {key}")
            }
            _ => {
                let key = some_key(map, rng);
                map.insert(key.clone(), rng.pick(&values).clone());
                format!("replace value at {key}")
            }
        },
        Json::Array(items) if !items.is_empty() => match rng.below(4) {
            0 => {
                let at = rng.below(items.len());
                let copies = 1 + rng.below(40);
                let item = items[at].clone();
                items.extend(std::iter::repeat_n(item, copies));
                format!("duplicate element {at} x{copies}")
            }
            1 => {
                items.remove(rng.below(items.len()));
                "remove element".into()
            }
            2 => {
                // Nest: the array becomes the only member of a deeper one.
                let depth = 1 + rng.below(60);
                let mut wrapped = Json::Array(std::mem::take(items));
                for _ in 0..depth {
                    wrapped = json!([wrapped]);
                }
                *node = wrapped;
                format!("nest array {depth} deep")
            }
            _ => {
                let at = rng.below(items.len());
                items[at] = rng.pick(&values).clone();
                format!("replace element {at}")
            }
        },
        Json::Number(number) => {
            let v = number.as_f64().unwrap_or(0.0);
            match rng.below(3) {
                0 => {
                    *node = json!(-v);
                    "negate number".into()
                }
                1 => {
                    *node = json!(v * 1000.0 + 1.0);
                    "scale number".into()
                }
                _ => {
                    *node = rng.pick(&values).clone();
                    "replace number".into()
                }
            }
        }
        other => {
            *other = rng.pick(&values).clone();
            "replace scalar".into()
        }
    }
}

const TOKENS: [&[u8]; 10] = [
    b"-1",
    b"1e999",
    b"null",
    b"[",
    b"{",
    b"\"",
    b"\\u0000",
    b"9999999999999",
    b"\\ud800",
    b",",
];

/// One raw edit of the bytes (JSON or gzip alike); returns what it did.
fn edit_bytes(bytes: &mut Vec<u8>, rng: &mut Rng) -> String {
    if bytes.is_empty() {
        bytes.push(rng.next() as u8);
        return "grow empty".into();
    }
    match rng.below(5) {
        0 => {
            let flips = 1 + rng.below(8);
            for _ in 0..flips {
                let at = rng.below(bytes.len());
                bytes[at] ^= 1 << rng.below(8);
            }
            format!("flip {flips} bits")
        }
        1 => {
            let to = rng.below(bytes.len());
            bytes.truncate(to);
            format!("truncate to {to}")
        }
        2 => {
            let at = rng.below(bytes.len() + 1);
            let token = rng.pick(&TOKENS);
            bytes.splice(at..at, token.iter().copied());
            format!("insert token at {at}")
        }
        3 => {
            let from = rng.below(bytes.len());
            let len = 1 + rng.below((bytes.len() - from).min(64));
            let copy = bytes[from..from + len].to_vec();
            let at = rng.below(bytes.len() + 1);
            bytes.splice(at..at, copy);
            format!("copy {len} bytes to {at}")
        }
        _ => {
            let from = rng.below(bytes.len());
            let len = 1 + rng.below((bytes.len() - from).min(64));
            bytes.drain(from..from + len);
            format!("delete {len} bytes at {from}")
        }
    }
}

/// A gzip header, trailer or member corruption; returns what it did. `bytes`
/// is a well-formed gzip of some document, so longer than its 18 bytes of
/// framing.
fn corrupt_gzip(bytes: &mut Vec<u8>, rng: &mut Rng) -> String {
    let len = bytes.len();
    match rng.below(8) {
        0 => {
            let at = rng.below(10);
            bytes[at] = rng.next() as u8;
            format!("header byte {at}")
        }
        1 => {
            bytes[3] |= 0x04; // FEXTRA with a length the body cannot honour
            let claimed = (rng.next() & 0xFFFF) as u16;
            bytes.splice(10..10, claimed.to_le_bytes());
            format!("FEXTRA claiming {claimed}")
        }
        2 => {
            bytes[3] |= 0x08; // FNAME that is never terminated
            "FNAME flag, no terminator".into()
        }
        3 => {
            bytes[3] |= 0x10 | 0x02; // FCOMMENT and FHCRC, neither present
            "FCOMMENT and FHCRC flags".into()
        }
        4 => {
            let cut = 1 + rng.below(8);
            bytes.truncate(len - cut);
            format!("trailer cut by {cut}")
        }
        5 => {
            let at = len - 1 - rng.below(8);
            bytes[at] ^= 0xFF;
            format!("trailer byte {at} inverted (CRC or ISIZE)")
        }
        6 => {
            let extra = 1 + rng.below(32);
            bytes.extend((0..extra).map(|_| rng.next() as u8));
            format!("{extra} trailing garbage bytes")
        }
        _ => {
            let second = bytes.clone();
            bytes.extend(second);
            "two members".into()
        }
    }
}

struct Generator {
    rng: Rng,
    bases: Vec<Json>,
}

impl Generator {
    fn new(seed: u64) -> Self {
        let bases = base_documents()
            .iter()
            .map(|doc| serde_json::from_str(doc).expect("a base document is JSON"))
            .collect();
        Generator {
            rng: Rng::new(seed),
            bases,
        }
    }

    fn next_case(&mut self) -> Case {
        let rng = &mut self.rng;
        // Rare, large and slow: the size caps (4 MiB encoded, 8 MiB inflated).
        if rng.chance(700) {
            return size_bomb(rng);
        }
        let mut recipe = Vec::new();
        let mut doc = rng.pick(&self.bases).clone();
        for _ in 0..1 + rng.below(3) {
            recipe.push(edit_structure(&mut doc, rng));
        }
        let mut bytes = serde_json::to_vec(&doc).unwrap_or_default();
        if rng.chance(3) {
            for _ in 0..1 + rng.below(3) {
                recipe.push(edit_bytes(&mut bytes, rng));
            }
        }
        if rng.chance(3) {
            bytes = common::gzip(&bytes);
            recipe.push("gzip".into());
            if rng.chance(2) && bytes.len() > 18 {
                recipe.push(corrupt_gzip(&mut bytes, rng));
            }
            if rng.chance(6) {
                recipe.push(edit_bytes(&mut bytes, rng));
            }
        }
        Case {
            recipe: recipe.join("; "),
            bytes,
        }
    }
}

/// A gzip that inflates past the cap from a few KiB, or raw bytes past the
/// encoded cap.
fn size_bomb(rng: &mut Rng) -> Case {
    if rng.chance(2) {
        let inflated = 7 * 1024 * 1024 + rng.below(6 * 1024 * 1024);
        Case {
            recipe: format!("zero bomb inflating to {inflated}"),
            bytes: common::gzip(&vec![0u8; inflated]),
        }
    } else {
        let len = 4 * 1024 * 1024 + rng.below(1024 * 1024);
        Case {
            recipe: format!("{len} raw bytes"),
            bytes: vec![b' '; len],
        }
    }
}

// ---------------------------------------------------------------------------
// The real driver
// ---------------------------------------------------------------------------

const GUARD: u8 = 0xAB;
const GUARD_TAIL: usize = 16;

/// A pixel region with row padding and a guarded tail, so a write outside
/// the described bytes shows up as a changed guard.
struct Region {
    buf: Vec<u8>,
    width: u32,
    height: u32,
    stride: usize,
}

impl Region {
    fn new(width: u32, height: u32, pad: usize) -> Self {
        let stride = width as usize * 4 + pad;
        let extent = (height as usize - 1) * stride + width as usize * 4;
        Region {
            buf: vec![GUARD; extent + GUARD_TAIL],
            width,
            height,
            stride,
        }
    }

    fn row(&self, y: usize) -> &[u8] {
        &self.buf[y * self.stride..][..self.width as usize * 4]
    }

    /// Every byte that is not a pixel (row padding and the tail) is still
    /// the guard.
    fn outside_is_intact(&self) -> bool {
        let row_bytes = self.width as usize * 4;
        let rows_ok = (0..self.height as usize - 1).all(|y| {
            self.buf[y * self.stride + row_bytes..(y + 1) * self.stride]
                .iter()
                .all(|&b| b == GUARD)
        });
        let extent = self.buf.len() - GUARD_TAIL;
        rows_ok && self.buf[extent..].iter().all(|&b| b == GUARD)
    }

    fn is_untouched(&self) -> bool {
        self.buf.iter().all(|&b| b == GUARD)
    }

    fn pixels(&self) -> Vec<u8> {
        (0..self.height as usize)
            .flat_map(|y| self.row(y).iter().copied())
            .collect()
    }

    /// Premultiplied means no colour channel is above its alpha.
    fn is_premultiplied(&self) -> bool {
        (0..self.height as usize).all(|y| {
            self.row(y)
                .as_chunks::<4>()
                .0
                .iter()
                .all(|p| p[0] <= p[3] && p[1] <= p[3] && p[2] <= p[3])
        })
    }
}

fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325, |hash, &b| {
        (hash ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
    })
}

impl Trace {
    fn call(&mut self, name: &'static str, status: i32) -> i32 {
        self.calls.push(Call { name, status });
        status
    }

    fn anomaly(&mut self, what: impl Into<String>) {
        self.anomalies.push(what.into());
    }
}

/// Pushes one input through load, render, the codec and free, recording what
/// each call said. Everything it asserts is a contract of the header; which
/// status an input earns is not asserted, only that it is a documented one.
fn drive_abi(input: &[u8]) -> Trace {
    use chat_lottie::{chat_lottie_free, chat_lottie_load, ChatLottie, ChatLottieInfo};
    let mut trace = Trace::default();
    let mut rng = Rng::new(fnv1a(input));
    let mut info = ChatLottieInfo::default();
    // Poisoned, so a failure path that forgets to null the handle shows.
    let mut handle: *mut ChatLottie = std::ptr::NonNull::dangling().as_ptr();
    let status = trace.call("load", unsafe {
        chat_lottie_load(input.as_ptr(), input.len(), &mut info, &mut handle)
    });
    if status == 0 {
        if handle.is_null() {
            trace.anomaly("load returned 0 with a null handle");
        } else {
            let rendered = render_stage(handle, &info, &mut rng, &mut trace);
            if let Some(region) = rendered {
                codec_round_trip(&region, &mut rng, &mut trace);
            }
            unsafe { chat_lottie_free(handle) };
        }
    } else if !handle.is_null() {
        trace.anomaly(format!(
            "load failed with {status} but left a non-null handle"
        ));
    }
    codec_on_raw_stream(input, &mut trace);
    trace
}

/// Renders a batch of good, hostile-frame and bad-size jobs at several sizes.
/// Returns the first region that rendered, as codec input.
fn render_stage(
    handle: *mut chat_lottie::ChatLottie,
    info: &chat_lottie::ChatLottieInfo,
    rng: &mut Rng,
    trace: &mut Trace,
) -> Option<Region> {
    use chat_lottie::{chat_lottie_render_batch, ChatLottieJob};
    let last = info.frame_count.saturating_sub(1) as f32;
    let frames = [
        0.0,
        last / 2.0,
        last,
        info.frame_count as f32,
        -1.0,
        f32::NAN,
        f32::INFINITY,
        1e9,
    ];
    // (width, height, row padding in bytes)
    let mut sizes = vec![(1, 1, 0), (17, 23, 12), (64, 64, 0), (128, 96, 32)];
    if rng.chance(16) {
        sizes.push((512, 512, 0));
    }
    let mut regions: Vec<Region> = sizes
        .iter()
        .map(|&(w, h, pad)| Region::new(w, h, pad))
        .collect();
    let mut jobs: Vec<ChatLottieJob> = regions
        .iter_mut()
        .map(|region| ChatLottieJob {
            handle,
            frame: *rng.pick(&frames),
            width: region.width,
            height: region.height,
            target: region.buf.as_mut_ptr(),
            stride_bytes: region.stride,
        })
        .collect();
    // Bad jobs ride in the same batch: they must fail alone.
    let mut scratch = [GUARD; 64];
    let bad = |handle, width, height, target: *mut u8| ChatLottieJob {
        handle,
        frame: 0.0,
        width,
        height,
        target,
        stride_bytes: 64 * 4,
    };
    jobs.push(bad(handle, 0, 8, scratch.as_mut_ptr()));
    jobs.push(bad(handle, 513, 8, scratch.as_mut_ptr()));
    jobs.push(bad(std::ptr::null_mut(), 8, 8, scratch.as_mut_ptr()));
    let mut statuses = vec![99i32; jobs.len()];
    let ran = unsafe { chat_lottie_render_batch(jobs.as_ptr(), jobs.len(), statuses.as_mut_ptr()) };
    if trace.call("render", ran) != 0 {
        return None;
    }
    let good = regions.len();
    for (i, &status) in statuses.iter().enumerate() {
        trace.call("render", status);
        if i >= good {
            let expected = if i == good + 2 { -1 } else { -7 };
            if status != expected {
                trace.anomaly(format!(
                    "bad job {} answered {status}, not {expected}",
                    i - good
                ));
            }
        }
    }
    if scratch.iter().any(|&b| b != GUARD) {
        trace.anomaly("a rejected job wrote to its target");
    }
    let mut first = None;
    for (region, &status) in regions.into_iter().zip(&statuses) {
        if status != 0 {
            continue;
        }
        if !region.outside_is_intact() {
            trace.anomaly(format!(
                "{}x{} render wrote outside its slot",
                region.width, region.height
            ));
        }
        if !region.is_premultiplied() {
            trace.anomaly(format!(
                "{}x{} render is not premultiplied",
                region.width, region.height
            ));
        }
        first.get_or_insert(region);
    }
    first
}

/// Compresses a rendered region and decompresses it again, then feeds the
/// codec a corrupt stream, a short destination and a wrong-size region.
fn codec_round_trip(region: &Region, rng: &mut Rng, trace: &mut Trace) {
    use chat_lottie::{
        chat_lottie_compress_region, chat_lottie_decompress_region, chat_lottie_lz4_bound,
    };
    let (w, h) = (region.width, region.height);
    let bound = chat_lottie_lz4_bound(w, h);
    if bound == 0 {
        trace.anomaly(format!("lz4_bound is 0 for {w}x{h}"));
        return;
    }
    let mut packed = vec![GUARD; bound];
    let mut len = 0usize;
    let status = trace.call("compress", unsafe {
        chat_lottie_compress_region(
            region.buf.as_ptr(),
            region.stride,
            w,
            h,
            packed.as_mut_ptr(),
            bound,
            &mut len,
        )
    });
    if status != 0 || len > bound {
        trace.anomaly(format!(
            "compress with the bound as capacity answered {status}, len {len}"
        ));
        return;
    }
    if len > 1 {
        let mut short_len = 7usize;
        let short = trace.call("compress", unsafe {
            chat_lottie_compress_region(
                region.buf.as_ptr(),
                region.stride,
                w,
                h,
                packed.as_mut_ptr(),
                len - 1,
                &mut short_len,
            )
        });
        if short != -2 || short_len != 7 {
            trace.anomaly(format!(
                "a one byte short destination answered {short}, len {short_len}"
            ));
        }
    }
    let stream = packed[..len].to_vec();

    let mut back = Region::new(w, h, 8);
    let status = trace.call("decompress", unsafe {
        chat_lottie_decompress_region(
            stream.as_ptr(),
            stream.len(),
            back.buf.as_mut_ptr(),
            back.stride,
            w,
            h,
        )
    });
    if status != 0 || back.pixels() != region.pixels() || !back.outside_is_intact() {
        trace.anomaly(format!(
            "round trip of {w}x{h} lost pixels or wrote outside (status {status})"
        ));
    }

    // A stream with a flipped byte or a missing tail: rejected, or accepted
    // as some other picture; a rejection leaves the region alone.
    let mut hurt = stream.clone();
    let at = rng.below(hurt.len());
    if rng.chance(2) {
        hurt[at] ^= 1 << rng.below(8);
    } else {
        hurt.truncate(at);
    }
    let mut target = Region::new(w, h, 0);
    let status = trace.call("decompress", unsafe {
        chat_lottie_decompress_region(
            hurt.as_ptr(),
            hurt.len(),
            target.buf.as_mut_ptr(),
            target.stride,
            w,
            h,
        )
    });
    if status != 0 && !target.is_untouched() {
        trace.anomaly(format!("a rejected stream ({status}) changed the region"));
    }
    if !target.outside_is_intact() {
        trace.anomaly("a corrupt stream wrote outside the region");
    }

    // The right stream for the wrong region size can never unpack exactly.
    let mut wrong = Region::new(w + 1, h, 0);
    let status = trace.call("decompress", unsafe {
        chat_lottie_decompress_region(
            stream.as_ptr(),
            stream.len(),
            wrong.buf.as_mut_ptr(),
            wrong.stride,
            w + 1,
            h,
        )
    });
    if status != -3 || !wrong.is_untouched() {
        trace.anomaly(format!("a wrong-size region answered {status}, not -3"));
    }
}

/// The input itself as an lz4 stream, whatever it was meant to be: the codec
/// is reachable without a successful load.
fn codec_on_raw_stream(input: &[u8], trace: &mut Trace) {
    use chat_lottie::chat_lottie_decompress_region;
    let mut region = Region::new(16, 16, 0);
    let status = trace.call("decompress", unsafe {
        chat_lottie_decompress_region(
            input.as_ptr(),
            input.len(),
            region.buf.as_mut_ptr(),
            region.stride,
            16,
            16,
        )
    });
    if status != 0 && !region.is_untouched() {
        trace.anomaly(format!(
            "a rejected raw stream ({status}) changed the region"
        ));
    }
}

// ---------------------------------------------------------------------------
// The run
// ---------------------------------------------------------------------------

use std::collections::BTreeMap;
use std::path::PathBuf;

struct Config {
    duration: Duration,
    seed: u64,
    dir: PathBuf,
    case_limit: Duration,
    max_findings: usize,
}

#[derive(Default)]
struct Report {
    cases: usize,
    findings: Vec<(Finding, PathBuf)>,
    /// How often `load` answered each status: the spread says whether the
    /// generator reaches the render path at all.
    load_statuses: BTreeMap<i32, usize>,
    slowest: Duration,
}

/// Writes the failing input and its recipe where the nightly job uploads
/// them; the name carries everything needed to regenerate the case.
fn save_finding(config: &Config, index: usize, case: &Case, finding: &Finding) -> PathBuf {
    let kind = match finding {
        Finding::Internal(_) => "internal",
        Finding::Undocumented(_) => "undocumented",
        Finding::Anomaly(_) => "anomaly",
        Finding::Hang => "hang",
        Finding::DriverPanicked(_) => "panicked",
    };
    let stem = format!("seed{}-case{index}-{kind}", config.seed);
    let path = config.dir.join(format!("{stem}.bin"));
    let note = format!("{finding:?}\nrecipe: {}\n", case.recipe);
    // A failed save must not hide the finding itself: report and go on.
    if let Err(error) = std::fs::write(&path, &case.bytes)
        .and_then(|()| std::fs::write(config.dir.join(format!("{stem}.txt")), note))
    {
        eprintln!("could not save {stem}: {error}");
    }
    path
}

fn fuzz_run(driver: Driver, config: &Config) -> Report {
    let mut report = Report::default();
    if let Err(error) = std::fs::create_dir_all(&config.dir) {
        eprintln!("could not create {:?}: {error}", config.dir);
    }
    // The input about to run is on disk first: a stack overflow or abort
    // kills the process before any verdict, and this file is then the
    // reproduction. A finished case replaces it; a clean run removes it.
    let inflight = config.dir.join(format!("inflight-seed{}.bin", config.seed));
    let mut generator = Generator::new(config.seed);
    let started = Instant::now();
    while started.elapsed() < config.duration && report.findings.len() < config.max_findings {
        let case = generator.next_case();
        let index = report.cases;
        report.cases += 1;
        let _ = std::fs::write(&inflight, &case.bytes);
        let case_started = Instant::now();
        let outcome = run_case(driver, &case.bytes, config.case_limit);
        report.slowest = report
            .slowest
            .max(case_started.elapsed().min(config.case_limit));
        match outcome {
            Ok(trace) => {
                if let Some(load) = trace.calls.iter().find(|c| c.name == "load") {
                    *report.load_statuses.entry(load.status).or_default() += 1;
                }
            }
            Err(finding) => {
                let hung = finding == Finding::Hang;
                let path = save_finding(config, index, &case, &finding);
                eprintln!(
                    "FINDING case {index}: {finding:?} ({}) saved to {path:?}",
                    case.recipe
                );
                report.findings.push((finding, path));
                // The abandoned worker still runs; more cases would pile
                // threads on a stuck library.
                if hung {
                    break;
                }
            }
        }
    }
    let _ = std::fs::remove_file(&inflight);
    report
}

impl Config {
    /// `CHAT_LOTTIE_FUZZ_SECONDS` (20), `CHAT_LOTTIE_FUZZ_SEED` (the clock),
    /// `CHAT_LOTTIE_FUZZ_DIR` (`target/fuzz-failures`) and
    /// `CHAT_LOTTIE_FUZZ_CASE_MS` (5000, the per-input time limit).
    fn from_env() -> Self {
        fn var<T: std::str::FromStr>(name: &str) -> Option<T> {
            std::env::var(name).ok().and_then(|v| v.trim().parse().ok())
        }
        let clock_seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(1, |d| d.as_nanos() as u64);
        Config {
            duration: Duration::from_secs_f64(var("CHAT_LOTTIE_FUZZ_SECONDS").unwrap_or(20.0)),
            seed: var("CHAT_LOTTIE_FUZZ_SEED").unwrap_or(clock_seed),
            dir: std::env::var_os("CHAT_LOTTIE_FUZZ_DIR")
                .map_or_else(|| PathBuf::from("target/fuzz-failures"), PathBuf::from),
            case_limit: Duration::from_millis(var("CHAT_LOTTIE_FUZZ_CASE_MS").unwrap_or(5000)),
            max_findings: 10,
        }
    }
}

/// The long run. Ignored: `cargo test --release --test fuzz_long -- --ignored --nocapture`.
#[test]
#[ignore = "runs for CHAT_LOTTIE_FUZZ_SECONDS; the nightly job and `-- --ignored` run it"]
fn long_fuzz_of_the_c_abi() {
    let config = Config::from_env();
    // First, so a failure anywhere below can be reproduced.
    println!("CHAT_LOTTIE_FUZZ_SEED={}", config.seed);
    let report = fuzz_run(drive_abi, &config);
    println!(
        "cases={} findings={} slowest_ms={} load_statuses={:?}",
        report.cases,
        report.findings.len(),
        report.slowest.as_millis(),
        report.load_statuses
    );
    assert!(
        report.findings.is_empty(),
        "{} finding(s), seed {}; inputs in {:?}: {:?}",
        report.findings.len(),
        config.seed,
        config.dir,
        report.findings
    );
}

#[cfg(test)]
mod generator_and_driver {
    use super::*;
    use common::{fixture, gzip};

    fn cases(seed: u64, n: usize) -> Vec<Vec<u8>> {
        let mut generator = Generator::new(seed);
        (0..n).map(|_| generator.next_case().bytes).collect()
    }

    #[test]
    fn one_seed_makes_the_same_cases() {
        assert_eq!(cases(7, 300), cases(7, 300));
        assert_ne!(cases(7, 300), cases(8, 300));
    }

    #[test]
    fn the_mix_covers_json_gzip_and_every_gzip_corruption() {
        let mut generator = Generator::new(1);
        let all: Vec<Case> = (0..3000).map(|_| generator.next_case()).collect();
        let gzipped = all
            .iter()
            .filter(|c| c.bytes.starts_with(&[0x1f, 0x8b]))
            .count();
        let valid_json = all
            .iter()
            .filter(|c| serde_json::from_slice::<serde_json::Value>(&c.bytes).is_ok())
            .count();
        let distinct: std::collections::HashSet<_> = all.iter().map(|c| &c.bytes).collect();
        assert!(gzipped > 300, "gzip variants: {gzipped}");
        assert!(
            valid_json > 300,
            "structure-aware edits stay JSON: {valid_json}"
        );
        assert!(distinct.len() > 2850, "inputs repeat: {}", distinct.len());
        for recipe in [
            "header byte",
            "FEXTRA",
            "FNAME",
            "FCOMMENT",
            "trailer cut",
            "trailer byte",
            "trailing garbage",
            "two members",
            "bomb",
            "flip",
            "truncate",
            "nest array",
            "duplicate element",
            "rename",
            "root w =",
        ] {
            assert!(
                all.iter().any(|c| c.recipe.contains(recipe)),
                "no case made by: {recipe}"
            );
        }
    }

    #[test]
    fn the_unmodified_fixture_passes_every_stage_with_status_zero() {
        for input in [fixture().into_bytes(), gzip(fixture().as_bytes())] {
            let trace = drive_abi(&input);
            assert_eq!(trace.anomalies, Vec::<String>::new());
            let names: Vec<_> = trace.calls.iter().map(|c| c.name).collect();
            for stage in ["load", "render", "compress", "decompress"] {
                assert!(names.contains(&stage), "{stage} never ran: {names:?}");
            }
            // The only expected failures are the planted bad inputs: the
            // undersized destination (-2) and the corrupt streams (-3).
            let ok_load = trace.calls.iter().find(|c| c.name == "load").unwrap();
            assert_eq!(ok_load.status, 0);
        }
    }

    #[test]
    fn garbage_is_rejected_at_load_and_still_exercises_the_codec() {
        let trace = drive_abi(b"not a lottie");
        assert_eq!(trace.anomalies, Vec::<String>::new());
        assert_eq!(
            trace.calls[0],
            Call {
                name: "load",
                status: -3
            }
        );
        assert!(trace.calls.iter().any(|c| c.name == "decompress"));
    }

    fn config(dir: &str, seconds: f64) -> Config {
        Config {
            duration: Duration::from_secs_f64(seconds),
            seed: 42,
            dir: PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(dir),
            case_limit: Duration::from_millis(500),
            max_findings: 3,
        }
    }

    fn internal_on_gzip(input: &[u8]) -> Trace {
        let status = if input.starts_with(&[0x1f, 0x8b]) {
            -6
        } else {
            -3
        };
        Trace {
            calls: vec![Call {
                name: "load",
                status,
            }],
            anomalies: vec![],
        }
    }

    fn hangs_on_gzip(input: &[u8]) -> Trace {
        if input.starts_with(&[0x1f, 0x8b]) {
            std::thread::sleep(Duration::from_secs(5));
        }
        clean(input)
    }

    #[test]
    fn a_planted_panic_status_is_found_and_the_input_saved() {
        let config = config("selftest-internal", 3.0);
        let _ = std::fs::remove_dir_all(&config.dir);
        let report = fuzz_run(internal_on_gzip, &config);

        assert_eq!(
            report.findings.len(),
            config.max_findings,
            "stops at the cap"
        );
        for (finding, path) in &report.findings {
            assert!(matches!(finding, Finding::Internal(_)), "{finding:?}");
            let saved = std::fs::read(path).unwrap();
            assert!(
                saved.starts_with(&[0x1f, 0x8b]),
                "the saved input is the failing one"
            );
            assert!(path.to_string_lossy().contains("seed42"), "{path:?}");
        }
    }

    #[test]
    fn a_planted_hang_is_found_saved_and_ends_the_run() {
        let config = config("selftest-hang", 20.0);
        let _ = std::fs::remove_dir_all(&config.dir);
        let started = Instant::now();
        let report = fuzz_run(hangs_on_gzip, &config);

        assert_eq!(report.findings.len(), 1);
        assert_eq!(report.findings[0].0, Finding::Hang);
        assert!(std::fs::read(&report.findings[0].1)
            .unwrap()
            .starts_with(&[0x1f, 0x8b]));
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "kept fuzzing after a hang"
        );
    }

    #[test]
    fn a_clean_run_counts_cases_and_leaves_no_input_behind() {
        let config = config("selftest-clean", 0.5);
        let _ = std::fs::remove_dir_all(&config.dir);
        let report = fuzz_run(clean, &config);

        assert!(report.cases > 50, "cases: {}", report.cases);
        assert!(report.findings.is_empty());
        assert_eq!(report.load_statuses.get(&-3), Some(&report.cases));
        let left: Vec<_> = std::fs::read_dir(&config.dir)
            .map(|d| d.flatten().collect())
            .unwrap_or_default();
        assert!(left.is_empty(), "left behind: {left:?}");
    }
}
