import 'dart:convert';

import 'package:content_model/src/diagnostics/chat_diagnostics.dart';
import 'package:content_model/src/diagnostics/chat_event.dart';
import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/link_preview/link_preview.dart';
import 'package:content_model/src/link_preview/link_preview_op.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:content_model/src/rich_text/markdown/rich_text_markdown.dart';
import 'package:content_model/src/rich_text/rich_text.dart';
import 'package:meta/meta.dart';

/// A message's link preview as it travels: the sender's options and, when
/// the sender had the page loaded, the page.
///
/// A receiver that gets no [page] resolves [LinkPreviewOptions.url] itself.
@immutable
final class MessageLinkPreview {
  /// The preview [options], with the [page] when the sender has one.
  const MessageLinkPreview({required this.options, this.page});

  /// The message's choices about the preview.
  final LinkPreviewOptions options;

  /// The page the sender loaded, if any.
  final LinkPreview? page;

  @override
  bool operator ==(Object other) =>
      other is MessageLinkPreview &&
      other.options == options &&
      other.page == page;

  @override
  int get hashCode => Object.hash(options, page);

  @override
  String toString() => 'MessageLinkPreview($options, page: $page)';
}

/// The codec of a message's two link preview fields, `linkPreview` and
/// `invertMedia`, beside the markdown body of ADR 034.
///
/// It reads and writes those two keys of a map the host owns: the message
/// envelope (its id, its body, its other fields) and the draft record
/// `{ body, linkPreview?, invertMedia?, dismissal? }` stay the host's, so a
/// host adds the fields to the map it already sends or stores. Values are
/// JSON-compatible (strings, numbers, booleans, maps and lists).
///
/// ```text
/// linkPreview: {
///   url: String,                      the chosen URL
///   media: 'auto' | 'small' | 'large',
///   removed: bool,
///   page?: {                          the loaded page, when the sender has one
///     url, displayUrl?, type?, siteName?, title?, author?,
///     description?: String,           markdown, as a body is written
///     photo?, media?: descriptor,
///     durationMs?: int, hasLargeMedia?: bool,
///   },
/// }
/// invertMedia: true                   written only when true
/// ```
///
/// A descriptor is `{ key: ContentKey.encoded, ... }` with each other fact
/// written only when it is not the default; its `durationMs` keeps whole
/// milliseconds.
///
/// ## Reading
///
/// Reading never throws. A message without `linkPreview` has no preview,
/// which is how history and older clients read (the absent-field rule).
/// Anything else the reader does not expect becomes the safe value and is
/// reported as a `linkPreview` / `codecTolerated` event naming the field and
/// the kind of problem, never the value:
///
/// | Read | Becomes |
/// | --- | --- |
/// | `linkPreview` not a map, or without a usable `url` | no preview |
/// | an unknown `media` | `auto` |
/// | `page` not a map, or without a usable `url` | no page; the options stay |
/// | a page or descriptor field of the wrong type | left out |
/// | a descriptor whose `key` does not parse | no descriptor |
/// | `invertMedia` not a bool | `false` |
///
/// A missing `media` or `removed` reads as its default without an event.
abstract final class LinkPreviewWire {
  /// The message key of the link preview.
  static const String linkPreviewKey = 'linkPreview';

  /// The message key of the media-above-text flag.
  static const String invertMediaKey = 'invertMedia';

  /// Sets [message]'s two fields to [linkPreview] and [invertMedia].
  ///
  /// A field with nothing to say is removed rather than written empty: no
  /// [linkPreview] removes `linkPreview`, and a false [invertMedia] removes
  /// `invertMedia`. So writing over a map that held the fields before (a
  /// draft rewritten on change) leaves no stale value.
  static void write(
    Map<String, Object?> message, {
    MessageLinkPreview? linkPreview,
    bool invertMedia = false,
  }) {
    switch (linkPreview) {
      case final linkPreview?:
        message[linkPreviewKey] = _encodeLinkPreview(linkPreview);
      case null:
        message.remove(linkPreviewKey);
    }
    if (invertMedia) {
      message[invertMediaKey] = true;
    } else {
      message.remove(invertMediaKey);
    }
  }

  /// The link preview [message] carries, or null when it carries none.
  ///
  /// [scrollId], the message's id, correlates the events of a tolerated
  /// value.
  static MessageLinkPreview? readLinkPreview(
    Map<String, Object?> message, {
    String? scrollId,
  }) => _WireReader(scrollId).linkPreview(message[linkPreviewKey]);

  /// Whether [message] puts its media (a link preview card, an album) above
  /// its text; false when the field is absent.
  static bool readInvertMedia(
    Map<String, Object?> message, {
    String? scrollId,
  }) => _WireReader(
    scrollId,
  ).boolean(message, invertMediaKey, path: invertMediaKey);

  // --- Writing ---

  static Map<String, Object?> _encodeLinkPreview(MessageLinkPreview value) => {
    'url': value.options.url.toString(),
    'media': value.options.media.value,
    'removed': value.options.removed,
    if (value.page case final page?) 'page': _encodePage(page),
  };

