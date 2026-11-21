import 'package:flutter/foundation.dart';
import 'package:viewport_scroll/src/fast_scroll_target.dart';

/// A [FastScrollTarget] a test sets by hand and whose commands it records.
///
/// [jumpTo] moves [progress] there (clamped) and notifies, as an engine
/// would; [stop] and the drag brackets only count.
final class FakeFastScrollTarget extends FastScrollTarget with ChangeNotifier {
  /// A target at [progress] showing [visibleShare] of its content.
  FakeFastScrollTarget({double? progress = 0, double visibleShare = 0.1})
    : _progress = progress,
      _visibleShare = visibleShare;

  double? _progress;
  double _visibleShare;

  /// Every [jumpTo] so far, as asked (before clamping).
  final List<double> jumps = [];

  /// How many times [stop] was called.
  int stops = 0;

  /// How many drags started and ended.
  int dragsStarted = 0, dragsEnded = 0;

  @override
  double? get progress => _progress;

  /// Moves the content as its engine would (a scroll of its own) and
  /// notifies; null for content that cannot scroll.
  set progress(double? value) {
    _progress = value;
    notifyListeners();
  }

  @override
  double get visibleShare => _visibleShare;
  set visibleShare(double value) {
    _visibleShare = value;
    notifyListeners();
  }

  @override
  void jumpTo(double progress) {
    jumps.add(progress);
    if (_progress == null) return;
    this.progress = progress.clamp(0.0, 1.0);
  }

  @override
  void stop() => stops++;

  @override
  void dragStarted() => dragsStarted++;

  @override
  void dragEnded() => dragsEnded++;
}
