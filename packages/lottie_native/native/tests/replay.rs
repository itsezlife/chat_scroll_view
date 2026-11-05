//! Deterministic replay of hostile inputs through `chat_lottie_load`: the
//! guarantee is about the boundary (no panic, no hang, a documented status,
//! a null handle on failure), not about which status each input earns.
mod common;
use common::*;
use std::sync::mpsc;
use std::time::Duration;

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
    out.push(("269 zero bytes".into(), vec![0; 269]));
    let mut rng = Lcg(0x5eed);
    for n in 0..100 {
        let mut bytes = fixture.clone();
        let at = rng.next() as usize % bytes.len();
        bytes[at] = rng.next() as u8;
        out.push((format!("mutation {n} at {at}"), bytes));
    }
    out
}

#[test]
fn hostile_inputs_never_panic_hang_or_leak_a_handle() {
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
        .recv_timeout(Duration::from_secs(60))
        .expect("replay hung or a load panicked across the boundary");
}
