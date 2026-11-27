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

  /// A picker's limits were derived from a chat's value (debug): the allowed
  /// attach kinds, grouping, single select and the caption, file and album
  /// limits and one-send mode. Emitted by the picker's package, which owns
  /// the derivation.
  limitsDerived,

  /// A picker entered or left one-send mode (debug): `on`, and the album
  /// cap one send unit holds. Emitted by the picker's package.
  pickerOneSend,
}
