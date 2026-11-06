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
