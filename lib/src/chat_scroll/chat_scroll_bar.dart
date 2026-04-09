import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Lightweight scrollbar overlay for [ChatScrollView].
///
/// Manages a single [PictureLayer] that paints a thin track + thumb
/// at the right edge of the viewport. Owned by [RenderChatScrollView],
/// not a widget.
///
/// The scrollbar position is fixed (right edge), so no [OffsetLayer] is
/// needed — only the thumb position within the track changes, which means
/// re-recording the picture (a few rounded rects — trivially cheap).
class ChatScrollBar {
  /// Width of the touch target from the right edge.
  static const double hitAreaWidth = 32.0;

  /// Visual track width (default state).
  static const double trackWidth = 4.0;

  /// Visual track width when actively dragging.
  static const double activeTrackWidth = 6.0;

  /// Fixed thumb height.
  static const double thumbHeight = 48.0;

  /// Padding from the top and bottom of the viewport.
  static const double trackPadding = 8.0;

  /// Distance from the right edge of the viewport.
  static const double rightPadding = 4.0;

  // --- State ---

  double _lastProgress = -1.0;
  bool _lastDragging = false;
  Size _lastViewportSize = Size.zero;

  /// Whether the scrollbar is being dragged. Set by the render object.
  bool isDragging = false;

  // --- Layer ---

  final LayerHandle<PictureLayer> _layerHandle = LayerHandle<PictureLayer>();

  /// The picture layer for compositing. May be null if not yet created.
  PictureLayer? get layer => _layerHandle.layer;

  /// Update the scrollbar picture for the current [progress] (0..1).
  ///
  /// Re-records only when progress, drag state, or viewport size changed.
  /// Creates the [PictureLayer] lazily on first call.
  void update(double progress, Size viewportSize) {
    final dragging = isDragging;
    if (progress == _lastProgress &&
        dragging == _lastDragging &&
        viewportSize == _lastViewportSize) {
      return;
    }
    _lastProgress = progress;
    _lastDragging = dragging;
    _lastViewportSize = viewportSize;
    _rerecord(progress, viewportSize, dragging);
  }

  /// Remove and dispose the picture layer.
  void dispose() {
    _layerHandle.layer = null;
  }

  /// Whether [localX] falls within the scrollbar hit area.
  bool isInHitArea(double localX, double viewportWidth) {
    return localX >= viewportWidth - hitAreaWidth;
  }

  /// Convert a local Y coordinate to a progress value (0..1), clamped.
  double progressFromY(double localY, double viewportHeight) {
    final trackHeight = viewportHeight - trackPadding * 2 - thumbHeight;
    if (trackHeight <= 0) return 0.0;
    final y = localY - trackPadding - thumbHeight / 2;
    return (y / trackHeight).clamp(0.0, 1.0);
  }

  /// Convert a progress value (0..1) to a target message ID.
  static int targetIdFromProgress(double progress, int newestKnownId) {
    return (progress * newestKnownId).round();
  }

  // --- Private ---

  void _rerecord(double progress, Size viewportSize, bool dragging) {
    // Remove old layer from the parent tree before disposal via LayerHandle.
    _layerHandle.layer?.remove();
    final rect = Offset.zero & viewportSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);

    _paintScrollbar(canvas, viewportSize, progress, dragging);

    _layerHandle.layer = PictureLayer(rect)..picture = recorder.endRecording();
  }

  void _paintScrollbar(
    Canvas canvas,
    Size viewportSize,
    double progress,
    bool dragging,
  ) {
    final currentTrackWidth = dragging ? activeTrackWidth : trackWidth;
    final trackX =
        viewportSize.width - rightPadding - currentTrackWidth;
    final trackY = trackPadding;
    final trackHeight = viewportSize.height - trackPadding * 2;

    if (trackHeight <= 0) return;

    // Track background.
    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(trackX, trackY, currentTrackWidth, trackHeight),
      Radius.circular(currentTrackWidth / 2),
    );
    canvas.drawRRect(
      trackRRect,
      Paint()..color = const Color(0x1A000000),
    );

    // Thumb.
    final thumbTravel = trackHeight - thumbHeight;
    if (thumbTravel <= 0) return;

    final thumbY = trackY + thumbTravel * progress;
    final thumbRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(trackX, thumbY, currentTrackWidth, thumbHeight),
      Radius.circular(currentTrackWidth / 2),
    );
    canvas.drawRRect(
      thumbRRect,
      Paint()..color = Color(dragging ? 0x99000000 : 0x66000000),
    );
  }
}
