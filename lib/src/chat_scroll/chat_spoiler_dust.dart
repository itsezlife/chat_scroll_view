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
///
/// ## Pausing keeps the phase
///
/// A pause (focus lost, a dialog over the chat) delivers no frame, and the
/// first one after it carries the live time. Handed on as it is, the dust
/// would jump by the whole pause; the reference client instead goes on from
/// where it stopped, clamping the first step after the pause to one dust
/// frame. A gap between two frames of more than [_maxStep] is such a pause (a
/// hitch of a few frames stays under it), and the time of the gap beyond one
/// dust frame is cut out of what [spoilers] is told, so the time it sees still
/// only grows. Whether anything was revealed is untouched: pausing is not a
/// reason to hide a spoiler again.
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

  // Three dust frames: more than a frame of jitter at any display rate, well
  // under the shortest pause anyone notices.
  static const Duration _maxStep = Duration(
    microseconds:
        3 *
        Duration.microsecondsPerSecond ~/
        MarkdownSpoilerController.fillFrameRate,
  );

  final MarkdownSpoilerController _spoilers;
  final PlaybackClock _clock;
  PlaybackSubscription? _subscription;

  // The time of the last frame seen and the paused time cut out so far. Both
  // outlive a subscription: the dust of a spoiler scrolled off and back goes
  // on from where it was.
  Duration? _lastFrame;
  Duration _cutOut = Duration.zero;

  void _sync() {
    if (_spoilers.wantsTicks.value) {
      _subscription ??= _clock.follow(_onFrame, frameInterval: _frameInterval);
    } else {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _onFrame(Duration now) {
    final last = _lastFrame;
    _lastFrame = now;
    if (last != null && now - last > _maxStep) {
      _cutOut += now - last - _frameInterval;
    }
    _spoilers.advance(now - _cutOut);
  }

  /// Stops listening and gives the clock back. Idempotent.
  void dispose() {
    _spoilers.wantsTicks.removeListener(_sync);
    _subscription?.cancel();
    _subscription = null;
  }
}
