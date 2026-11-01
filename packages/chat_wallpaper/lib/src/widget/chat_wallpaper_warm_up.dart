import 'dart:async';

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_controller.dart';
import 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_scope.dart';
import 'package:chat_wallpaper/src/render/wallpaper_pattern_image.dart';
import 'package:chat_wallpaper/src/widget/chat_wallpaper_patterns.dart';
import 'package:chat_wallpaper/src/widget/chat_wallpaper_view.dart';
import 'package:chat_wallpaper/src/widget/patterned_fill.dart';
import 'package:flutter/widgets.dart';

/// Keeps the pattern rasters and freeform keyframes of [wallpapers] ready for
/// the [ChatWallpaperView]s mounted while it is in the tree.
///
/// ## Rasters
///
/// For each [ChatWallpaper$Patterned] in [wallpapers] whose slug has artwork
/// in the nearest [ChatWallpaperPatterns], the host resolves the same
/// [WallpaperPatternImage] a view under that registry and the same
/// [MediaQuery] size resolves, and listens to it while mounted. Wallpapers without a pattern, and slugs
/// without artwork, are skipped. Patterns sharing a slug share one raster,
/// whatever their fill, intensity or blend.
///
/// A raster with a listener is a live [ImageCache] entry: a view mounted
/// later finds it synchronously and composites the pattern on its first
/// frame, however many other images have passed through the cache, and even
/// after [ImageCache.clear]. A raster resolved and then left without
/// listeners, as [precacheImage] leaves it, is an ordinary cache entry that
/// other images can evict.
///
/// Rasterizing is asynchronous: a view mounted before its raster lands waits
/// for it as it would without the host. The rasters live as long as the
/// host; mounted above the navigator, as long as the app.
///
/// ## Keyframes
///
/// Under a [ChatWallpaperMotionScope], the host also holds the scope
/// controller's keyframes of every [ChatWallpaper.freeformFill] in
/// [wallpapers], bare or under a pattern; equal fills share one hold. A view
/// given that controller finds the keyframes already held: once the settled
/// frame has landed, it paints the freeform raster on its first frame instead
/// of [ChatWallpaper.averageColor].
///
/// The hold is one more holder of the keyframes the controller shares with
/// its views, not a copy. It follows every run the controller starts, so a
/// view mounted after a run paints the phase the run settled at once that
/// frame has landed, and it never delays or blocks a run. While a fill is
/// held, the controller keeps and warms its whole ring of keyframes in the
/// background even when no view paints it. Once the ring is warm, the first
/// run a view starts on the fill — a shift, a swirl or the loading spin —
/// begins on keyframes already held. Each held fill costs up to about
/// 460 KB of textures once its ring is warm; while the controller's motion
/// is disabled, only its resting keyframe.
///
/// Without a motion scope above it, the host holds no keyframes: a view
/// without a controller rasterizes and owns its own freeform image, so there
/// is nothing to share with it.
///
/// ## Shader
///
/// The host also loads the shader patterned views paint with, so a view
/// mounted after it has loaded composites its pattern on its first frame.
///
/// ## Changes
///
/// When [wallpapers], the registry or the display changes, or the host moves under another motion scope, rasters and
/// keyframes no longer needed are released and new ones acquired; one still
/// needed stays held without being resolved again. Unmounting releases
/// everything. A released raster stays in the cache as an ordinary entry
/// until something evicts it; released keyframes are disposed once no view
/// holds them either.
///
/// ## Requirements and failures
///
/// A [MediaQuery] must be an ancestor whenever a listed pattern has artwork.
/// The host attaches no error listener, so a raster that fails to rasterize
/// is still reported through [FlutterError.reportError].
class ChatWallpaperWarmUp extends StatefulWidget {
  /// Keeps [wallpapers]' pattern rasters and freeform keyframes ready for
  /// [child] and its descendants.
  const ChatWallpaperWarmUp({
    required this.wallpapers,
    required this.child,
    super.key,
  });

