import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';

// [DBG-141] Ticket 141's device log, behind --dart-define=DBG_141=true.
const bool _dbg141 = bool.fromEnvironment('DBG_141');

/// Holds the animations still while the panel moves, and the chat's while a
/// popup panel or a pack sheet is over it, as the reference clients do.
///
/// Two holds from the presentation's visibility, and one the host asks for:
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
/// - **While a claim is open** ([holdChat]), [chatHeld] is true as well: the
///   host claims it for a pack sheet over the chat. The reference mobile
///   client pauses what is under its sticker and emoji sheets while their own
///   stickers play; one clock serves both here, so the chat is held on its
///   own rather than the clock paused.
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
  bool _popupOver = false;
  int _claims = 0;
  bool _holdsMotion = false;
  bool _disposed = false;

  /// Whether the chat's playback is held: a popup panel is on screen, or a
  /// claim is open.
  listen.ValueListenable<bool> get chatHeld => _chatHeld;

  /// Holds the chat until the claim is released (idempotent); claims count.
  /// Releasing one after [dispose] does nothing.
  ChatPlaybackClaim holdChat() {
    if (_disposed) return ChatPlaybackClaim._(null);
    _claims++;
    _updateChat();
    return ChatPlaybackClaim._(() {
      if (_disposed) return;
      _claims--;
      _updateChat();
    });
  }

  void _follow() {
    if (_disposed) return;
    final state = _presentation.value;
    _holdMotion(state.isMoving);
    _popupOver = state.isVisible && state.kind is AnchoredPopup;
    _updateChat();
  }

  void _updateChat() {
    final held = _popupOver || _claims > 0;
    if (_dbg141 && held != _chatHeld.value) {
      debugPrint('[DBG-141] chatHeld=$held claims=$_claims');
    }
    _chatHeld.value = held;
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

/// One open claim on the chat's playback ([PanelPlaybackHold.holdChat]).
final class ChatPlaybackClaim {
  ChatPlaybackClaim._(this._onRelease);

  void Function()? _onRelease;

  /// Gives the claim back. Idempotent.
  void release() {
    final onRelease = _onRelease;
    _onRelease = null;
    onRelease?.call();
  }
}
