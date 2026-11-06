import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// One item of the [VideoStickerPack]: a video-coded file in the app bundle,
/// a WebM sticker, an MP4 clip or a GIF.
@immutable
final class VideoPackItem implements BundledItem {
  const VideoPackItem._(
    this.name,
    this.spokenName, {
    required this.extension,
    required this.kind,
    required int side,
  }) : _side = side;

  /// The file's name, without its extension.
  final String name;

  /// The name read aloud for it.
  final String spokenName;

  /// The file's extension, without the dot: `webm`, `mp4` or `gif`.
  final String extension;

  /// What it is to the user: a sticker (WebM), or a gif (an MP4 clip or a GIF
  /// file, both "a short loop sent as a message").
  final SemanticKind kind;

  final int _side;

  /// Its content identity: a document key under the pack's own prefix, so its
  /// cache entry and recents slot never meet another pack's.
  @override
  ContentKey get key =>
      ContentKey.document('${VideoStickerPack._keyPrefix}$name');

  /// What the pipeline needs to make it. The decoder registered for
  /// [MediaForm.video] plays it; without one it keeps its placeholder.
  @override
  ContentDescriptor get descriptor => ContentDescriptor(
    key: key,
    semanticKind: kind,
    mediaForm: MediaForm.video,
    animated: true,
    size: ContentSize(_side, _side),
    spokenName: spokenName,
  );

  @override
  String get assetPath => 'assets/video_stickers/$name.$extension';
}

/// The demo's pack of video-coded content, generated for it with FFmpeg from
/// synthetic sources (`assets/video_stickers/README.md` holds the commands):
/// three VP9 WebM stickers with alpha, two silent H.264 MP4 clips and two
/// tiny GIFs.
///
/// It stands in for content a real host fetches from its backend, like the
/// other bundled packs: [source] publishes the pack as a collection,
/// [descriptors] are what the host tells its asset pipeline, and
/// `BundledPacks` reads [VideoPackItem.assetPath] from the bundle. Playing it
/// needs the native video library; without one the items keep their
/// placeholder.
abstract final class VideoStickerPack {
  /// The collection the pack is listed as.
  static const CollectionId id = CollectionId.set('demo_video');

  /// The pack's title.
  static const String title = 'Demo video stickers';

  static const String _keyPrefix = 'demo-video:';

  /// The WebM stickers, 512 x 512 with alpha. Each has a file in
  /// `assets/video_stickers/`; the lists are kept by hand.
  static const List<VideoPackItem> stickers = [
    VideoPackItem._(
      'orbit',
      'an orbiting ball',
      extension: 'webm',
      kind: SemanticKind.sticker,
      side: 512,
    ),
    VideoPackItem._(
      'pulse',
      'a pulsing ring',
      extension: 'webm',
      kind: SemanticKind.sticker,
      side: 512,
    ),
    VideoPackItem._(
      'slide',
      'a sliding square',
      extension: 'webm',
      kind: SemanticKind.sticker,
      side: 512,
    ),
  ];

  /// The MP4 clips, 256 x 256, silent.
  static const List<VideoPackItem> clips = [
    VideoPackItem._(
      'gradient',
      'a drifting gradient',
      extension: 'mp4',
      kind: SemanticKind.gif,
      side: 256,
    ),
    VideoPackItem._(
      'spiral',
      'a turning spiral',
      extension: 'mp4',
      kind: SemanticKind.gif,
      side: 256,
    ),
  ];

  /// The GIFs, 128 x 128.
  static const List<VideoPackItem> gifs = [
    VideoPackItem._(
      'bars',
      'a test pattern',
      extension: 'gif',
      kind: SemanticKind.gif,
      side: 128,
    ),
    VideoPackItem._(
      'plasma',
      'a colour plasma',
      extension: 'gif',
      kind: SemanticKind.gif,
      side: 128,
    ),
  ];

  /// Every item, in the order the pack shows them.
  static const List<VideoPackItem> items = [...stickers, ...clips, ...gifs];

  static final Map<ContentKey, VideoPackItem> _byKey = {
    for (final item in items) item.key: item,
  };

  /// The item of [key], or null for content that is not the pack's.
  static VideoPackItem? of(ContentKey key) => _byKey[key];

  /// The descriptor of every item, for the host's asset pipeline.
  static Iterable<ContentDescriptor> get descriptors =>
      items.map((item) => item.descriptor);

  /// A source that lists the pack, loaded from the start.
  static CollectionSource source() =>
      BundledPackSource(id: id, title: title, items: items);
}
