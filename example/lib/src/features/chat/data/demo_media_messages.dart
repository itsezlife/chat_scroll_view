import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_documents.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_photos.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// What one media item of a [DemoMediaMessage] is: a descriptor, the kind
/// the host gives it, and whether it hides under a spoiler.
typedef DemoMediaPart = ({
  ContentDescriptor descriptor,
  MediaItemKind? kind,
  bool spoiler,
});

/// A media message of the demo chat, before the chat gives it an id: its
/// caption, its items, its link preview and where its media sits.
@immutable
final class DemoMediaMessage {
  /// A message of [parts] under [body], with [linkPreview] and
  /// [invertMedia].
  const DemoMediaMessage({
    this.body = '',
    this.parts = const [],
    this.linkPreview,
    this.invertMedia = false,
  });

  /// The caption, or the text a link preview is of: markdown as the wire
  /// carries it.
  final String body;

  /// The items, in order.
  final List<DemoMediaPart> parts;

  /// The link preview the sender attached: options and, when the sender had
  /// it, the page.
  final MessageLinkPreview? linkPreview;

  /// Whether the caption (or the card) sits above the media (the text).
  final bool invertMedia;

  /// The message with [id] from [sender] at [time].
  ///
  /// The demo issues each item's `MediaItemId` from the message id and the
  /// item's place (`<id>.<n>`), unique in the chat as the ids are; a link
  /// preview's media takes `MediaItemId.linkPreviewOf` in the layout.
  UserChatMessage toMessage({
    required int id,
    required String sender,
    required DateTime time,
  }) {
    final payload = <String, Object?>{};
    LinkPreviewWire.write(
      payload,
      linkPreview: linkPreview,
      invertMedia: invertMedia,
    );
    return UserChatMessage(
      id: id,
      sender: sender,
      createdAt: time,
      updatedAt: time,
      // Receive fallback — once, when the message model is made (ADR 017).
      content: ChatBodyMarkdown.received(body),
      media: [
        for (final (index, part) in parts.indexed)
          MediaItem(
            id: MediaItemId('$id.$index'),
            descriptor: part.descriptor,
            kind: part.kind,
            spoiler: part.spoiler,
          ),
      ],
      payload: payload,
    );
  }
}

/// The media messages the demo chat ends with: a photo, a video, a GIF,
/// albums of two to ten, a mixed list, file stacks with and without
/// thumbnails, spoilers, captions above and below, and link previews small,
/// large, above the text and looked up by the receiver.
abstract final class DemoMediaMessages {
  static DemoMediaPart _photo(DemoPhoto photo, {bool spoiler = false}) =>
      (descriptor: photo.descriptor, kind: null, spoiler: spoiler);

  // A photo sent as a file: a row with its picture as the thumbnail.
  static DemoMediaPart _photoFile(DemoPhoto photo) =>
      (descriptor: photo.descriptor, kind: MediaItemKind.file, spoiler: false);

  // A clip of the video pack sent as a video: it plays inline, muted.
  static DemoMediaPart _video(VideoPackItem clip, {bool spoiler = false}) => (
    descriptor: clip.descriptor.copyWith(
      fileName: '${clip.name}.mp4',
      mimeType: 'video/mp4',
      duration: const Duration(seconds: 2),
      byteSize: _byteSizes[clip.name],
    ),
    kind: MediaItemKind.video,
    spoiler: spoiler,
  );

  // A GIF of the video pack.
  static DemoMediaPart _gif(VideoPackItem gif) => (
    descriptor: gif.descriptor.copyWith(
      fileName: '${gif.name}.gif',
      mimeType: 'image/gif',
      byteSize: _byteSizes[gif.name],
    ),
    kind: MediaItemKind.animation,
    spoiler: false,
  );

  // A bundled document as a file row.
  static DemoMediaPart _document(String id) {
    final document = DemoDocuments.all.singleWhere((d) => d.id == id);
    return (
      descriptor: document.descriptor.copyWith(
        fileName: document.name,
        mimeType: document.mimeType,
        byteSize: document.byteSize,
      ),
      kind: MediaItemKind.file,
      spoiler: false,
    );
  }

  // The bundled files' sizes, as a backend would say them.
  static const Map<String, int> _byteSizes = {
    'gradient': 6485,
    'wave': 5677,
    'tunnel': 5329,
    'bars': 42616,
  };

