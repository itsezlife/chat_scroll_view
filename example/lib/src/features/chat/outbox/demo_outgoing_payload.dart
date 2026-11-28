import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outgoing_media.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart';

/// The demo's message model as the outbox keeps it in a publish job: who
/// sends, the markdown body as the composer encoded it, and the rest of the
/// message the bubbles read (its [linkPreview] and [invertMedia]).
///
/// Typed through and through: the wire form of the link preview fields
/// (`LinkPreviewWire`'s) is the codec's and the boundaries' ([extras],
/// [DemoOutgoingPayload.fromWire]), never a map held here.
///
/// A media send's body is its caption; [items] say what each item is, so
/// the row shows it as media before the server has it, after a restart
/// too. The items' bytes are the job's.
@immutable
final class DemoOutgoingPayload {
  /// A payload of [body] from [sender], with its [linkPreview],
  /// [invertMedia] and [items].
  const DemoOutgoingPayload({
    required this.sender,
    required this.body,
    this.linkPreview,
    this.invertMedia = false,
    this.items = const [],
  });

  /// A payload whose link preview fields come in their wire form
  /// ([extras], a message map in `LinkPreviewWire`'s form), as the chat's
  /// screen and the server hand them; other keys of the map are not the
  /// payload's.
  factory DemoOutgoingPayload.fromWire({
    required String sender,
    required String body,
    Map<String, Object?> extras = const {},
    List<DemoOutgoingItem> items = const [],
  }) => DemoOutgoingPayload(
    sender: sender,
    body: body,
    linkPreview: LinkPreviewWire.readLinkPreview(extras),
    invertMedia: LinkPreviewWire.readInvertMedia(extras),
    items: items,
  );

  /// Who sends it: the demo's signed-in user.
  final String sender;

  /// The markdown body, as stored.
  final String body;

  /// The message's link preview, if it has one.
  final MessageLinkPreview? linkPreview;

  /// Whether the message puts its media above its text.
  final bool invertMedia;

  /// The link preview fields in their wire form, for a row's payload and
  /// the server: empty when there is nothing to say.
  Map<String, Object?> get extras {
    final wire = <String, Object?>{};
    LinkPreviewWire.write(
      wire,
      linkPreview: linkPreview,
      invertMedia: invertMedia,
    );
    return wire;
  }

  /// What each media item of the message is, in the send's order.
  final List<DemoOutgoingItem> items;

  @override
  bool operator ==(Object other) =>
      other is DemoOutgoingPayload &&
      other.sender == sender &&
      other.body == body &&
      other.linkPreview == linkPreview &&
      other.invertMedia == invertMedia &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(
    sender,
    body,
    linkPreview,
    invertMedia,
    Object.hashAll(items),
  );

  // The body is user content: it stays out of logs.
  @override
  String toString() =>
      'DemoOutgoingPayload(${body.length} chars, '
      'link preview ${linkPreview != null}, ${items.length} items)';
}

/// What one media item of an outgoing message is, as the picker knew it:
/// enough for the row to show it as media until the server has it.
@immutable
final class DemoOutgoingItem {
  /// The item cached and uploaded under [mediaKey] (a key
  /// [DemoOutgoingMedia.mint] gave), shown as [kind], its picture from
  /// [source].
  const DemoOutgoingItem({
    required this.mediaKey,
    required this.kind,
    this.width,
    this.height,
    this.byteSize,
    this.duration,
    this.fileName,
    this.source,
  });

  /// The key the item's upload is tracked and its picture cached under.
  final MediaKey mediaKey;

  /// What the item is shown as.
  final MediaItemKind kind;

  /// The pixel width, when known.
  final int? width;

  /// The pixel height, when known.
  final int? height;

  /// The file's size in bytes, when known.
  final int? byteSize;

  /// The running time, when known.
  final Duration? duration;

  /// The file's name. User content: never logged.
  final String? fileName;

  /// Where the item's picture comes from; null where nothing on the device
  /// holds it (a web blob).
  final DemoOutgoingSource? source;

