import 'package:flutter/painting.dart' show TextPosition;
import 'package:flutter/widgets.dart' show Offset;

/// Which half of a secondary mouse click an [ExtendedSecondaryClick] reports.
enum ExtendedSecondaryClickPhase {
  /// The button went down.
  down,

  /// The button came up over the field, ending a click that began on it.
  up,
}

/// One edge of a secondary mouse click on a field that asked to hear it
/// (`ExtendedTextField.onSecondaryClick`).
///
/// The press and the release are both reported, because desktop toolkits
/// differ in which of the two opens a context menu and the field does not
/// choose for the host.
final class ExtendedSecondaryClick {
  /// A click edge at [globalPosition], over [textPosition] in the text.
  const ExtendedSecondaryClick({
    required this.phase,
    required this.globalPosition,
    required this.textPosition,
  });

  /// Which edge this is.
  final ExtendedSecondaryClickPhase phase;

  /// Where the pointer was, in global coordinates.
  final Offset globalPosition;

  /// The caret position nearest the pointer, in the field's text.
  final TextPosition textPosition;
}