  static final _gradient = VideoStickerPack.clips.firstWhere(
    (clip) => clip.name == 'gradient',
  );
  static final _wave = VideoStickerPack.clips.firstWhere(
    (clip) => clip.name == 'wave',
  );
  static final _tunnel = VideoStickerPack.clips.firstWhere(
    (clip) => clip.name == 'tunnel',
  );
  static final _bars = VideoStickerPack.gifs.firstWhere(
    (gif) => gif.name == 'bars',
  );

  static final _dartPage = LinkPreview(
    url: Uri.parse('https://dart.dev/overview'),
    displayUrl: 'dart.dev',
    type: 'article',
    siteName: 'Dart',
    title: 'Dart overview',
    description: const RichText.plain(
      'A client-optimized language for fast apps on any platform.',
    ),
    photo: DemoPhotos.pebble.descriptor,
  );

  static final _flutterPage = LinkPreview(
    url: Uri.parse('https://flutter.dev/showcase'),
    displayUrl: 'flutter.dev',
    type: 'website',
    siteName: 'Flutter',
    title: 'Showcase',
    description: const RichText.plain(
      'Apps built with Flutter, on mobile, web and desktop.',
    ),
    photo: DemoPhotos.harbour.descriptor,
    hasLargeMedia: true,
  );

  /// The messages, in the order the chat shows them.
  static final List<DemoMediaMessage> all = List.unmodifiable([
    DemoMediaMessage(parts: [_photo(DemoPhotos.harbour)]),
    DemoMediaMessage(
      body: 'The tower at noon, caption below.',
      parts: [_photo(DemoPhotos.tower)],
    ),
    DemoMediaMessage(
      body: 'Caption above the picture.',
      parts: [_photo(DemoPhotos.skyline)],
      invertMedia: true,
    ),
    DemoMediaMessage(parts: [_video(_gradient)]),
    DemoMediaMessage(parts: [_gif(_bars)]),
    DemoMediaMessage(
      parts: [_photo(DemoPhotos.cliff), _photo(DemoPhotos.meadow)],
    ),
    DemoMediaMessage(
      body: 'Three of them, one a video.',
      parts: [
        _photo(DemoPhotos.dunes),
        _video(_wave),
        _photo(DemoPhotos.lagoon),
      ],
    ),
    DemoMediaMessage(
      parts: [
        _photo(DemoPhotos.harbour),
        _photo(DemoPhotos.cliff),
        _photo(DemoPhotos.meadow),
        _photo(DemoPhotos.skyline),
      ],
    ),
    DemoMediaMessage(
      body: 'Ten at once.',
      parts: [
        for (final photo in DemoPhotos.all) _photo(photo),
        _video(_tunnel),
        _video(_gradient),
      ],
    ),
    DemoMediaMessage(
      body: 'Two pictures and the notes that go with them.',
      parts: [
        _photo(DemoPhotos.dunes),
        _photo(DemoPhotos.lagoon),
        _document('notes'),
      ],
    ),
    DemoMediaMessage(
      parts: [
        _document('notes'),
        _document('diagram'),
        _photoFile(DemoPhotos.meadow),
      ],
    ),
    DemoMediaMessage(
      body: 'The notes, as a file.',
      parts: [_document('notes')],
    ),
    DemoMediaMessage(
      body: 'Tap to reveal.',
      parts: [_photo(DemoPhotos.lagoon, spoiler: true)],
    ),
    DemoMediaMessage(
      parts: [
        _photo(DemoPhotos.meadow),
        _photo(DemoPhotos.dunes, spoiler: true),
        _video(_wave, spoiler: true),
      ],
    ),
    DemoMediaMessage(
      body: 'Read https://dart.dev/overview',
      linkPreview: MessageLinkPreview(
        options: LinkPreviewOptions(url: _dartPage.url),
        page: _dartPage,
      ),
    ),
    DemoMediaMessage(
      body: 'See https://flutter.dev/showcase',
      linkPreview: MessageLinkPreview(
        options: LinkPreviewOptions(
          url: _flutterPage.url,
          media: LinkPreviewMedia.large,
        ),
        page: _flutterPage,
      ),
    ),
    DemoMediaMessage(
      body: 'The card above the text: https://dart.dev/overview',
      linkPreview: MessageLinkPreview(
        options: LinkPreviewOptions(url: _dartPage.url),
        page: _dartPage,
      ),
      invertMedia: true,
    ),
    // The sender's options without a page: the receiver looks it up.
    DemoMediaMessage(
      body: 'Looked up here: https://pub.dev',
      linkPreview: MessageLinkPreview(
        options: LinkPreviewOptions(url: Uri.parse('https://pub.dev')),
      ),
    ),
  ]);
}
