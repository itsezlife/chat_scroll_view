import 'dart:typed_data';

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

/// An image or a file the user put into an input: from the clipboard, or
/// from a keyboard that inserts images.
///
/// Image data arrives as [PastedMedia.bytes]; a file copied in a file
/// manager arrives as [PastedMedia.file], read from where it is rather than
/// loaded whole.
@immutable
sealed class PastedMedia {
  const PastedMedia();

  /// Image or file data of [mimeType] (`image/png`), named [name] when the
  /// source gave one.
  const factory PastedMedia.bytes(
    Uint8List bytes, {
    required String mimeType,
    String? name,
  }) = PastedMedia$Bytes;

  /// The file at [path], of [mimeType] when known.
  const factory PastedMedia.file(String path, {String? mimeType}) =
      PastedMedia$File;
}

/// Media as data; see [PastedMedia.bytes].
final class PastedMedia$Bytes extends PastedMedia {
  /// Creates media of [bytes].
  const PastedMedia$Bytes(this.bytes, {required this.mimeType, this.name});

  /// The data.
  final Uint8List bytes;

  /// Its type, `image/png` for example.
  final String mimeType;

  /// A name the source gave it, if any.
  final String? name;

  @override
  String toString() => 'PastedMedia.bytes($mimeType, ${bytes.length} bytes)';
}

/// Media as a file on disk; see [PastedMedia.file].
final class PastedMedia$File extends PastedMedia {
  /// Creates media at [path].
  const PastedMedia$File(this.path, {this.mimeType});

  /// Where the file is.
  final String path;

  /// Its type when known.
  final String? mimeType;

  @override
  bool operator ==(Object other) =>
      other is PastedMedia$File &&
      other.path == path &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(path, mimeType);

  @override
  String toString() => 'PastedMedia.file($path)';
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

  /// The images and files the clipboard holds, in order; empty when it holds
  /// none. A paste that finds media hands it to the host to send, as the
  /// reference clients do.
  Future<List<PastedMedia>> readMedia();
}
