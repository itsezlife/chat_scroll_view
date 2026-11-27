import 'package:content_model/content_model.dart';

/// The operations of the `capabilities` diagnostics events the composer
/// emits through `ChatDiagnostics.current`, correlated by the controller's
/// chat id. The `denied` event of an attempt is the feedback seam's
/// (`CapabilityFeedback.onDenied`), not one of these.
///
/// Closed: an operation is added here with the path that emits it. Names
/// are stable, since logs filter by them.
enum ComposerCapabilitiesOp implements DiagnosticOp {
  /// The input row's panel was chosen from the write access (debug): the
  /// `writeAccess` form (with `reason` for a restriction and `tag` for a
  /// host form), the `panel` id and the `builder` (`field`, `host` or
  /// `default`). Once per change of those, not per build.
  panelChosen,
}
