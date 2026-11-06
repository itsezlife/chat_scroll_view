import 'dart:developer' show Timeline;
import 'dart:ui' show PlatformDispatcher;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackBinding;
import 'package:chat_scroll_view_example/src/common/pointer_tape.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Finds the soft keyboard's hide in a stream of bottom view insets.
///
/// The system consumes Back to hide the keyboard, so the app sees only the
/// inset falling. The hide is stamped where it began (the first fall), not
/// where the inset reached zero. One that follows the app's own input within
/// [causeWindowMicros] (a tap that opened the panel, a Back the app handled)
/// is not reported: the replayed input does it again.
final class ImeHideDetector {
  /// Creates a detector at rest.
  ImeHideDetector({this.causeWindowMicros = 400000});

  /// How soon after the app's own input a hide counts as its consequence.
  final int causeWindowMicros;

  double _bottom = 0;
  int? _fallStart;
  int? _sinceInputAtFallStart;

  /// Feeds the inset at [now]; [sinceInputMicros] is the age of the last
  /// pointer sample or Back. Returns the event and its time, if one is due.
  (TapeSystemEvent, int)? onInset(
    double bottom,
    int now, {
    required int sinceInputMicros,
  }) {
    final previous = _bottom;
    _bottom = bottom;
    if (bottom > previous) {
      _fallStart = null;
      return previous == 0 ? (TapeSystemEvent.imeShown, now) : null;
    }
    if (previous <= 0 || bottom >= previous && bottom > 0) return null;
    if (_fallStart == null) {
      _fallStart = now;
      _sinceInputAtFallStart = sinceInputMicros;
    }
    if (bottom > 0) return null;
    final start = _fallStart!;
    final caused = _sinceInputAtFallStart! < causeWindowMicros;
    _fallStart = null;
    return caused ? null : (TapeSystemEvent.imeHidden, start);
  }
}

/// Feeds [PointerTape] the system events pointer packets do not carry.
///
/// Registered ahead of the navigators, so [didPopRoute] sees every `popRoute`
/// (button, 3-button bar, and gesture without predictive back) first, notes
/// it and answers false so the navigators still run. Back claimed before the
/// IME is noted by [PointerTape.note] from the host's native adapter, and the
/// keyboard hiding by [didChangeMetrics].
final class TapeSystemRecorder with WidgetsBindingObserver {
  TapeSystemRecorder._();

  static TapeSystemRecorder? _instance;
  final _ime = ImeHideDetector();

  /// Registers the observer. Idempotent; call before `runApp`.
  static void install() {
    if (_instance != null) return;
    final recorder = _instance = TapeSystemRecorder._();
    WidgetsBinding.instance.addObserver(recorder);
  }

  @override
  Future<bool> didPopRoute() {
    PointerTape.note(TapeSystemEvent.back);
    return Future<bool>.value(false);
  }

  @override
  void didChangeMetrics() {
    if (!PointerTape.recording) return;
    final bottom =
        PlatformDispatcher.instance.implicitView?.viewInsets.bottom ?? 0;
    final found = _ime.onInset(
      bottom,
      Timeline.now,
      sinceInputMicros: PointerTape.sinceInputMicros,
    );
    if (found case (final event, final at)) PointerTape.note(event, at: at);
  }
}

/// Plays [event] the way the platform delivers it.
///
/// Back goes through the `popRoute` message the engine sends, or through
/// the host's pre-IME claim. The keyboard hiding does what the framework does
/// when the system closes the connection (`EditableText.connectionClosed`):
/// hides the input and drops the primary focus.
Future<void> dispatchTapeSystemEvent(TapeSystemEvent event) async {
  switch (event) {
    case TapeSystemEvent.back:
      // The message the engine sends for a system Back, so the binding runs
      // its own `handlePopRoute` (observers, then the navigators).
      // The deprecation points at `channelBuffers.push`, which queues the
      // message without reaching a handler under the test binding; this
      // calls the binding's own dispatcher directly.
      final messenger = ServicesBinding.instance.defaultBinaryMessenger;
      final call = SystemChannels.navigation.codec.encodeMethodCall(
        const MethodCall('popRoute'),
      );
      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage('flutter/navigation', call, null);
    case TapeSystemEvent.backPreIme:
      await ChatPreImeBackBinding.handleNativeBack();
    case TapeSystemEvent.imeHidden:
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      FocusManager.instance.primaryFocus?.unfocus();
    case TapeSystemEvent.imeShown:
      break;
  }
}
