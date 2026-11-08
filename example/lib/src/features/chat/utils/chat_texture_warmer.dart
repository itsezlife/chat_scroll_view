import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';

/// Warms the texture pool for the chat's stickers and GIFs (ADR 043, "Pool"),
/// once, when the chat screen opens: the chat's counterpart of
/// `PanelTextureWarmer`.
///
/// A sticker or GIF message is an emoji-only body of one document, drawn at
/// the platform's sticker extent, and its body composites a playing embed
/// as a texture layer. A lease never creates a texture, so without this the
/// first stickers of the chat would keep their page slots. The pool waits
/// with each creation while a surface scrolls, so a chat opened mid-fling
/// creates them once it rests.
abstract final class ChatTextureWarmer {
  /// About how many sticker or GIF messages one screen of the chat shows.
  static const int perScreen = 6;

  /// Warms [pool] with [perScreen] textures of the class a sticker of
  /// [stickerExtent] logical pixels takes at [devicePixelRatio]; nothing when
  /// it is above the largest class.
  static void warm(
    FrameTexturePool pool, {
    required double stickerExtent,
    required double devicePixelRatio,
  }) {
    final pixels = (stickerExtent * devicePixelRatio).ceil();
    final sizeClass = pool.classOf(pixels, pixels);
    if (sizeClass == null) return;
    unawaited(pool.warm(sizeClass, perScreen));
  }
}
