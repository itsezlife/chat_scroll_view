import 'package:attach_model/attach_model.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The host's answer for one attach item of a send: the keys it is cached
/// under and where its bytes come from, what the outbox needs to make the
/// item a publish item.
///
/// The attach model names an item's origin by plain values (a library
/// asset id, a path, a blob handle), and only the host's media layer turns
/// those into a preparation input or a prepared file, so the outbox asks
/// the host instead of guessing.
@immutable
final class OutgoingSendItem {
  /// An item cached under [localKey] and [mediaKey], its bytes from
  /// [source].
  const OutgoingSendItem({
    required this.localKey,
    required this.mediaKey,
    required this.source,
    this.fingerprint,
    this.fileName,
  });

  /// The content key the item's local content is cached under: what the
  /// chat's media cells read its upload state by.
  final ContentKey localKey;

  /// The same content as the media cache keys it, the host's mapping of
  /// [localKey] (the content assets' key mapping): what the publish item
  /// carries.
  final MediaKey mediaKey;

  /// Where the item's bytes come from: a preparation input with its intent,
  /// a prepared file, or `remote` for content the server already has.
  final PublishSource source;

  /// The host's value for the item's content that the engine's reuse table
  /// knows a source by; null for the file's own path, size and time.
  final String? fingerprint;

  /// The file's name for the remote end, when the host gives one. User
  /// content: never logged.
  final String? fileName;

  @override
  bool operator ==(Object other) =>
      other is OutgoingSendItem &&
      other.localKey == localKey &&
      other.mediaKey == mediaKey &&
      other.source == source &&
      other.fingerprint == fingerprint &&
      other.fileName == fileName;

  @override
  int get hashCode =>
      Object.hash(localKey, mediaKey, source, fingerprint, fileName);

  @override
  String toString() => 'OutgoingSendItem($source)';
}

/// The host's [OutgoingSendItem] for [item], sent in [form]; the outbox
/// calls it for each item of a planned send it accepts, in order.
typedef OutgoingSendItemResolver =
    OutgoingSendItem Function(AttachItem item, SendForm form);
