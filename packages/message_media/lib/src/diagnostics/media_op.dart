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

  /// A cell could not be built (error): the [MediaBuilder] as `builder` and
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
  /// the `part`, its `role`, the `mode` (`normal`) and the [MediaHitOutcome]
  /// as `outcome`. The viewport's own `hit` event says the tap was an
  /// activation.
  hit,

  /// An activation dropped by the input guard (debug): the `part` and the
  /// milliseconds since the last accepted one (`sinceMs`).
  activationDropped,

  /// The host's viewer was asked to open (info): the `index` of the item
  /// and the `count` of items it pages through.
  viewerOpened,

  /// An item had no rectangle for the viewer (warning): the
  /// [MediaViewerMoment] as `at`.
  originRectMissing,

  /// An item's upload changed what its cell shows (debug): the transfer
  /// `state` (`sending`, `sent`, or `none` once published), with the
  /// `sent` and `total` bytes while sending. Reported on a change of state,
  /// not of bytes.
  uploadState,

  /// The cross on an item of a message being sent dropped it (info): the
  /// `albumBefore` and `albumAfter` item counts.
  itemCancelled,

  /// A cell was handed its item's send origin (debug): the `platform`,
  /// `originPresent`, the [MediaFlightOutcome] as `outcome`, and for want
  /// of an overlay the [MediaFlightSkip] as `reason`.
  sendOriginFlight,
}

/// The cell builder or chrome slot that failed; the `builder` of a
/// [MediaOp.cellFailed] event.
enum MediaBuilder {
  /// The box cell builder.
  box,

  /// The file row cell builder.
  row,

  /// The info badge slot.
  infoBadge,

  /// The sent check slot.
  sentCheck,

  /// The status control slot.
  statusControl,

  /// The spoiler slot.
  spoiler,

  /// The options affordance slot.
  options,
}

/// What an activated part did; the `outcome` of a [MediaOp.hit] event.
enum MediaHitOutcome {
  /// A hidden spoiler was revealed.
  reveal,

  /// A download or an upload was stopped.
  cancel,

  /// The card's page was asked to open.
  open,

  /// The card's action button was activated.
  action,
}

/// When an item's rectangle was missing; the `at` of a
/// [MediaOp.originRectMissing] event.
enum MediaViewerMoment {
  /// The viewer opened from a tap whose hit had no rectangle.
  open,

  /// The viewer asked for the item by id on close and it was off screen.
  close,
}

/// What a cell did with its send origin; the `outcome` of a
/// [MediaOp.sendOriginFlight] event.
enum MediaFlightOutcome {
  /// The item flew in from its origin.
  flown,

  /// No flight: reduce motion, or no overlay to fly in.
  skipped,
}

/// Why a flight was skipped other than reduce motion; the `reason` of a
/// [MediaOp.sendOriginFlight] event.
enum MediaFlightSkip {
  /// No overlay above the cell to fly in.
  noOverlay,
}
