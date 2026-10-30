import 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_controller.dart';
import 'package:flutter/widgets.dart';

/// Owns one [ChatWallpaperMotionController] for a whole subtree, so every
/// wallpaper view under it moves on one timeline.
///
/// ## Ownership
///
/// The scope's state creates the controller when the scope mounts and
/// disposes it when the scope unmounts. The controller ticks through that
/// state and follows [MediaQuery.disableAnimationsOf], so a [MediaQuery] must
/// be an ancestor. Hosts under the scope pass the controller to their views
/// and call its run requests; they never dispose it.
///
/// The phase therefore outlives any single host. A host that leaves the tree
/// and mounts again under the same scope finds the colour points where the
/// last run left them, and a run started through one host moves every view
/// under the scope at once. Mounted above the navigator, the phase lasts as
/// long as the app process and resets only on restart. The ticker follows the
/// nearest [TickerMode] above the scope, not the routes below it, so a run
/// started from a host keeps going after that host's route is covered.
///
/// A host that needs a timeline of its own — one that starts at phase `0`
/// and never moves another host's views — mixes in
/// [ChatWallpaperMotionStateMixin] instead of reading the scope.
///
/// ## Lookup
///
/// [of] and [maybeOf] register no dependency: the controller is one object
/// for the scope's whole lifetime, so there is no change to notify. They may
/// be called from `initState`. Motion itself is observed by listening to the
/// controller.
class ChatWallpaperMotionScope extends StatefulWidget {
  /// Provides one motion controller to [child] and its descendants.
  const ChatWallpaperMotionScope({required this.child, super.key});

  /// Subtree whose wallpaper views share the scope's controller.
  final Widget child;

  /// Controller of the nearest scope, or `null` when no
  /// [ChatWallpaperMotionScope] is an ancestor. Registers no dependency.
  static ChatWallpaperMotionController? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_InheritedChatWallpaperMotion>()
      ?.motion;

  /// Controller of the nearest scope. Registers no dependency.
  ///
  /// Throws a [FlutterError] when no [ChatWallpaperMotionScope] is an
  /// ancestor.
  static ChatWallpaperMotionController of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError(
        'ChatWallpaperMotionScope.of() was called with a context that has no ChatWallpaperMotionScope ancestor.\n'
        'Mount a ChatWallpaperMotionScope above the wallpaper hosts, or give the host its own controller '
        'with ChatWallpaperMotionStateMixin.',
      ));

  @override
  State<ChatWallpaperMotionScope> createState() =>
      _ChatWallpaperMotionScopeState();
}

class _ChatWallpaperMotionScopeState extends State<ChatWallpaperMotionScope>
    with SingleTickerProviderStateMixin, ChatWallpaperMotionStateMixin {
  @override
  Widget build(BuildContext context) => _InheritedChatWallpaperMotion(
    motion: wallpaperMotion,
    child: widget.child,
  );
}

class _InheritedChatWallpaperMotion extends InheritedWidget {
  const _InheritedChatWallpaperMotion({
    required this.motion,
    required super.child,
  });

  final ChatWallpaperMotionController motion;

  @override
  bool updateShouldNotify(_InheritedChatWallpaperMotion oldWidget) =>
      !identical(motion, oldWidget.motion);
}
