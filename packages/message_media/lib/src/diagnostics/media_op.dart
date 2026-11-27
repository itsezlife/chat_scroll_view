import 'package:content_model/content_model.dart';

/// The operations of the `media` diagnostics events this package emits
/// through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum MediaOp implements DiagnosticOp {
  /// A media layout was computed (trace): the policy's platform family, the
  /// item count, the block kinds, the available width, the mosaic
  /// algorithm and the duration in microseconds.
  layoutComputed,

  /// A box took a fallback size rule (debug): the rule (no dimensions, a
  /// minimum width, the caption widening) and the resulting size.
  layoutFallback,

  /// An item of a custom kind was laid out as a file row (warning): its
  /// kind tag.
  unknownKind,

  /// A cell could not be built (error): which builder (`box`, `row`, or a
  /// chrome slot: `infoBadge`, `statusControl`, `spoiler`, `options`) and
  /// the error's type (`missingItem` for a cell whose item was not given).
  cellFailed,

  /// A spoiler's reveal started (debug): the policy's platform family, the
  /// reveal's form (`circle`, `spot`, `crossFade`) and whether reduce
  /// motion made it jump to revealed.
  spoilerRevealed,
}
