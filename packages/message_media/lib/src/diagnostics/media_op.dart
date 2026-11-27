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

  /// A message's media layout changed and a transition toward the new one
  /// started (trace): the trigger, the entering and exiting cell counts,
  /// the duration in milliseconds (0 when it jumps to its end) and whether
  /// reduce motion collapsed it.
  transitionStarted,

  /// A layout changed again while its transition ran, and the next leg
  /// starts from the frame it reached (trace): the new trigger and the
  /// milliseconds the interrupted leg had run.
  transitionInterrupted,

  /// What an activated part did beyond the viewport's arbitration (debug):
  /// the `part`, its `role`, the `mode` (`normal`) and the `outcome`,
  /// `reveal` (a hidden spoiler revealed) or `cancel` (a download stopped).
  /// The viewport's own `hit` event says the tap was an activation.
  hit,

  /// An activation dropped by the input guard (debug): the `part` and the
  /// milliseconds since the last accepted one (`sinceMs`).
  activationDropped,

  /// The host's viewer was asked to open (info): the `index` of the item
  /// and the `count` of items it pages through.
  viewerOpened,

  /// An item had no rectangle for the viewer (warning): `at` open (the tap's
  /// hit had none) or close (the viewer asked for it by id and it was off
  /// screen).
  originRectMissing,
}
