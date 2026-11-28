import 'package:content_model/content_model.dart';

/// The operations of the diagnostics events the panel presentation emits
/// through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum PanelPresentationOp implements DiagnosticOp {
  /// The keyboard-replacement slot's occupancy hold began or ended (debug,
  /// category `overlay`): the `phase` (`start`, `end`) and the held
  /// `heightPx`.
  occupancyHold,
}
