import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// One clip of the [FrameCounterPack]: a GIF, a WebP or an MP4 at one rate.
@immutable
final class FrameCounterItem implements BundledItem {
  const FrameCounterItem._(this.fps, this.extension);

  /// Frames a second of the clip.
  final int fps;

  /// The file's extension, without the dot: `gif`, `webp` or `mp4`.
  final String extension;

  @override
  ContentKey get key =>
      ContentKey.document('${FrameCounterPack._keyPrefix}$extension-$fps');

  /// A GIF or a WebP is played by the engine's image codec, an MP4 by the
  /// video decoder: the two paths a clip in a chat or on the GIF page takes.
  @override
  ContentDescriptor get descriptor => ContentDescriptor(
    key: key,
    semanticKind: SemanticKind.gif,
    mediaForm: extension == 'mp4' ? MediaForm.video : MediaForm.animatedImage,
    animated: true,
    size: const ContentSize(192, 144),
    spokenName: 'frame counter, $extension at $fps frames a second',
  );

  @override
  String get assetPath => 'assets/frame_counter/counter_${fps}fps.$extension';
}

/// The frame counter clips: each frame shows its index as a number and in a
/// binary bar, so a screen recording of a GIF scrolled off and back can be
/// read frame by frame (`tool/frame_counter.dart read`). The same tool makes
/// them (`make`), and its header has the frame's layout.
///
/// A GIF, a WebP and an MP4 at 10, 15 and 25 fps, generated from a synthetic
/// source (no third-party artwork). The showcase chat shows them after a
/// "Frame counter" line, and the panel's GIF page lists them first in a
/// build with `--dart-define=FRAME_COUNTER_GIFS=true`.
abstract final class FrameCounterPack {
  /// The collection the GIF page lists them as.
  static const CollectionId id = CollectionId.set('frame_counter');

  /// The collection's title.
  static const String title = 'Frame counter';

  static const String _keyPrefix = 'frame-counter:';

  /// Every clip: the GIFs, the WebPs, then the MP4s, each at 10, 15 and 25
  /// fps. The files are in `assets/frame_counter/`.
  static final List<FrameCounterItem> items = List.unmodifiable([
    for (final extension in ['gif', 'webp', 'mp4'])
      for (final fps in [10, 15, 25]) FrameCounterItem._(fps, extension),
  ]);

  static final Map<ContentKey, FrameCounterItem> _byKey = {
    for (final item in items) item.key: item,
  };

  /// The clip of [key], or null for content that is not one.
  static FrameCounterItem? of(ContentKey key) => _byKey[key];

  /// The descriptor of every clip, for the host's asset pipeline.
  static Iterable<ContentDescriptor> get descriptors =>
      items.map((item) => item.descriptor);

  /// A source that lists the clips as one collection, loaded from the start.
  static CollectionSource source() =>
      BundledPackSource(id: id, title: title, items: items);
}
