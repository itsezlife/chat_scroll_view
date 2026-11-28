import 'package:content_model/content_model.dart';

/// The operations of the diagnostics events a content preview emits through
/// `ChatDiagnostics.current`, all of category `overlay`: the phases of the
/// chrome scrim under it, each with `owner` `contentPreview`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum ContentPreviewOp implements DiagnosticOp {
  /// The window was captured for the still (trace): the `preset`, the
  /// capture's `captureUs` and the still's `stillWidth` and `stillHeight` in
  /// pixels.
  scrimCaptured,

  /// A still was made (trace): the `preset`, `cpuMs` from the capture, and
  /// `glassSource`, whether it is the glass source (the preview's preset
  /// has none).
  scrimStillReady,

  /// The scrim has no still (debug): `why`, `presetNoBlur` (the blur is off,
  /// or a mouse opened a preview with no menu), `noSource` or
  /// `reduceTransparency`.
  scrimStillSkipped,

  /// A press outside or back closed the preview (debug): `by` (`outside`,
  /// `back`) and the preset's `closeOn`.
  scrimDismissed,

  /// The preview was taken away at once (debug).
  scrimCancelled,

  /// The scrim let go of its stills (trace): `stills`, how many.
  scrimDisposed,

  /// The capture threw, or its still could not be made (error): the
  /// `errorType`, `glassSource` as for [scrimStillReady], and the error
  /// itself.
  scrimCaptureFailed,
}
