import 'package:content_model/content_model.dart';

/// The operations of the `overlay` diagnostics events the draft options
/// overlay emits through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names
/// are stable, since logs filter by them. No event carries the draft's text
/// or a URL. The `scrim…` operations are the overlay's scrim's phases, each
/// with `owner` `draftOptions` and the scrim's `preset`.
enum OverlayOp implements DiagnosticOp {
  /// The scrim captured the window (trace): `captureUs`, the still's
  /// `stillWidth` and `stillHeight` in pixels.
  scrimCaptured,

  /// A still of the scrim was made (trace): `cpuMs` from the capture, and
  /// `glassSource`, whether it is the glass source's still (reported once
  /// for each still).
  scrimStillReady,

  /// The scrim has no still (debug): `why`, `presetNoBlur`, `noSource` or
  /// `reduceTransparency`.
  scrimStillSkipped,

  /// A press outside, back or Escape closed the scrim (debug): `by`
  /// (`outside`, `back`, `escape`) and the preset's `closeOn`.
  scrimDismissed,

  /// The scrim was taken away without its fade (debug).
  scrimCancelled,

  /// The scrim let go of its stills (trace): `stills`.
  scrimDisposed,

  /// The scrim's capture failed (error): the `errorType`, and `glassSource`
  /// when it was the glass source's still.
  scrimCaptureFailed,

  /// The overlay opened (info): `presentation` (`android`, `ios`, `ipad`,
  /// `desktop`), `part`, `page` (`pending`, `loaded`), the `apply` mode and
  /// whether the keyboard was up (`keyboardWasUp`).
  opened,

  /// An open was refused (debug): `why`, `desktopNotLoaded`, `denied` or
  /// `alreadyOpen`.
  openRefused,

  /// An open came within the tap guard of the accepted one and was dropped
  /// (debug): `ms` since the accepted open.
  openDropped,

  /// The overlay closed (info): its `trigger`, `openMs`, the `edits` made and
  /// whether they were `committed` (reported to the host and kept).
  closed,

  /// An edit reached the host (debug): its `field` (`position`, `size`,
  /// `remove`, `link`) and `mode`, `live` or `onSave`.
  editReported,

  /// A copy local to the overlay was dropped unsaved (debug): its `edits`.
  editsDiscarded,

  /// A tap in the live preview chose another link (debug): its `index` in
  /// the text's links and their `count`.
  linkTapped,

  /// A tap on a link in the live preview chose nothing (debug): `why`,
  /// `singleLink` (the policy needs more than one), `current` (the link
  /// already previewed) or `notInText` (not one of the text's links).
  linkTapIgnored,

  /// The chosen link's lookup stands at `state` (debug): `pending`,
  /// `loaded` or `none`, `ms` since the tap.
  linkState,

  /// A touch on an inert row was ignored (debug): its `row`, the size row
  /// drawn faded without shrinkable media.
  rowInertTouch,

  /// A tap on a row came within the row guard of the accepted one, or while
  /// the overlay closes, and was dropped (debug): its `row` and `ms` since
  /// the accepted tap.
  rowDropped,

  /// The remove row dropped the preview (info): the `dismissal` policy it
  /// applied (`none` without one) and whether the `nextLink` was taken.
  removeApplied,
}
