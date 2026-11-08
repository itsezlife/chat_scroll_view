import 'package:catalog_assets/catalog_assets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';

/// Holds the animations still while the panel moves, and the chat's while a
/// popup panel is over it, as the reference clients do.
///
/// Two holds, from the presentation's visibility alone:
///
/// - **While the panel moves in or out** (`PanelVisibility.isMoving`, of any
///   kind: popup, dock, keyboard replacement), [PlaybackPauseLayer.routeMoving]
///   is set on the clock: nothing advances, decodes or uploads, every surface
///   keeps its frame, and the frames go to the motion. The reference desktop
///   client paints its panel from a snapshot for the show and hide and plays
///   nothing in it; the reference mobile client locks its notifications for
///   the panel's animation. Playback resumes when the motion settles.
/// - **While a popup panel is on screen** (`AnchoredPopup`, from showing to
///   hidden), [chatHeld] is true: the host feeds it to the chat's embeds
///   (`ContentEmbed.held`), so the chat under the popup shows its frames and
///   keeps them while the panel plays. The reference desktop client pauses
///   the chat's animations for as long as its panel is shown. A dock sits
///   beside the chat and a keyboard panel below it; neither holds the chat.
///
/// The layer is set and cleared only when this object's own claim changes, so
/// a layer the host raised itself is not cleared by a settle, and [dispose]
/// clears only what it set.
final class PanelPlaybackHold {
  /// Follows [presentation] and holds [clock]'s playback by it.
  PanelPlaybackHold({
    required listen.ValueListenable<PanelVisibility> presentation,
    required PlaybackClock clock,
  }) : _presentation = presentation,
       _clock = clock {
    presentation.addListener(_follow);
    _follow();
  }

  final listen.ValueListenable<PanelVisibility> _presentation;
  final PlaybackClock _clock;
  final listen.ValueNotifier<bool> _chatHeld = listen.ValueNotifier(false);
  bool _holdsMotion = false;
  bool _disposed = false;

  /// Whether the chat's playback is held: a popup panel is on screen.
  listen.ValueListenable<bool> get chatHeld => _chatHeld;

  void _follow() {
    if (_disposed) return;
    final state = _presentation.value;
    _holdMotion(state.isMoving);
    _chatHeld.value = state.isVisible && state.kind is AnchoredPopup;
  }

  void _holdMotion(bool on) {
    if (_holdsMotion == on) return;
    _holdsMotion = on;
    _clock.setPaused(PlaybackPauseLayer.routeMoving, paused: on);
  }

  /// Stops following and gives back both holds. Idempotent. The clock and the
  /// presentation are their owners' to dispose.
  void dispose() {
    if (_disposed) return;
    _holdMotion(false);
    _chatHeld.value = false;
    _disposed = true;
    _presentation.removeListener(_follow);
    _chatHeld.dispose();
  }
}