  static Map<String, Object?> _encodePage(LinkPreview page) => {
    'url': page.url.toString(),
    'displayUrl': ?page.displayUrl,
    'type': ?page.type,
    'siteName': ?page.siteName,
    'title': ?page.title,
    'author': ?page.author,
    if (page.description.plain.isNotEmpty)
      'description': RichTextMarkdown.encode(page.description),
    if (page.photo case final photo?) 'photo': _encodeDescriptor(photo),
    if (page.media case final media?) 'media': _encodeDescriptor(media),
    'durationMs': ?page.duration?.inMilliseconds,
    'hasLargeMedia': ?page.hasLargeMedia,
  };

  static Map<String, Object?> _encodeDescriptor(ContentDescriptor value) => {
    'key': value.key.encoded,
    if (value.semanticKind != SemanticKind.unknown)
      'semanticKind': value.semanticKind.value,
    if (value.mediaForm != MediaForm.unknown)
      'mediaForm': value.mediaForm.value,
    if (value.animated) 'animated': true,
    if (value.tintable) 'tintable': true,
    if (value.locked) 'locked': true,
    if (value.size case final size?) ...{
      'width': size.width,
      'height': size.height,
    },
    'byteSize': ?value.byteSize,
    'durationMs': ?value.duration?.inMilliseconds,
    if (value.streamable) 'streamable': true,
    'thumbnail': ?value.thumbnail?.value,
    if (value.preview case final preview?)
      'preview': switch (preview) {
        ContentPreview$Raster(:final encoded) => {
          'raster': base64Encode(encoded),
        },
        ContentPreview$Outline(:final pathData, :final viewBox) => {
          'outline': pathData,
          'width': viewBox.width,
          'height': viewBox.height,
        },
      },
    'spokenName': ?value.spokenName,
    'shortcode': ?value.shortcode,
    'pack': ?value.pack?.value,
  };
}

/// What was wrong with a value the reader tolerated, as the event writes it.
enum _Problem { missing, wrongType, unknownValue, unparseable }

/// One read of a message's fields, reporting each tolerated value against
/// the message's [scrollId].
final class _WireReader {
  const _WireReader(this.scrollId);

  final String? scrollId;

  void _tolerate(String path, _Problem problem) => ChatDiagnostics.current.emit(
    ChatEventLevel.debug,
    ChatEventCategory.linkPreview,
    LinkPreviewOp.codecTolerated,
    correlation: ChatCorrelation(scrollId: scrollId),
    fields: () => {'field': path, 'kind': problem.name},
  );

  // --- Fields ---

  /// The map under [json], or null; anything but a map or null is reported.
  Map<Object?, Object?>? map(Object? json, {required String path}) {
    switch (json) {
      case final Map<Object?, Object?> map:
        return map;
      case null:
        return null;
      default:
        _tolerate(path, _Problem.wrongType);
        return null;
    }
  }

  String? string(
    Map<Object?, Object?> map,
    String key, {
    required String path,
  }) {
    switch (map[key]) {
      case final String value:
        return value;
      case null:
        return null;
      default:
        _tolerate(path, _Problem.wrongType);
        return null;
    }
  }

  int? integer(Map<Object?, Object?> map, String key, {required String path}) {
    switch (map[key]) {
      case final int value:
        return value;
      case null:
        return null;
      default:
        _tolerate(path, _Problem.wrongType);
        return null;
    }
  }

  bool? optionalBoolean(
    Map<Object?, Object?> map,
    String key, {
    required String path,
  }) {
    switch (map[key]) {
      case final bool value:
        return value;
      case null:
        return null;
      default:
        _tolerate(path, _Problem.wrongType);
        return null;
    }
  }

  bool boolean(Map<Object?, Object?> map, String key, {required String path}) =>
      optionalBoolean(map, key, path: path) ?? false;

  /// The absolute URL under [key]; reported when missing, since a preview or
  /// a page is nothing without one.
  Uri? url(Map<Object?, Object?> map, String key, {required String path}) {
    if (!map.containsKey(key)) {
      _tolerate(path, _Problem.missing);
      return null;
    }
    final text = string(map, key, path: path);
    if (text == null) return null;
    if (Uri.tryParse(text) case final uri? when uri.hasScheme) return uri;
    _tolerate(path, _Problem.unparseable);
    return null;
  }

  // --- Values ---

  MessageLinkPreview? linkPreview(Object? json) {
    const path = LinkPreviewWire.linkPreviewKey;
    final fields = map(json, path: path);
    if (fields == null) return null;
    final url = this.url(fields, 'url', path: '$path.url');
    if (url == null) return null;
    final mediaValue = string(fields, 'media', path: '$path.media');
    final media = LinkPreviewMedia.fromValue(mediaValue);
    if (mediaValue != null && media.value != mediaValue) {
      _tolerate('$path.media', _Problem.unknownValue);
    }
    return MessageLinkPreview(
      options: LinkPreviewOptions(
        url: url,
        media: media,
        removed: boolean(fields, 'removed', path: '$path.removed'),
      ),
      page: page(fields['page']),
    );
  }

