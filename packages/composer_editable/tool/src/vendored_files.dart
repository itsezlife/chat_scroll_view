// The stock files the package vendors and where each lives in the package.
// This table is the one place that knows both sides; the re-vendor tool, the
// divergence report and the tests all read it.

/// One Flutter source file copied into the package.
class VendoredFile {
  const VendoredFile(this.stock, this.fork);

  /// Path under the SDK's `packages/flutter/lib/src/`.
  final String stock;

  /// Path under the package root.
  final String fork;

  /// The directory part of [stock], the base for its relative imports.
  String get stockDir => stock.substring(0, stock.lastIndexOf('/'));

  /// The file name, equal on both sides.
  String get name => stock.substring(stock.lastIndexOf('/') + 1);

  /// Where the baseline keeps this file under `tool/baseline/<version>/`.
  String get baseline => fork.replaceFirst('lib/src/', '');
}

/// Every vendored file. The first five are the files the fork diverges in; the
/// last four differ from stock only in names and imports, but joining the
/// baseline means a stock change to them arrives in the merge instead of going
/// unnoticed.
const List<VendoredFile> vendoredFiles = [
  VendoredFile(
    'widgets/editable_text.dart',
    'lib/src/widget/editable_text.dart',
  ),
  VendoredFile(
    'widgets/text_selection.dart',
    'lib/src/widget/text_selection.dart',
  ),
  VendoredFile(
    'widgets/_web_browser_detection_io.dart',
    'lib/src/widget/_web_browser_detection_io.dart',
  ),
  VendoredFile(
    'widgets/_web_browser_detection_web.dart',
    'lib/src/widget/_web_browser_detection_web.dart',
  ),
  VendoredFile('material/text_field.dart', 'lib/src/material/text_field.dart'),
  VendoredFile(
    'material/text_selection.dart',
    'lib/src/material/text_selection.dart',
  ),
  VendoredFile(
    'material/desktop_text_selection.dart',
    'lib/src/material/desktop_text_selection.dart',
  ),
  VendoredFile(
    'cupertino/text_selection.dart',
    'lib/src/cupertino/text_selection.dart',
  ),
  VendoredFile(
    'cupertino/desktop_text_selection.dart',
    'lib/src/cupertino/desktop_text_selection.dart',
  ),
];
