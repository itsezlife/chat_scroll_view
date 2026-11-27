import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';

/// The operations of the `capabilities` diagnostics events the composer
/// emits through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names
/// are stable, since logs filter by them. The `denied`, `denialTextMissing`
/// and `feedbackFailed` events of the composer's attempts and texts are
/// `chat_capabilities`' own (`CapabilitiesOp`), emitted by its
/// `CapabilityFeedback`.
enum ComposerOp implements DiagnosticOp {
  /// The composer chose its input row's panel from the write access
  /// (debug): the `writeAccess` form (with `reason` for a restriction and
  /// `tag` for a host form), the `panel` id and the `builder`: `field` when
  /// the user may write (the row is the spec's), `host` or `default` for a
  /// replacing panel. Emitted once per change of the choice, when the
  /// capabilities change, never from a build.
  panelChosen,

  /// Slow mode's countdown started (debug): the slow mode `intervalMs`,
  /// the `remainingMs` of the wait and whether a message is still
  /// `pending`.
  slowModeStarted,

  /// Slow mode's countdown ended (debug), at its next send time or because
  /// the host's new value lifted it: `intervalMs`, `remainingMs` (zero at
  /// the time, more when lifted early) and `pending`.
  slowModeEnded,
}

/// Where the composer draws a denial text in place, named in the
/// `denialTextMissing` event when the host gives none.
enum ComposerDenialForm implements DenialForm {
  /// The default panel that replaces the input row.
  restrictionBar,

  /// The locked text field's placeholder.
  lockedField,

  /// A dimmed action's spoken hint.
  dimmedAction,
}
