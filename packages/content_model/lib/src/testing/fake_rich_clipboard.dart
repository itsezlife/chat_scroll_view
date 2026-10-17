import 'package:content_model/content_model.dart';

/// An in-memory [RichClipboard] for tests.
///
/// Honours the whole seam contract. [putPlainText] stands in for another app
/// copying plain text, [performCopy] and [performPaste] for a browser's own
/// commands on an attached field; set [failure] to simulate a clipboard that
/// cannot be reached: every call then fails with it and changes nothing.
final class FakeRichClipboard implements RichClipboard {
  ClipboardText? _held;
  List<PastedMedia> _media = const [];

  /// When non-null, every call fails with this exception and changes nothing.
  Exception? failure;

  /// How many [write] calls succeeded.
  int writeCount = 0;

  /// Puts [text] on the clipboard as plain text only, as an app with no rich
  /// form would.
  void putPlainText(String text) {
    _held = ClipboardText(text);
    _media = const [];
  }

  /// Puts [media] on the clipboard, as copying an image or a file in another
  /// app does, with the plain [text] some apps put next to it (an office
  /// app's copied range comes with a picture of it).
  void putMedia(List<PastedMedia> media, {String? text}) {
    _held = text == null ? null : ClipboardText(text);
    _media = List.unmodifiable(media);
  }

  final List<RichClipboardField> _fields = [];

  /// Performs a copy, or a cut, as a browser does for the focused text field
  /// it was [attach]ed for: the field's selection goes on the clipboard.
  /// False when no attached field has focus or its selection is empty.
  bool performCopy({bool cut = false}) {
    for (final field in _fields) {
      if (!field.hasFocus) continue;
      final text = cut ? field.cutSelection() : field.copySelection();
      if (text == null) return false;
      _held = ClipboardText(text.plain, rich: text);
      _media = const [];
      return true;
    }
    return false;
  }

  /// Performs a paste, as a browser does for the focused text field it was
  /// [attach]ed for: the field is handed what the clipboard holds. False when
  /// no attached field has focus.
  bool performPaste() {
    for (final field in _fields) {
      if (!field.hasFocus) continue;
      field.paste(ClipboardContents(text: _held, media: _media));
      return true;
    }
    return false;
  }

  @override
  void Function() attach(RichClipboardField field) {
    _fields.add(field);
    return () => _fields.remove(field);
  }

  @override
  Future<void> write(RichText text) async {
    if (failure case final failure?) throw failure;
    _held = ClipboardText(text.plain, rich: text);
    _media = const [];
    writeCount++;
  }

  @override
  Future<ClipboardText?> read() async {
    if (failure case final failure?) throw failure;
    return _held;
  }

  @override
  Future<ClipboardContents> readWithMedia() async {
    if (failure case final failure?) throw failure;
    return ClipboardContents(text: _held, media: _media);
  }
}
