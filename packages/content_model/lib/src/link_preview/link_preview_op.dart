import 'package:content_model/src/diagnostics/chat_event.dart';

/// The operations of the `linkPreview` diagnostics events this package
/// emits through `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them. The composer's link preview events
/// (resolving, dismissal, options) are in its own operation enum, under the
/// same category.
enum LinkPreviewOp implements DiagnosticOp {
  /// `LinkPreviewWire` read a value it did not expect and went on with a
  /// default (debug): the field's path and the kind of problem (`missing`,
  /// `wrongType`, `unknownValue`, `unparseable`). Never the value itself.
  codecTolerated,
}