  /// Wallpapers to keep ready. Order and duplicates don't matter.
  final List<ChatWallpaper> wallpapers;

  /// Subtree whose wallpaper views find the rasters and keyframes ready.
  final Widget child;

  @override
  State<ChatWallpaperWarmUp> createState() => _ChatWallpaperWarmUpState();
}

class _ChatWallpaperWarmUpState extends State<ChatWallpaperWarmUp> {
  late final ImageStreamListener _listener = ImageStreamListener(_onPattern);

  @override
  void initState() {
    super.initState();
    // A failure is the loader's to report; the views paint their bare fills.
    unawaited(PatternedFillProgram.load().then<void>((_) {}, onError: (_) {}));
  }

  /// Held rasters, each with the stream the listener is attached to.
  final Map<WallpaperPatternImage, ImageStream> _patterns = {};

  /// Controller [_heldFills] are held on; `null` without a motion scope.
  ChatWallpaperMotionController? _motion;

  /// Fills whose keyframes are held on [_motion], one hold each.
  final Set<ChatWallpaper$Freeform> _heldFills = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warm();
  }

  @override
  void didUpdateWidget(ChatWallpaperWarmUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _warm();
  }

  /// The scope lookup registers no dependency, so a host moved under another
  /// scope with an unchanged widget and no pattern dependencies gets neither
  /// [didChangeDependencies] nor [didUpdateWidget]; the move itself re-reads
  /// the scope.
  @override
  void activate() {
    super.activate();
    _warmKeyframes();
  }

  void _warm() {
    _warmPatterns();
    _warmKeyframes();
  }

  /// Holds exactly the rasters [ChatWallpaperWarmUp.wallpapers] need now.
  /// Diffing by provider keeps a raster that is still needed on its existing
  /// stream.
  void _warmPatterns() {
    final wanted = {
      for (final wallpaper in widget.wallpapers)
        if (wallpaper case ChatWallpaper$Patterned(:final pattern))
          ?ChatWallpaperPatterns.imageOf(context, pattern.slug),
    };
    for (final image
        in _patterns.keys.where((image) => !wanted.contains(image)).toList()) {
      _patterns.remove(image)?.removeListener(_listener);
    }
    for (final image in wanted.where(
      (image) => !_patterns.containsKey(image),
    )) {
      _patterns[image] = image.resolve(ImageConfiguration.empty)
        ..addListener(_listener);
    }
  }

  /// Holds exactly the keyframes [ChatWallpaperWarmUp.wallpapers] need on the
  /// nearest scope's controller, moving every hold when that controller is
  /// not the one they are on.
  void _warmKeyframes() {
    final motion = ChatWallpaperMotionScope.maybeOf(context);
    if (!identical(motion, _motion)) {
      _releaseKeyframes();
      _motion = motion;
    }
    if (motion == null) return;
    final wanted = {
      for (final wallpaper in widget.wallpapers) ?wallpaper.freeformFill,
    };
    for (final fill in _heldFills.difference(wanted)) {
      _heldFills.remove(fill);
      motion.releaseKeyframes(fill);
    }
    for (final fill in wanted.difference(_heldFills)) {
      _heldFills.add(fill);
      motion.acquireKeyframes(fill);
    }
  }

  /// Drops every keyframe hold on [_motion]; a no-op for a controller already
  /// disposed.
  void _releaseKeyframes() {
    if (_motion case final motion?) _heldFills.forEach(motion.releaseKeyframes);
    _heldFills.clear();
  }

  /// Each delivery hands this listener its own handle on the image; the
  /// stream's completer keeps the raster itself, so the handle is disposed
  /// straight away.
  void _onPattern(ImageInfo pattern, bool synchronousCall) => pattern.dispose();

  @override
  void dispose() {
    for (final stream in _patterns.values) {
      stream.removeListener(_listener);
    }
    _patterns.clear();
    _releaseKeyframes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
