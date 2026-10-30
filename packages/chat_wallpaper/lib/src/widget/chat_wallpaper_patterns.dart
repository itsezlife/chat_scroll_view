import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/render/wallpaper_pattern_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// Registry of pattern artwork for the `ChatWallpaperView`s below it.
///
/// Maps each [WallpaperPattern.slug] the host ships to the vector source
/// of its artwork. The engine owns no artwork: without this scope, or for a
/// slug it doesn't list, a patterned wallpaper paints its fill alone.
///
/// Dependents rebuild only when the mapping changes by content.
class ChatWallpaperPatterns extends InheritedWidget {
  /// Provides [artwork] to [child] and its descendants.
  const ChatWallpaperPatterns({
    required this.artwork,
    required super.child,
    super.key,
  });

  /// Artwork source per pattern slug.
  final Map<String, BytesLoader> artwork;

  /// Artwork for [slug] from the nearest scope, or `null` when there is no
  /// scope or it doesn't list [slug]. Registers [context] as a dependent.
  static BytesLoader? artworkOf(BuildContext context, String slug) => context
      .dependOnInheritedWidgetOfExactType<ChatWallpaperPatterns>()
      ?.artwork[slug];

  /// The raster of [slug] that every consumer under [context] resolves: its
  /// [artworkOf] rasterized at the shorter side of the display in physical
  /// pixels.
  ///
  /// The single place the provider is built, so consumers under one registry
  /// on one display (a view and anything warming its pattern) always reach
  /// the same [ImageCache] entry.
  ///
  /// The width follows the display, not the window: a window that is
  /// resized, split, folded or rotated keeps its raster, and the pattern is
  /// scaled to the window when it is drawn. Keyed by the window instead,
  /// every step of a desktop window drag rasterized the artwork again and
  /// dropped the pattern until the new raster landed. Where the platform
  /// reports no display size, the window's shorter side stands in.
  ///
  /// `null` when there is no artwork for [slug], or while nothing has a size
  /// yet (a launch frame before the first layout). Registers [context] as a
  /// dependent of the scope and, when there is artwork, of its [View].
  @internal
  static WallpaperPatternImage? imageOf(BuildContext context, String slug) {
    final artwork = artworkOf(context, slug);
    if (artwork == null) return null;
    final side = switch (View.maybeOf(context)?.display.size) {
      final display? when !display.isEmpty => display.shortestSide,
      _ =>
        MediaQuery.sizeOf(context).shortestSide *
            MediaQuery.devicePixelRatioOf(context),
    };
    final width = side.round();
    if (width <= 0) return null;
    return WallpaperPatternImage(slug: slug, artwork: artwork, width: width);
  }

  @override
  bool updateShouldNotify(ChatWallpaperPatterns oldWidget) =>
      !mapEquals(artwork, oldWidget.artwork);
}
