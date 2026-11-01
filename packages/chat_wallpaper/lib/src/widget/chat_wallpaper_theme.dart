import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:flutter/widgets.dart';

/// Exposes the resolved [ChatWallpaper] to a chat subtree.
///
/// The scope does not resolve anything itself: the host decides which
/// wallpaper applies and mounts the result once, so every reader — the
/// background layer and any chrome derived from the wallpaper — sees the
/// same value.
///
/// Dependents rebuild only when [wallpaper] changes by value; re-mounting an
/// equal wallpaper on a host rebuild notifies nobody.
class ChatWallpaperTheme extends InheritedWidget {
  /// Provides [wallpaper] to [child] and its descendants.
  const ChatWallpaperTheme({
    required this.wallpaper,
    required super.child,
    super.key,
  });

  /// Wallpaper the subtree draws behind its messages.
  final ChatWallpaper wallpaper;

  /// Nearest scoped wallpaper, or `null` when no [ChatWallpaperTheme] is an
  /// ancestor. Registers [context] as a dependent.
  static ChatWallpaper? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChatWallpaperTheme>()
      ?.wallpaper;

  /// Nearest scoped wallpaper. Registers [context] as a dependent.
  ///
  /// Throws a [FlutterError] when no [ChatWallpaperTheme] is an ancestor; the
  /// engine has no wallpaper of its own to fall back to.
  static ChatWallpaper of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError(
        'ChatWallpaperTheme.of() was called with a context that has no ChatWallpaperTheme ancestor.\n'
        'Mount a ChatWallpaperTheme above the chat subtree, or use ChatWallpaperTheme.maybeOf().',
      ));

  @override
  bool updateShouldNotify(ChatWallpaperTheme oldWidget) =>
      wallpaper != oldWidget.wallpaper;
}
