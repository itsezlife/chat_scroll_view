import 'package:meta/meta.dart';

/// Which budget an entry counts against.
enum AssetTier {
  /// Stills: one decoded frame, small and cheap to make again.
  still,

  /// Animations: frame buffers and decoder state, large and slow to make
  /// again. Budgeted apart so a screenful of stickers cannot push every emoji
  /// out, and the reverse.
  animated,
}

/// Byte budgets of the unattached entries' cache, one per [AssetTier].
///
/// An entry with a live binding is pinned and counts toward its tier's bytes
/// but is never evicted, so a tier can exceed its budget while surfaces hold
/// more than it. The budget bounds what is kept for later (pager keep-alive,
/// scrolling back), not what is on screen.
///
/// ## Defaults
///
/// [AssetCacheBudgets.defaults] is 24 MiB of stills and 12 MiB of animations.
/// They come from the churn benchmark
/// (`test/benchmark/asset_cache_churn_bench_test.dart`, tables in the package
/// README): scrolling down a catalogue and back, 24 MiB keeps all of the last
/// four screens of 192 px stickers (24 cells a screen, 144 KiB each) and of
/// 102 px custom emoji (64 cells a screen, 40 KiB each), where 16 MiB already
/// misses one sticker in twelve and 12 MiB one in three; 12 MiB of animations
/// keeps the one screen of 256 px animated stickers (12 cells, 512 KiB each)
/// just scrolled past, and half of the screen before it. The figures stay
/// under the Android client's own (a 15 to 30 MB bitmap cache and a 10 MiB
/// animation cache). Pinned bytes come out of the budget first, so a surface
/// that shows more than a tier's budget leaves nothing for keep-alive; a host
/// with a different device class sets its own.
@immutable
final class AssetCacheBudgets {
  /// Creates budgets of [stillBytes] and [animatedBytes].
  const AssetCacheBudgets({
    this.stillBytes = _defaultStillBytes,
    this.animatedBytes = _defaultAnimatedBytes,
  }) : assert(
         stillBytes >= 0 && animatedBytes >= 0,
         'budgets are not negative',
       );

  /// The documented defaults; see the class documentation.
  static const AssetCacheBudgets defaults = AssetCacheBudgets();

  static const int _defaultStillBytes = 24 * 1024 * 1024;
  static const int _defaultAnimatedBytes = 12 * 1024 * 1024;

  /// Bytes the still tier may keep unattached.
  final int stillBytes;

  /// Bytes the animated tier may keep unattached.
  final int animatedBytes;

  /// The budget of [tier].
  int of(AssetTier tier) => switch (tier) {
    AssetTier.still => stillBytes,
    AssetTier.animated => animatedBytes,
  };

  @override
  bool operator ==(Object other) =>
      other is AssetCacheBudgets &&
      other.stillBytes == stillBytes &&
      other.animatedBytes == animatedBytes;

  @override
  int get hashCode => Object.hash(stillBytes, animatedBytes);

  @override
  String toString() =>
      'AssetCacheBudgets(still: $stillBytes, animated: $animatedBytes)';
}
