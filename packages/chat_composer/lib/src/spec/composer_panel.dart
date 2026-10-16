import 'package:flutter/widgets.dart';

/// Names which panel occupies the input row: the text field, a recording
/// surface, a recorded-message preview, a "join" or "restricted" notice.
///
/// An open set, like [ComposerQueryKind]: the composer ships only [text] and
/// leaves every other panel to the host, which names it here and builds it in
/// the [ComposerPanelResolver].
extension type const ComposerPanelId(String value) {
  /// The default panel: the entity-aware text field.
  static const ComposerPanelId text = ComposerPanelId('text');
}

/// Builds the widget for a panel other than [ComposerPanelId.text].
///
/// Returns null for an id the host does not know; the composer then asserts
/// in debug builds and shows an empty row. The widget fills the row between
/// the actions and may be any height at or above the island height: the
/// island animates to it.
typedef ComposerPanelResolver =
    Widget? Function(BuildContext context, ComposerPanelId panel);
