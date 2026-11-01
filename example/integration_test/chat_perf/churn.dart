/// The churn family's seams and arithmetic (spec 7.2): a frame-clocked
/// mutation schedule, the per-frame trace it records, and the outcome metrics
/// computed from that trace.
///
/// Pure Dart: scenarios speak to a [ChurnContext]; the device implements it,
/// unit tests fake it.
library;

import 'metrics.dart';
import 'registry.dart';

/// One frame of a churn window, sampled after the frame.
final class ChurnFrame {
  const ChurnFrame({
    required this.index,
    required this.tMs,
    required this.anchorId,
    required this.anchorOffsetDp,
    required this.isAtTail,
    required this.bandBottomDp,
    required this.placeholders,
    this.animating = false,
  });

  /// Frames from the window's first mutation: negative in the pre-roll.
  final int index;

  /// Milliseconds since the window's first sample.
  final double tMs;
  final int anchorId;
  final double anchorOffsetDp;
  final bool isAtTail;

  /// Bottom edge of the lowest visible row, or null with no visible row.
  final double? bandBottomDp;

  /// Placeholder rows alive (a slot whose message is not loaded).
  final int placeholders;

  /// An `animateTo` flight was in progress after the frame. A stitch flight
  /// moves the anchor to its target before its first frame and travels in
  /// paint, so neither the anchor nor its offset shows it (finding 09).
  final bool animating;
}

/// Mutations keyed by the frame they fire on, counted from the window's
/// first mutation frame (frame 0).
final class FrameSchedule {
  final _actions = <int, List<void Function()>>{};

  /// Fires [action] on frame [frame] of the schedule's clock.
  void atFrame(int frame, void Function() action) {
    assert(frame >= 0, 'a mutation cannot precede the first mutation frame');
    (_actions[frame] ??= []).add(action);
  }

  /// The actions due at [frame], in the order added.
  List<void Function()> actionsAt(int frame) => _actions[frame] ?? const [];

  /// The last frame with an action; zero for an empty schedule.
  int get lastFrame => _actions.keys.fold(0, (a, b) => a > b ? a : b);
}

/// Pre-roll length in frames: stability baseline only.
const int kPreRollFrames = 10;

/// Post-roll length in frames: 0.5 s at 120 Hz.
const int kPostRollFrames = 60;

/// What a churn script may do to the host's data and viewport.
abstract interface class ChurnHost {
  /// Id of the newest message in the source.
  int get newestId;

  /// Inserts one message after the newest; [self] marks it the viewer's own.
  void insert({required bool self});

  /// Replaces message [id] by a taller body, or by its original.
  void edit(int id, {required bool taller});

  /// Removes message [id].
  void remove(int id);

  /// Moves the unread boundary to [id]; `null` clears it.
  void setUnreadBoundary(int? id);

  /// A visible message that is not the anchor, or null with none.
  int? get visibleNonAnchorId;

  /// Milliseconds from mount to the first message built; null until then.
  double? get firstBuildMs;

  /// The path (`close`, `stitch`, `instant`, `none`) the last finished
  /// `animateTo` flight took; null before one finished.
  String? get lastAnimatePath;

  /// Data source fetches started since the host mounted.
  int get fetches;

  /// Builds the viewport, for a host mounted without it
  /// ([BenchSetup.mountViewport] false), and restarts the mount clock
  /// [firstBuildMs] reads. Call inside the window that measures the opening.
  Future<void> openViewport();
}

/// A [ScenarioContext] that can run frame-clocked schedules on the host.
abstract interface class ChurnContext implements ScenarioContext {
  ChurnHost get churn;

  /// Seats the viewport at the newest message and waits until it is idle.
  Future<void> seatTail();

  /// Seats the viewport on message [id] and waits until it is loaded and idle.
  Future<void> seatOn(int id, {double alignment = 0.5});

  /// Runs [schedule] with [preRoll] frames before and [postRoll] after, one
  /// pumped frame each, and returns the per-frame trace. A window that has not
  /// settled by its end reports `settled` as exact 0. Call inside `measure`.
  Future<List<ChurnFrame>> runSchedule(
    FrameSchedule schedule, {
    int preRoll = kPreRollFrames,
    int postRoll = kPostRollFrames,
  });

  /// Runs [body] and samples every frame it spans.
  Future<List<ChurnFrame>> recordFrames(Future<void> Function() body);

  /// Adds [metrics] to the window [name] being measured.
  void report(String name, Map<String, Metric> metrics);
}

List<ChurnFrame> _post(List<ChurnFrame> f) => [
  for (final x in f)
    if (x.index >= 0) x,
];

ChurnFrame? _baseline(List<ChurnFrame> f) {
  ChurnFrame? base;
  for (final x in f) {
    if (x.index < 0) base = x;
  }
  return base ?? (f.isEmpty ? null : f.first);
}

