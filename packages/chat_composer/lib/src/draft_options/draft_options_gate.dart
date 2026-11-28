import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/draft_options/draft_options_policy.dart';
import 'package:chat_composer/src/draft_options/overlay_op.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// Why the draft options did not open, as their `openRefused` event names
/// it.
enum DraftOptionsOpenRefusal {
  /// The chat denies link previews.
  denied,

  /// The options are up already.
  alreadyOpen,

  /// The page is not loaded and the policy opens only on a loaded one
  /// (`DraftOptionsOverlayPolicy.opensOnPending` off).
  notLoaded,

  /// The host has no draft link to open on.
  noDraft,
}

/// The rules every open of the draft options passes, the overlay's and the
/// web menu's alike: link previews allowed, nothing up, and the input guard
/// ([DraftOptionsPolicy.openGuard]); with the `overlay` events they emit.
///
/// One per controller. The controllers keep their own surfaces and close
/// paths; what decides whether an open starts, and how it is reported,
/// lives here once.
@internal
final class DraftOptionsGate {
  /// A gate on [clock], emitting with [correlation]'s ids.
  DraftOptionsGate({required this.clock, this.correlation});

  /// The clock the guard reads.
  final ComposerClock clock;

  /// The ids of the events (the chat); none when null.
  final ChatCorrelation Function()? correlation;

  /// Whether the chat allows link previews.
  bool allowed = true;

  DateTime? _acceptedAt;

  /// Admits an open now; the time it was accepted, or null after the event
  /// that says why not: within the guard of the accepted open
  /// (`openDropped`), or refused (`openRefused`) while previews are denied,
  /// while one [isOpen], or on a page that is [notLoaded] where that
  /// refuses it.
  DateTime? admit({required bool isOpen, bool notLoaded = false}) {
    final now = clock.now();
    if (_acceptedAt case final accepted?
        when now.difference(accepted) < DraftOptionsPolicy.openGuard) {
      final ms = now.difference(accepted).inMilliseconds;
      emit(ChatEventLevel.debug, OverlayOp.openDropped, () => {'ms': ms});
      return null;
    }
    final refusal = switch ((allowed, isOpen, notLoaded)) {
      (false, _, _) => DraftOptionsOpenRefusal.denied,
      (_, true, _) => DraftOptionsOpenRefusal.alreadyOpen,
      (_, _, true) => DraftOptionsOpenRefusal.notLoaded,
      _ => null,
    };
    if (refusal != null) {
      refuse(refusal);
      return null;
    }
    return _acceptedAt = now;
  }

  /// Reports an open refused for [why].
  void refuse(DraftOptionsOpenRefusal why) => emit(
    ChatEventLevel.debug,
    OverlayOp.openRefused,
    () => {'why': why.name},
  );

  /// Whether [since] is within the open guard: a press then passes through.
  bool guards(DateTime since) =>
      clock.now().difference(since) < DraftOptionsPolicy.openGuard;

  /// Emits an `overlay` event of [op] at [level] with [fields].
  void emit(
    ChatEventLevel level,
    OverlayOp op,
    Map<String, Object> Function() fields,
  ) => ChatDiagnostics.current.emit(
    level,
    ChatEventCategory.overlay,
    op,
    correlation: correlation?.call() ?? ChatCorrelation.none,
    fields: fields,
  );
}
