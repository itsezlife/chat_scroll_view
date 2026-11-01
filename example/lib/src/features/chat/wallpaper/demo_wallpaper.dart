import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// The wallpaper the demo's chats show, and its artwork.
///
/// The app is dark, so this is the dark default of the product the demo
/// mirrors: a four-point freeform gradient seen through the doodle pattern as
/// a mask, the heaviest kind to composite. Every on-device wallpaper suite
/// measures this value unless it picks another.
abstract final class DemoWallpaper {
  /// Slug of the doodle pattern.
  static const String careerPattern = 'career';

  /// Artwork per slug, compiled from SVG at build time.
  static const Map<String, BytesLoader> artwork = {
    careerPattern: AssetBytesLoader('assets/chat_wallpaper/career.svg'),
  };

  /// The four colour points of [dark].
  static const ChatWallpaper$Freeform darkFill = ChatWallpaper$Freeform(
    Color(0xFF5E9E8A),
    Color(0xFF28493F),
    Color(0xFF8AA66A),
    Color(0xFF2A4A52),
  );

  /// The chats' wallpaper.
  static const ChatWallpaper dark = ChatWallpaper.patterned(
    darkFill,
    WallpaperPattern(
      careerPattern,
      intensity: 57,
      blend: WallpaperPatternBlend.mask,
    ),
  );

  /// The wallpaper [DemoConfig.wallpaper] names; `null` for none.
  static ChatWallpaper? get configured => switch (DemoConfig.wallpaper) {
    'none' => null,
    'solid' => const ChatWallpaper.solid(Color(0xFF28493F)),
    'linear' => const ChatWallpaper.linear(
      Color(0xFF5E9E8A),
      Color(0xFF2A4A52),
    ),
    'freeform' => darkFill,
    'softLight' => const ChatWallpaper.patterned(
      darkFill,
      WallpaperPattern(careerPattern),
    ),
    _ => dark,
  };
}

/// The wallpaper scopes of the app, above the navigator as a product mounts
/// them: one motion timeline for every chat, the pattern registry, and the
/// warm-up that keeps [wallpaper]'s pattern raster, freeform keyframes and
/// last composite alive between chats.
///
/// Mounted above the navigator, a chat pushed later paints the wallpaper on
/// its first frame instead of its average colour, and reopening a chat takes
/// no new composite. Needs a [MediaQuery] above it.
class DemoWallpaperScope extends StatelessWidget {
  /// Scopes [child] for [wallpaper].
  const DemoWallpaperScope({required this.child, this.wallpaper, super.key});

  /// The wallpaper the chats below show; none when `null`.
  final ChatWallpaper? wallpaper;

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) => ChatWallpaperMotionScope(
    child: switch (wallpaper) {
      final wallpaper? => ChatWallpaperPatterns(
        artwork: DemoWallpaper.artwork,
        child: ChatWallpaperTheme(
          wallpaper: wallpaper,
          child: ChatWallpaperWarmUp(wallpapers: [wallpaper], child: child),
        ),
      ),
      null => child,
    },
  );
}

/// The box a chat's wallpaper covers: lends the scoped wallpaper's gradient
/// to the service fills in [child], moving with the app's motion scope. Just
/// [child] when no wallpaper is scoped.
class DemoChatSurface extends StatelessWidget {
  /// Lends the scoped wallpaper to [child].
  const DemoChatSurface({required this.child, super.key});

  /// The chat, everything over it and the [DemoChatWallpaper] under it.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      switch (ChatWallpaperTheme.maybeOf(context)) {
        final wallpaper? => ChatWallpaperSurface(
          wallpaper: wallpaper,
          darkTheme: true,
          motion: ChatWallpaperMotionScope.maybeOf(context),
          child: child,
        ),
        null => child,
      };
}

/// [child] over the scoped wallpaper, filling the box; just [child] when no
/// wallpaper is scoped.
///
/// The chat puts it inside its glass source, so the composer and the side
/// controls frost the wallpaper under the messages, as they do in a product.
class DemoChatWallpaper extends StatelessWidget {
  /// Paints the scoped wallpaper under [child].
  const DemoChatWallpaper({required this.child, super.key});

  /// What is drawn over the wallpaper.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      switch (ChatWallpaperTheme.maybeOf(context)) {
        final wallpaper? => Stack(
          fit: StackFit.expand,
          children: [
            ChatWallpaperView(
              wallpaper: wallpaper,
              motion: ChatWallpaperMotionScope.maybeOf(context),
            ),
            child,
          ],
        ),
        null => child,
      };
}
