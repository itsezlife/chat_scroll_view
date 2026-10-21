import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';

/// An [AssetPaintable] that records what is done to it.
///
/// With [frameDurations] it also plays the way a frame sequence does, so the
/// binding and the surfaces above it can be driven by a clock alone: the first
/// paint that animates starts a pass, the frame shown follows the time since
/// then, and a paint that does not loop holds the rest frame once the pass is
/// over. Without them it only records, and never holds.
final class FakeAssetPaintable implements AssetPaintable {
  /// Creates a paintable called [label] (shown in failures).
  FakeAssetPaintable({
    this.label = 'paintable',
    bool? isAnimated,
    this.sprite,
    this.frameDurations = const [],
  }) : isAnimated = isAnimated ?? frameDurations.isNotEmpty;

  /// Names this paintable in test output.
  final String label;

  @override
  final bool isAnimated;

  @override
  final AtlasSprite? sprite;

  /// How long each frame of the sequence it plays lasts; empty for a
  /// paintable that only records.
  final List<Duration> frameDurations;

  /// Every [paint] call, in order.
  final List<({Rect rect, AssetPaintContext context})> paints = [];

  /// How many times [dispose] was called.
  int disposals = 0;

  /// How many times [restart] rewound a holding playback.
  int restarts = 0;

  /// Whether the cache disposed it.
  bool get isDisposed => disposals > 0;

  Duration? _startedAt;
  bool _holding = false;
  int _frame = 0;

  /// The index of the frame the last paint drew (0 before any).
  int get frameShown => _frame;

  Duration get _passLength =>
      frameDurations.fold(Duration.zero, (sum, d) => sum + d);

  @override
  bool get isHolding => _holding;

  @override
  bool restart() {
    if (!_holding) return false;
    _holding = false;
    _startedAt = null;
    _frame = 0;
    restarts++;
    return true;
  }

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    assert(!isDisposed, '$label painted after dispose');
    paints.add((rect: rect, context: context));
    if (frameDurations.isEmpty || !context.animate) return;
    if (_holding) {
      if (!context.loop) return;
      _holding = false;
      _startedAt = null;
    }
    final started = _startedAt ??= context.time;
    final elapsed = context.time - started;
    final total = _passLength;
    if (elapsed >= total && !context.loop) {
      _holding = true;
      _frame = context.restFrame == AssetRestFrame.last
          ? frameDurations.length - 1
          : 0;
      return;
    }
    var left = Duration(
      microseconds: elapsed.inMicroseconds % total.inMicroseconds,
    );
    _frame = 0;
    while (left >= frameDurations[_frame]) {
      left -= frameDurations[_frame];
      _frame++;
    }
  }

  @override
  void dispose() => disposals++;

  @override
  String toString() => 'FakeAssetPaintable($label)';
}
