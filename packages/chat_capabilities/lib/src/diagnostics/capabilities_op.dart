import 'package:content_model/content_model.dart';

/// The operations of the `capabilities` diagnostics events this package
/// emits through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum CapabilitiesOp implements DiagnosticOp {
  /// A chat's value changed (debug): the changed group names, the write
  /// access form, whether slow mode is active and what protection denies.
  valueChanged,

  /// A chat's value breaks a rule (warning), one event per rule; debug
  /// builds also assert.
  invalidValue,

  /// A package asked for a denial text and got null, so it draws its silent
  /// form (debug): the action, the reason form and the form drawn.
  denialTextMissing,

  /// A host feedback hook threw and was swallowed (error): which hook, the
  /// action and the error's type.
  feedbackFailed,

  /// The user attempted a denied action (info): the action, the reason form,
  /// the consumer that reported it and, for a send during slow mode, the
  /// milliseconds left. Emitted by `CapabilityFeedback.onDenied`, so every
  /// consumer reports it the same way.
  denied,

  /// A picker's limits were derived from a chat's value (debug): the allowed
  /// attach kinds, grouping, single select and the caption, file and album
  /// limits. Emitted by the picker's package, which owns the derivation.
  limitsDerived,

  /// The composer chose its input row's panel from the write access (debug):
  /// the `writeAccess` form (with `reason` for a restriction and `tag` for a
  /// host form), the `panel` id and the `builder` (`field`, `host` or
  /// `default`). Emitted by the composer once per change of those.
  panelChosen,
}
