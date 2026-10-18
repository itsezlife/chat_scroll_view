import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:meta/meta.dart' show internal;

/// Moves the dust over hidden spoilers on the asset cache's shared clock.
///
/// The markdown engine owns no clock for the dust: it says when something
/// would move ([MarkdownSpoilerController.wantsTicks]) and takes the time from
/// whoever calls [MarkdownSpoilerController.advance]. The viewport is that
/// host, and it borrows the cache's [PlaybackClock] (ADR 022, ADR 037) rather
/// than run a ticker of its own, so the dust shares the frames, the cadence
/// and the pause layers (a route moving, a fast scroll, low power) of every
/// animated asset on screen.
///
/// The clock is subscribed to only while [spoilers] wants ticks, so a chat with
/// no hidden spoiler on screen keeps the engine asleep.
@internal
final class ChatSpoilerDust {
  /// Starts feeding [spoilers] from [clock], and keeps doing so until
  /// [dispose].
  ChatSpoilerDust({
    required MarkdownSpoilerController spoilers,
    required PlaybackClock clock,
  }) : _spoilers = spoilers,
       _clock = clock {
    spoilers.wantsTicks.addListener(_sync);
    _sync();
  }

  // The engine moves the dust at its own rate; frames in between are skipped
  // there, so the clock is asked for no more than that.
  static const Duration _frameInterval = Duration(
    microseconds:
        Duration.microsecondsPerSecond ~/
        MarkdownSpoilerController.fillFrameRate,
  );

  final MarkdownSpoilerController _spoilers;
  final PlaybackClock _clock;
  PlaybackSubscription? _subscription;

  void _sync() {
    if (_spoilers.wantsTicks.value) {
      _subscription ??= _clock.follow(
        _spoilers.advance,
        frameInterval: _frameInterval,
      );
    } else {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  /// Stops listening and gives the clock back. Idempotent.
  void dispose() {
    _spoilers.wantsTicks.removeListener(_sync);
    _subscription?.cancel();
    _subscription = null;
  }
}