  LinkPreview? page(Object? json) {
    const path = 'page';
    final fields = map(json, path: path);
    if (fields == null) return null;
    final url = this.url(fields, 'url', path: '$path.url');
    if (url == null) return null;
    final durationMs = integer(fields, 'durationMs', path: '$path.durationMs');
    return LinkPreview(
      url: url,
      displayUrl: string(fields, 'displayUrl', path: '$path.displayUrl'),
      type: string(fields, 'type', path: '$path.type'),
      siteName: string(fields, 'siteName', path: '$path.siteName'),
      title: string(fields, 'title', path: '$path.title'),
      author: string(fields, 'author', path: '$path.author'),
      description: switch (string(
        fields,
        'description',
        path: '$path.description',
      )) {
        final markdown? => RichTextMarkdown.decode(markdown),
        null => RichText.empty,
      },
      photo: descriptor(fields['photo'], path: '$path.photo'),
      media: descriptor(fields['media'], path: '$path.media'),
      duration: switch (durationMs) {
        final ms? => Duration(milliseconds: ms),
        null => null,
      },
      hasLargeMedia: optionalBoolean(
        fields,
        'hasLargeMedia',
        path: '$path.hasLargeMedia',
      ),
    );
  }

  ContentDescriptor? descriptor(Object? json, {required String path}) {
    final fields = map(json, path: path);
    if (fields == null) return null;
    final encodedKey = string(fields, 'key', path: '$path.key');
    if (encodedKey == null) {
      if (!fields.containsKey('key')) _tolerate('$path.key', _Problem.missing);
      return null;
    }
    final key = ContentKey.tryParse(encodedKey);
    if (key == null) {
      _tolerate('$path.key', _Problem.unparseable);
      return null;
    }
    final byteSize = integer(fields, 'byteSize', path: '$path.byteSize');
    final durationMs = integer(fields, 'durationMs', path: '$path.durationMs');
    return ContentDescriptor(
      key: key,
      semanticKind: SemanticKind.fromValue(
        string(fields, 'semanticKind', path: '$path.semanticKind'),
      ),
      mediaForm: MediaForm.fromValue(
        string(fields, 'mediaForm', path: '$path.mediaForm'),
      ),
      animated: boolean(fields, 'animated', path: '$path.animated'),
      tintable: boolean(fields, 'tintable', path: '$path.tintable'),
      locked: boolean(fields, 'locked', path: '$path.locked'),
      size: size(fields, path: '$path.size'),
      byteSize: switch (byteSize) {
        final bytes? when bytes < 0 => _unparseable('$path.byteSize'),
        _ => byteSize,
      },
      duration: switch (durationMs) {
        final ms? => Duration(milliseconds: ms),
        null => null,
      },
      streamable: boolean(fields, 'streamable', path: '$path.streamable'),
      thumbnail: switch (string(fields, 'thumbnail', path: '$path.thumbnail')) {
        final ref? => ThumbnailRef(ref),
        null => null,
      },
      preview: preview(fields['preview'], path: '$path.preview'),
      spokenName: string(fields, 'spokenName', path: '$path.spokenName'),
      shortcode: string(fields, 'shortcode', path: '$path.shortcode'),
      pack: switch (string(fields, 'pack', path: '$path.pack')) {
        final id? => PackId(id),
        null => null,
      },
    );
  }

  /// The positive `width` and `height` of [fields], or null.
  /// A [required] size that is absent is reported as missing.
  ContentSize? size(
    Map<Object?, Object?> fields, {
    required String path,
    bool required = false,
  }) {
    final width = integer(fields, 'width', path: path);
    final height = integer(fields, 'height', path: path);
    return switch ((width, height)) {
      (null, null) when required => _tolerated(path, _Problem.missing),
      (null, null) => null,
      (final w?, final h?) when w > 0 && h > 0 => ContentSize(w, h),
      _ => _unparseable(path),
    };
  }

  ContentPreview? preview(Object? json, {required String path}) {
    final fields = map(json, path: path);
    if (fields == null) return null;
    if (string(fields, 'raster', path: '$path.raster') case final raster?) {
      try {
        return ContentPreview.raster(base64Decode(raster));
      } on FormatException {
        return _unparseable('$path.raster');
      }
    }
    if (string(fields, 'outline', path: '$path.outline') case final outline?) {
      return switch (size(fields, path: '$path.size', required: true)) {
        final viewBox? => ContentPreview.outline(outline, viewBox),
        null => null,
      };
    }
    return _unparseable(path);
  }

  T? _unparseable<T>(String path) => _tolerated(path, _Problem.unparseable);

  T? _tolerated<T>(String path, _Problem problem) {
    _tolerate(path, problem);
    return null;
  }
}
