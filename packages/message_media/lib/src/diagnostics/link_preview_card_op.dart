import 'package:content_model/content_model.dart';

/// The operations of the `linkPreview` diagnostics events this package
/// emits through `ChatDiagnostics.current` (the card's own; the composer's
/// and the codec's are their packages').
///
/// Closed: an operation is added here with the path that emits it. Names are
/// stable, since logs filter by them.
enum LinkPreviewCardOp implements DiagnosticOp {
  /// A card was shown for a page (debug): its media `size` (`small`,
  /// `large`, `none`), the `widthRule` and the `appear` form. Never the
  /// page's URL, title or text.
  cardShown,
}
