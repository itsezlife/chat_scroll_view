import 'package:content_model/content_model.dart';

/// The operations of the `media` diagnostics events the message media state
/// emits through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum MediaStateOp implements DiagnosticOp {
  /// A cell found no `MessageMediaStateScope` above it and keeps its own
  /// state (debug).
  stateScopeMissing,
}