  /// The item as the chat's media cells take it, as [id] and under
  /// [localKey] (the outbox's).
  MediaItem toMediaItem({
    required MediaItemId id,
    required ContentKey localKey,
  }) => MediaItem(
    id: id,
    kind: kind,
    descriptor: ContentDescriptor(
      key: localKey,
      mediaForm: switch (kind) {
        MediaItemKind.video => MediaForm.video,
        MediaItemKind.animation => MediaForm.animatedImage,
        MediaItemKind.photo => MediaForm.still,
        MediaItemKind.file => MediaForm.unknown,
        // `MediaItemKind` is an open set: a custom kind, which the demo's
        // picker never makes, has no form of its own.
        MediaItemKind() => MediaForm.unknown,
      },
      animated: kind == MediaItemKind.animation,
      size: switch ((width, height)) {
        (final w?, final h?) when w > 0 && h > 0 => ContentSize(w, h),
        _ => null,
      },
      byteSize: byteSize,
      duration: duration,
      fileName: fileName,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is DemoOutgoingItem &&
      other.mediaKey == mediaKey &&
      other.kind == kind &&
      other.width == width &&
      other.height == height &&
      other.byteSize == byteSize &&
      other.duration == duration &&
      other.fileName == fileName &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
    mediaKey,
    kind,
    width,
    height,
    byteSize,
    duration,
    fileName,
    source,
  );

  @override
  String toString() => 'DemoOutgoingItem(${mediaKey.encoded}, ${kind.value})';
}

/// [DemoOutgoingPayload] to the bytes a publish job journals, and back.
///
/// ## Format
///
/// UTF-8 JSON, one object:
///
/// | Key | Value |
/// |---|---|
/// | `v` | the format version, `1` |
/// | `sender` | [DemoOutgoingPayload.sender], a string |
/// | `body` | [DemoOutgoingPayload.body], a string |
/// | `extras` | [DemoOutgoingPayload.linkPreview] and [DemoOutgoingPayload.invertMedia] in `LinkPreviewWire`'s form, an object; left out when both say nothing |
/// | `items` | [DemoOutgoingPayload.items], a list of objects; left out when empty, and read as none when absent |
///
/// Each item:
///
/// | Key | Value |
/// |---|---|
/// | `key` | [DemoOutgoingItem.mediaKey]'s stable form, a string |
/// | `kind` | [DemoOutgoingItem.kind]'s value, a string |
/// | `w`, `h` | the pixel size, integers; each left out when unknown |
/// | `bytes` | the byte size, an integer; left out when unknown |
/// | `ms` | the duration in milliseconds, an integer; left out when unknown |
/// | `name` | the file name, a string; left out when unknown |
/// | `source` | [DemoOutgoingSource.encoded], a string; left out when none |
///
/// The bytes outlive the app (the transfer journal keeps them across a
/// restart), so a decode of another version, of a value of the wrong type
/// or of a missing field throws a [FormatException] naming it: the outbox
/// then reads the message as undecodable.
final class DemoOutgoingPayloadCodec
    extends OutgoingPayloadCodec<DemoOutgoingPayload> {
  /// The codec.
  const DemoOutgoingPayloadCodec();

  /// The version every payload written carries.
  static const int version = 1;

  @override
  Converter<DemoOutgoingPayload, Uint8List> get encoder => const _Encoder();

  @override
  Converter<Uint8List, DemoOutgoingPayload> get decoder => const _Decoder();
}

abstract final class _Key {
  static const String version = 'v';
  static const String sender = 'sender';
  static const String body = 'body';
  static const String extras = 'extras';
  static const String items = 'items';
}

abstract final class _ItemKey {
  static const String key = 'key';
  static const String kind = 'kind';
  static const String width = 'w';
  static const String height = 'h';
  static const String byteSize = 'bytes';
  static const String duration = 'ms';
  static const String name = 'name';
  static const String source = 'source';
}

final class _Encoder extends Converter<DemoOutgoingPayload, Uint8List> {
  const _Encoder();