/// Frames from the first mutation until the viewport is at the tail (and,
/// with [newestId], anchored on it) and stays there, counting the first such
/// frame; null if the last frame is not pinned.
int? tailPinFrames(List<ChurnFrame> frames, {int? newestId}) {
  bool pinned(ChurnFrame x) =>
      x.isAtTail && (newestId == null || x.anchorId == newestId);
  final post = _post(frames);
  if (post.isEmpty || !pinned(post.last)) return null;
  var lastUnpinned = -1;
  for (final x in post) {
    if (!pinned(x)) lastUnpinned = x.index;
  }
  return lastUnpinned + 2;
}

/// Frames from the first mutation to the last frame with an `animateTo`
/// flight in progress, counting both; zero when no flight ran.
int animateTravelFrames(List<ChurnFrame> frames) {
  var last = -1;
  for (final x in _post(frames)) {
    if (x.animating) last = x.index;
  }
  return last + 1;
}

/// Post-mutation frames in which the viewport was not at the tail.
int tailUnpinnedFrames(List<ChurnFrame> frames) =>
    _post(frames).where((x) => !x.isAtTail).length;

/// Largest anchor offset change from the baseline among post-mutation frames
/// that keep the baseline's anchor id.
double anchorDriftDp(List<ChurnFrame> frames) {
  final base = _baseline(frames);
  if (base == null) return 0;
  var drift = 0.0;
  for (final x in _post(frames)) {
    if (x.anchorId != base.anchorId) continue;
    final d = (x.anchorOffsetDp - base.anchorOffsetDp).abs();
    if (d > drift) drift = d;
  }
  return drift;
}

/// Post-mutation frames whose anchor id differs from the baseline's.
int anchorIdChanges(List<ChurnFrame> frames) {
  final base = _baseline(frames);
  if (base == null) return 0;
  return _post(frames).where((x) => x.anchorId != base.anchorId).length;
}

/// Largest change of the visible band's bottom edge from the baseline; null
/// when the baseline had no visible band (invariant 19 does not apply).
double? bandBottomShiftDp(List<ChurnFrame> frames) {
  final base = _baseline(frames)?.bandBottomDp;
  if (base == null) return null;
  var shift = 0.0;
  for (final x in _post(frames)) {
    final b = x.bandBottomDp;
    if (b == null) continue;
    final d = (b - base).abs();
    if (d > shift) shift = d;
  }
  return shift;
}

/// Absolute anchor offset change between the baseline and the last frame.
double finalScrollDeltaDp(List<ChurnFrame> frames) {
  final base = _baseline(frames);
  if (base == null || frames.isEmpty) return 0;
  return (frames.last.anchorOffsetDp - base.anchorOffsetDp).abs();
}

/// Milliseconds from the first mutation frame to the last frame in which the
/// anchor, its offset or the tail flag changed, or an `animateTo` flight was
/// in progress.
double settleMs(List<ChurnFrame> frames, {double epsilonDp = 0.01}) {
  final post = _post(frames);
  if (post.isEmpty) return 0;
  var prev = _baseline(frames) ?? post.first;
  var last = post.first.tMs;
  for (final x in post) {
    final moved =
        x.animating ||
        x.anchorId != prev.anchorId ||
        x.isAtTail != prev.isAtTail ||
        (x.anchorOffsetDp - prev.anchorOffsetDp).abs() > epsilonDp;
    if (moved) last = x.tMs;
    prev = x;
  }
  return last - post.first.tMs;
}

/// Frames in which at least one placeholder row was alive.
int shimmerFrames(List<ChurnFrame> frames) =>
    frames.where((x) => x.placeholders > 0).length;

/// Durations in milliseconds of each run of frames with a placeholder alive,
/// one per chunk boundary crossing: from the first such frame to the first
/// frame after the run (or the last frame if the run reaches the end).
List<double> placeholderRunsMs(List<ChurnFrame> frames) {
  final runs = <double>[];
  double? start;
  for (final x in frames) {
    if (x.placeholders > 0) {
      start ??= x.tMs;
    } else if (start != null) {
      runs.add(x.tMs - start);
      start = null;
    }
  }
  if (start != null && frames.isNotEmpty) runs.add(frames.last.tMs - start);
  return runs;
}

/// `settled` is exact 1 when the window ended with no pending frame.
Metric settledMetric({required bool settled}) =>
    Metric(settled ? 1 : 0, kind: MetricKind.exact, role: MetricRole.headline);

/// Metric constructors with kind fixed per unit, so scenarios name only the
/// quantity and whether it is judged.
abstract final class ChurnMetric {
  static MetricRole _role(bool headline) =>
      headline ? MetricRole.headline : MetricRole.diagnostic;

  static Metric dp(double v, {bool headline = false}) =>
      Metric(v, kind: MetricKind.dp, role: _role(headline));
  static Metric count(num v, {bool headline = false}) =>
      Metric(v.toDouble(), kind: MetricKind.count, role: _role(headline));
  static Metric ms(double v, {bool headline = false}) =>
      Metric(v, kind: MetricKind.ms, role: _role(headline));
  static Metric exactDp(double v) =>
      Metric(v, kind: MetricKind.exact, role: MetricRole.headline);
}
