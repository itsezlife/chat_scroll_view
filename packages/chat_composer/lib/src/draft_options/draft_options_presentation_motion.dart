import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The open and close every draft options presentation runs over its
/// scrim: the open once its scopes stand, the close once the scrim starts
/// closing, each started once at the chrome motion speed and reported
/// through the session's `motion` event.
///
/// The Android card, the iOS spring and the desktop box each play their own
/// motion ([playOpen], [playClose]); when they start and how they report is
/// the same for all three, so it lives here.
@internal
mixin DraftOptionsPresentationMotion<T extends StatefulWidget> on State<T> {
  bool _opened = false;
  bool _closed = false;

  /// The open the presentation shows.
  DraftOptionsSession get motionSession;

  /// The scrim whose close starts the presentation's.
  ChromeScrimController get motionScrim;

  /// Starts the open at [speed]; returns how long it runs at that speed.
  Duration playOpen(ChromeMotionSpeed speed);

  /// Starts the close at [speed]; returns how long it runs at that speed.
  Duration playClose(ChromeMotionSpeed speed);

  /// The chrome motion speed where the presentation stands.
  ChromeMotionSpeed get motionSpeed => ChromeMotionScope.of(context).speed;

  /// Reports a motion of [phase] lasting [duration] at [motionSpeed].
  void reportMotion(DraftOptionsMotionPhase phase, Duration duration) =>
      motionSession.reportMotion(
        phase,
        duration,
        reduceMotion: motionSpeed.isInstant,
      );

  @override
  void initState() {
    super.initState();
    motionScrim.addListener(_onScrim);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    reportMotion(DraftOptionsMotionPhase.open, playOpen(motionSpeed));
    // A scrim that started closing before the first build.
    _onScrim();
  }

  @override
  void dispose() {
    motionScrim.removeListener(_onScrim);
    super.dispose();
  }

  void _onScrim() {
    final scrim = motionScrim;
    // Not `isDone`: under an instant speed the scrim is done by the time
    // its close is heard, and that close is still reported.
    if (_closed || !mounted || !scrim.isClosing) return;
    _closed = true;
    reportMotion(DraftOptionsMotionPhase.close, playClose(motionSpeed));
  }
}
