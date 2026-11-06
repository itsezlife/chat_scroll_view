//! Deterministic replay of hostile inputs through `chat_lottie_load`: the
//! guarantee is about the boundary (no panic, no hang, a documented status,
//! a null handle on failure), not about which status each input earns.
//!
//! The corpus is hand-authored or derived from the hand-authored fixture:
//! prefix truncations, byte mutations, and the TGS (gzip) forms of the same
//! (valid, truncated at several points, a corrupted header, a gzip bomb at the
//! inflated cap and one byte past it). ADR 030 asks for a replay that finishes
//! in under a minute; [`BUDGET`] holds the whole replay to it.
//!
//! The "269 zero bytes" input is a **stand-in**. The policy names a known
//! 269-byte crashing file, but that file is not available to this repository
//! (and a corpus sticker is not redistributable), so the closest honest thing
//! is a 269-byte input of zeros: it exercises the same short-input paths and
//! says nothing about the original's contents.
mod common;
use common::*;
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// The ADR 030 budget for the whole replay.
const BUDGET: Duration = Duration::from_secs(60);

/// The cap on inflated output (`MAX_INFLATED_BYTES` in `input.rs`).
const INFLATED_CAP: usize = 8 * 1024 * 1024;

/// Statuses `chat_lottie_load` documents; -7 and -8 belong to render.
const LOAD_STATUSES: [i32; 6] = [-1, -2, -3, -4, -5, -6];

/// A fixed LCG (Numerical Recipes constants) so a failure replays exactly.
struct Lcg(u32);

impl Lcg {
    fn next(&mut self) -> u32 {
        self.0 = self.0.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        self.0 >> 8
    }
}

fn inputs() -> Vec<(String, Vec<u8>)> {
    let fixture = fixture().into_bytes();
    let mut out = Vec::new();
    for len in (0..fixture.len()).step_by(7) {
        out.push((format!("prefix {len}"), fixture[..len].to_vec()));
    }
    out.push(("269 zero bytes (a stand-in)".into(), vec![0; 269]));
    let mut rng = Lcg(0x5eed);
    for n in 0..100 {
        let mut bytes = fixture.clone();
        let at = rng.next() as usize % bytes.len();
        bytes[at] = rng.next() as u8;
        out.push((format!("mutation {n} at {at}"), bytes));
    }
    out.extend(tgs_inputs(&fixture));
    out
}

/// The gzip (TGS) forms: valid, cut short, with a damaged header or trailer,
/// and bombs at the inflated cap.
fn tgs_inputs(fixture: &[u8]) -> Vec<(String, Vec<u8>)> {
    let zipped = gzip(fixture);
    let mut out = vec![("valid tgs".to_string(), zipped.clone())];
    for len in (0..zipped.len()).step_by(5) {
        out.push((format!("tgs prefix {len}"), zipped[..len].to_vec()));
    }
    // The 10-byte gzip header: magic, method, flags, mtime, xfl, os.
    for at in 0..10 {
        for value in [0x00, 0xff] {
            let mut bytes = zipped.clone();
            bytes[at] = value;
            out.push((format!("tgs header byte {at} = {value:#04x}"), bytes));
        }
    }
    // The trailer is CRC-32 then the length, both little-endian.
    for back in 1..=8 {
        let mut bytes = zipped.clone();
        let at = bytes.len() - back;
        bytes[at] ^= 0xff;
        out.push((format!("tgs trailer byte {back} from the end"), bytes));
    }
    // 8 MiB of spaces is exactly the cap: inflated whole, then not a
    // composition. One byte more is over it and is cut at the cap.
    out.push((
        "tgs bomb exactly at the inflated cap".into(),
        gzip(&vec![b' '; INFLATED_CAP]),
    ));
    out.push((
        "tgs bomb one byte over the inflated cap".into(),
        gzip(&vec![b' '; INFLATED_CAP + 1]),
    ));
    out
}

#[test]
fn hostile_inputs_never_panic_hang_or_leak_a_handle() {
    let started = Instant::now();
    let (done, finished) = mpsc::channel();
    std::thread::spawn(move || {
        for (name, bytes) in inputs() {
            // try_load asserts a null handle on every failure.
            if let Err(status) = try_load(&bytes) {
                assert!(LOAD_STATUSES.contains(&status), "{name}: status {status}");
            }
        }
        let _ = done.send(());
    });
    finished
        .recv_timeout(BUDGET)
        .expect("replay hung or a load panicked across the boundary");
    let took = started.elapsed();
    assert!(
        took < BUDGET,
        "the replay took {took:?}; ADR 030 allows {BUDGET:?}"
    );
}

#[test]
fn the_bombs_at_the_cap_get_the_documented_statuses() {
    let at_cap = gzip(&vec![b' '; INFLATED_CAP]);
    let over = gzip(&vec![b' '; INFLATED_CAP + 1]);
    assert!(at_cap.len() < 64 * 1024 && over.len() < 64 * 1024);
    // At the cap the whole thing inflates and is then not a composition; one
    // byte over is refused at the cap before it is parsed.
    assert!(matches!(try_load(&at_cap).err(), Some(-3) | Some(-5)));
    assert_eq!(try_load(&over).err(), Some(-2));
}

#[test]
fn a_valid_tgs_in_the_corpus_loads() {
    let loaded = try_load(&gzip(&fixture().into_bytes()));
    assert!(loaded.is_ok());
}
