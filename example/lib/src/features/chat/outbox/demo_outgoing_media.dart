import 'dart:math';

import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart';

/// Where an outgoing item's picture comes from until the server has it:
/// the media it was picked as (a library asset, a capture) or a file.
@immutable
sealed class DemoOutgoingSource {
  const DemoOutgoingSource._();

  /// The item is the media under [key].
  const factory DemoOutgoingSource.key(MediaKey key) = DemoOutgoingSource$Key;

  /// The item is the file at [path].
  const factory DemoOutgoingSource.file(String path) = DemoOutgoingSource$File;

  /// The source of [encoded], the form [encoded] writes: `key:<media key>`
  /// or `file:<path>`. Throws a [FormatException] for anything else.
  factory DemoOutgoingSource.parse(String encoded) {
    final colon = encoded.indexOf(':');
    final rest = colon < 0 ? '' : encoded.substring(colon + 1);
    return switch (colon < 0 ? encoded : encoded.substring(0, colon)) {
      _keyTag when rest.isNotEmpty => DemoOutgoingSource.key(
        MediaKey.parse(rest),
      ),
      _fileTag when rest.isNotEmpty => DemoOutgoingSource.file(rest),
      _ => throw FormatException('Not an outgoing item source', encoded),
    };
  }

  static const String _keyTag = 'key';
  static const String _fileTag = 'file';

  /// The stable form a payload keeps it in.
  String get encoded;
}

/// [DemoOutgoingSource.key].
final class DemoOutgoingSource$Key extends DemoOutgoingSource {
  /// The media under [key].
  const DemoOutgoingSource$Key(this.key) : super._();

  /// The key the picture is fetched under.
  final MediaKey key;

  @override
  String get encoded => '${DemoOutgoingSource._keyTag}:${key.encoded}';

  @override
  bool operator ==(Object other) =>
      other is DemoOutgoingSource$Key && other.key == key;

  @override
  int get hashCode => Object.hash(DemoOutgoingSource$Key, key);
}

/// [DemoOutgoingSource.file].
final class DemoOutgoingSource$File extends DemoOutgoingSource {
  /// The file at [path].
  const DemoOutgoingSource$File(this.path) : super._();

  /// The file's path. User content: never logged.
  final String path;

  @override
  String get encoded => '${DemoOutgoingSource._fileTag}:$path';

  @override
  bool operator ==(Object other) =>
      other is DemoOutgoingSource$File && other.path == path;

  @override
  int get hashCode => Object.hash(DemoOutgoingSource$File, path);

  // The path is the user's: it stays out of logs.
  @override
  String toString() => 'DemoOutgoingSource\$File(${path.length} chars)';
}

/// The media of the user's outgoing messages before the server has it.
///
/// A media cell reads an item's upload by the media key its content key
/// maps to (`content_assets`' mapping), which is one-to-one only for a
/// `document` key and its `remote` media key; a picked asset's or a
/// capture's own key has no content key at all. So each outgoing item gets
/// a key minted here ([mint]), a `remote` one the chat can name, under
/// which the upload is tracked and the picture is cached; [route] fetches
/// that picture from the item's real source ([know]).
final class DemoOutgoingMedia {
  /// An empty registry.
  DemoOutgoingMedia();

  static const String _prefix = 'local:';

  final Map<MediaKey, DemoOutgoingSource> _$sources = {};

  /// Whether [key] is one [mint] gives.
  static bool isOutgoing(MediaKey key) =>
      key is MediaKey$Remote && key.id.startsWith(_prefix);

  /// A new outgoing item's key.
  MediaKey mint() => MediaKey.remote('$_prefix${_uuid()}');

  /// The item under [key] shows [source]'s picture.
  void know(MediaKey key, DemoOutgoingSource source) => _$sources[key] = source;

  /// A fetcher that serves the outgoing items' pictures from their
  /// sources and hands every other request to [otherwise]. An outgoing key
  /// whose source is not known (an item restored from a journal the
  /// payload of which named none) fails for good: nothing else holds it.
  ContentFetcher route(ContentFetcher otherwise) =>
      _OutgoingRoute(_$sources, otherwise);

  static final Random _$random = Random.secure();

  static String _uuid() {
    final bytes = [for (var i = 0; i < 16; i++) _$random.nextInt(256)];
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

final class _OutgoingRoute implements ContentFetcher {
  _OutgoingRoute(this._sources, this._otherwise);

  final Map<MediaKey, DemoOutgoingSource> _sources;
  final ContentFetcher _otherwise;

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    final key = request.descriptor.key;
    if (!DemoOutgoingMedia.isOutgoing(key)) return _otherwise.fetch(request);
    return switch ((_sources[key], request.part)) {
      (DemoOutgoingSource$Key(key: final source), _) => _otherwise.fetch(
        _withKey(request, source),
      ),
      (DemoOutgoingSource$File(:final path), FetchPart.content) =>
        FetchedContent.file(path),
      (DemoOutgoingSource$File(), FetchPart.thumbnail) =>
        throw const FetchFailure.permanent('a file item has no thumbnail'),
      (null, _) => throw const FetchFailure.permanent(
        'outgoing item not known',
      ),
    };
  }

  static FetchRequest _withKey(FetchRequest request, MediaKey key) {
    final d = request.descriptor;
    return FetchRequest(
      descriptor: MediaDescriptor(
        key: key,
        kind: d.kind,
        animated: d.animated,
        dimensions: d.dimensions,
        byteSize: d.byteSize,
        duration: d.duration,
        thumbnail: d.thumbnail,
        preview: d.preview,
        streamable: d.streamable,
        silentLoop: d.silentLoop,
      ),
      part: request.part,
      priority: request.priority,
      cancellation: request.cancellation,
      onProgress: request.onProgress,
      prefix: request.prefix,
      whole: request.whole,
    );
  }

  // The user's own media is here already: never a download.
  @override
  bool needsDownload(MediaKey key) =>
      !DemoOutgoingMedia.isOutgoing(key) && _otherwise.needsDownload(key);
}
