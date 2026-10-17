import 'package:content_model/content_model.dart';

/// An in-memory [RichClipboard] for tests.
///
/// Honours the whole seam contract. [putPlainText] stands in for another app
/// copying plain text; set [failure] to simulate a clipboard that cannot be
/// reached: every call then fails with it and changes nothing.
final class FakeRichClipboard implements RichClipboard {
  ClipboardText? _held;

  /// When non-null, every call fails with this exception and changes nothing.
  Exception? failure;

  /// How many [write] calls succeeded.
  int writeCount = 0;

  /// Puts [text] on the clipboard as plain text only, as an app with no rich
  /// form would.
  void putPlainText(String text) => _held = ClipboardText(text);

  @override
  Future<void> write(RichText text) async {
    if (failure case final failure?) throw failure;
    _held = ClipboardText(text.plain, rich: text);
    writeCount++;
  }

  @override
  Future<ClipboardText?> read() async {
    if (failure case final failure?) throw failure;
    return _held;
  }
}
