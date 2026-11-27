import 'package:content_model/content_model.dart';

/// The operations of the diagnostics events the panel shell emits through
/// `ChatDiagnostics.current`.
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum PanelShellOp implements DiagnosticOp {
  /// The host set a page's availability to a new form (debug, category
  /// `capabilities`): the `page` id, the `form` (`available`, `dimmed`,
  /// `hidden`, `replaced`) and, when the panel left the page for it,
  /// `movedTo`, the page selected instead. Never the hint or the text.
  pageAvailability,
}
