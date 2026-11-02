/// Whether a real-IME window can be compared with its baseline (spec 7.3).
///
/// Pure Dart. The system keyboard's height varies with the input method, its
/// layout and the user's settings; a window whose settled inset differs from
/// its baseline's by more than [kImeInsetTolerance] measured another keyboard,
/// so it is reported "not comparable" instead of regressed.
library;

/// The allowed relative difference of a settled inset from the baseline's.
const double kImeInsetTolerance = 0.02;

/// The metric every real-IME window records: the inset it settled at, in
/// physical pixels.
const String kImeSettledInsetMetric = 'ime.settled_inset_px';

/// Whether [settledPx] is within [kImeInsetTolerance] of [baselinePx].
bool imeComparable({required double settledPx, required double baselinePx}) =>
    baselinePx == 0
    ? settledPx == 0
    : (settledPx - baselinePx).abs() / baselinePx <= kImeInsetTolerance;
