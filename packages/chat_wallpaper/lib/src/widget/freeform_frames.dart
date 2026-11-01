import 'dart:async';
import 'dart:ui' as ui;

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_controller.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:chat_wallpaper/src/render/freeform_gradient.dart';
import 'package:flutter/foundation.dart';

/// What a freeform fill paints now, and a signal whenever that changes.
///
/// Under a motion controller the frame comes from the keyframes it shares
/// with every other holder of [wallpaper], at its current phase; without one,
/// from a phase-0 raster this source owns. Notifies on every motion tick and
/// every landed keyframe. Dispose it to release what it holds.
@internal
sealed class FreeformFrames implements Listenable {
  /// Frames of [wallpaper], moving with [motion] when given.
  factory FreeformFrames(
    ChatWallpaper$Freeform wallpaper, {
    ChatWallpaperMotionController? motion,
  }) => switch (motion) {
    final motion? => _MovingFrames(wallpaper, motion),
    null => _StillFrames(wallpaper),
  };

  /// The frame to paint, or `null` before the first raster lands.
  FreeformFrame? get frame;

  /// Releases the rasters or the keyframe hold.
  void dispose();
}

final class _MovingFrames implements FreeformFrames {
  _MovingFrames(this._wallpaper, this._motion)
    : _keyframes = _motion.acquireKeyframes(_wallpaper) {
    _changes = Listenable.merge([_motion, _keyframes]);
  }

  final ChatWallpaper$Freeform _wallpaper;
  final ChatWallpaperMotionController _motion;
  final FreeformKeyframes _keyframes;
  late final Listenable _changes;

  @override
  FreeformFrame? get frame =>
      _keyframes.frameAt(phase: _motion.phase, progress: _motion.progress);

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  @override
  void dispose() => _motion.releaseKeyframes(_wallpaper);
}

final class _StillFrames extends ChangeNotifier implements FreeformFrames {
  _StillFrames(ChatWallpaper$Freeform wallpaper) {
    unawaited(_rasterize(wallpaper));
  }

  ui.Image? _image;
  bool _disposed = false;

  @override
  FreeformFrame? get frame => switch (_image) {
    final image? => (base: image, overlay: null, overlayOpacity: 0),
    null => null,
  };

  /// An image that lands after [dispose] is disposed on arrival.
  Future<void> _rasterize(ChatWallpaper$Freeform wallpaper) async {
    final image = await FreeformGradient.image(wallpaper);
    if (_disposed) {
      image.dispose();
      return;
    }
    _image = image;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