  @override
  Uint8List convert(DemoOutgoingPayload input) => utf8.encode(
    jsonEncode({
      _Key.version: DemoOutgoingPayloadCodec.version,
      _Key.sender: input.sender,
      _Key.body: input.body,
      if (input.extras case final extras when extras.isNotEmpty)
        _Key.extras: extras,
      if (input.items.isNotEmpty)
        _Key.items: [for (final item in input.items) _item(item)],
    }),
  );

  static Map<String, Object?> _item(DemoOutgoingItem item) => {
    _ItemKey.key: item.mediaKey.encoded,
    _ItemKey.kind: item.kind.value,
    _ItemKey.width: ?item.width,
    _ItemKey.height: ?item.height,
    _ItemKey.byteSize: ?item.byteSize,
    _ItemKey.duration: ?item.duration?.inMilliseconds,
    _ItemKey.name: ?item.fileName,
    _ItemKey.source: ?item.source?.encoded,
  };
}

final class _Decoder extends Converter<Uint8List, DemoOutgoingPayload> {
  const _Decoder();

  @override
  DemoOutgoingPayload convert(Uint8List input) {
    final map = switch (jsonDecode(utf8.decode(input))) {
      final Map<String, Object?> map => map,
      _ => throw const FormatException('A payload is a JSON object'),
    };
    if (map[_Key.version] != DemoOutgoingPayloadCodec.version) {
      throw FormatException(
        'Unknown payload version "${_Key.version}": ${map[_Key.version]}',
      );
    }
    return DemoOutgoingPayload.fromWire(
      sender: _string(map, _Key.sender),
      body: _string(map, _Key.body),
      extras: switch (map[_Key.extras]) {
        null => const {},
        final Map<String, Object?> extras => extras,
        _ => throw const FormatException(
          'Payload field "${_Key.extras}" is not an object',
        ),
      },
      items: switch (map[_Key.items]) {
        null => const [],
        final List<Object?> items => [
          for (final (index, item) in items.indexed) _item(item, index),
        ],
        _ => throw const FormatException(
          'Payload field "${_Key.items}" is not a list',
        ),
      },
    );
  }

  // A value whose own parse fails names the field it was read from.
  static T _parsed<T>(T Function() parse, int index, String key) {
    try {
      return parse();
    } on FormatException catch (error) {
      throw FormatException(
        'Payload item $index "$key" is not readable: ${error.message}',
      );
    }
  }

  static DemoOutgoingItem _item(Object? value, int index) {
    final map = switch (value) {
      final Map<String, Object?> map => map,
      _ => throw FormatException('Payload item $index is not an object'),
    };
    String text(String key) => switch (map[key]) {
      final String value => value,
      null => throw FormatException('Payload item $index has no "$key"'),
      _ => throw FormatException('Payload item $index "$key" is not a string'),
    };
    int? integer(String key) => switch (map[key]) {
      null => null,
      final int value => value,
      _ => throw FormatException('Payload item $index "$key" is not an int'),
    };
    String? optionalText(String key) => switch (map[key]) {
      null => null,
      final String value => value,
      _ => throw FormatException('Payload item $index "$key" is not a string'),
    };
    return DemoOutgoingItem(
      mediaKey: _parsed(
        () => MediaKey.parse(text(_ItemKey.key)),
        index,
        _ItemKey.key,
      ),
      kind: MediaItemKind.fromValue(text(_ItemKey.kind)),
      width: integer(_ItemKey.width),
      height: integer(_ItemKey.height),
      byteSize: integer(_ItemKey.byteSize),
      duration: switch (integer(_ItemKey.duration)) {
        final ms? => Duration(milliseconds: ms),
        null => null,
      },
      fileName: optionalText(_ItemKey.name),
      source: switch (optionalText(_ItemKey.source)) {
        final source? => _parsed(
          () => DemoOutgoingSource.parse(source),
          index,
          _ItemKey.source,
        ),
        null => null,
      },
    );
  }

  static String _string(Map<String, Object?> map, String key) =>
      switch (map[key]) {
        final String value => value,
        null => throw FormatException('Payload field "$key" is missing'),
        _ => throw FormatException('Payload field "$key" is not a string'),
      };
}
