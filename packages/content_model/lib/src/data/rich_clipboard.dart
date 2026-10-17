import 'package:content_model/src/rich_text/rich_text.dart';
import 'package:meta/meta.dart';

/// What a clipboard holds as text: the plain text any app reads, and the
/// [RichText] when the clipboard also held a rich form.
@immutable
final class ClipboardText {
  /// Creates the clipboard's text [plain], with its [rich] form when there
  /// was one.
  const ClipboardText(this.plain, {this.rich});

  /// The plain text on the clipboard, as another app would paste it.
  final String plain;

  /// The text with its entities, read from a rich form (ours, or another
  /// app's formatting); null when the clipboard held plain text only.
  final RichText? rich;

  /// What a paste inserts: [rich] when there is one, else [plain].
  RichText get richOrPlain => rich ?? RichText.plain(plain);

  @override
  bool operator ==(Object other) =>
      other is ClipboardText && other.plain == plain && other.rich == rich;

  @override
  int get hashCode => Object.hash(plain, rich);

  @override
  String toString() => 'ClipboardText(${rich == null ? 'plain' : 'rich'})';
}

/// The system clipboard, for text that keeps its entities.
///
/// A copy puts two forms of one [RichText] on the clipboard: its plain text,
/// which every app can paste (inline content as its alternative text, links as
/// their visible text), and a rich form that keeps every entity, which a paste
/// into this app reads back. Other apps' formatting comes back through the
/// rich form too, as far as entities can say it.
///
/// The only way packages reach the clipboard: the adapter that owns the
/// platform code lives in its own package, and presentation packages are
/// handed this seam.
///
/// ## Failure
///
/// A future fails when the platform clipboard cannot be reached, written or
/// read; the clipboard is then as it was. A caller pasting may fall back to
/// what the platform's own paste gives.
abstract interface class RichClipboard {
  /// Puts [text] on the clipboard, replacing what was there.
  Future<void> write(RichText text);

  /// What the clipboard holds as text, or null when it holds no text.
  Future<ClipboardText?> read();
}
