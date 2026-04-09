import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// Whether a message is aligned to the left or right of the content area.
enum ChatMessageAlignment { left, right }

/// Lightweight render object for a single chat message.
///
/// Owns layout state (e.g. [TextPainter]s) between [performLayout] and
/// [paintMessage], so work done during layout is reused at paint time.
///
/// ### Compositing architecture
///
/// Each message owns an [OffsetLayer] → [PictureLayer] subtree.
/// The viewport calls [attachLayer] when the message enters the attach zone
/// and [detachLayer] when it leaves the detach zone (wider than attach zone
/// to avoid thrashing on small scroll oscillations).
///
/// When attached, [paintMessage] output is recorded into a [ui.Picture]
/// and stored in the [PictureLayer]. Scrolling only updates
/// [OffsetLayer.offset] — no re-recording.
///
/// For animated messages, override [needsRepaint] to return `true`.
/// The viewport will call [rerecordPicture] every frame while active.
abstract class ChatMessageRender {
  /// Called when message data or chunk status may have changed.
  ///
  /// [message] is `null` when the slot has no content yet (chunk just created,
  /// fetch in progress). Compare with previous values (e.g. via [identical])
  /// and set [dirty] or call [invalidatePaint] as appropriate.
  void update(covariant IChatMessage? message, ChatMessageStatus status);

  /// Lay out the message for the given [availableWidth].
  /// Returns the computed height.
  double performLayout(double availableWidth);

  /// Paint the message content onto [canvas] within [size].
  ///
  /// The result is recorded into a [ui.Picture] and cached in
  /// a [PictureLayer] inside this render's [OffsetLayer].
  void paintMessage(Canvas canvas, Size size);

  /// Whether this render has no content to display.
  ///
  /// Empty renders skip layer creation entirely — no [OffsetLayer], no
  /// [PictureLayer], no [paintMessage] call.
  /// Defaults to `true` when [height] is zero.
  bool get isEmpty => height == 0.0;

  /// Whether this message needs its [PictureLayer] re-recorded every frame.
  ///
  /// Override and return `true` for animations (hover, buttons, etc.).
  /// Alternatively, create a [Ticker] in [attachLayer] and call
  /// [rerecordPicture] directly — this avoids viewport polling and lets
  /// the render drive its own animation lifecycle.
  bool get needsRepaint => false;

  /// Hit-test at [position] (local to this message's origin).
  bool hitTest(Offset position) => false;

  /// Called by the viewport when a pointer event occurs within this
  /// render's bounds. [localPosition] is in this render's coordinate
  /// space (0,0 = top-left of message).
  ///
  /// Override for interactive content (links, buttons, hover effects).
  /// Selection handling is done by the viewport — this method is for
  /// render-local interactions.
  void handlePointerEvent(PointerEvent event, Offset localPosition) {}

  // --- Layout properties (set by viewport or concrete render) ---

  /// Alignment within the content area. Set by concrete render in [update].
  @nonVirtual
  ChatMessageAlignment alignment = ChatMessageAlignment.left;

  // --- Selection state (set by viewport) ---

  /// Whether selection mode is globally active (checkboxes visible).
  @nonVirtual
  bool selectionMode = false;

  /// Whether this message is currently selected.
  /// Set by the viewport; the concrete render uses it in [paintMessage].
  @nonVirtual
  bool selected = false;

  /// Invalidate the cached picture, causing [paintMessage] to be called
  /// again on the next paint frame. Does not trigger layout.
  void invalidatePaint() {
    pictureInvalid = true;
  }

  /// Whether the cached picture needs re-recording.
  @internal
  bool pictureInvalid = false;

  /// Whether this render currently has live layers.
  bool get isAttached => _attached;

  // --- Layer lifecycle ---

  /// Create the [OffsetLayer] → [PictureLayer] subtree and record
  /// the initial picture via [paintMessage].
  ///
  /// Override to react to entering the visible zone (start animations,
  /// load resources, create a [Ticker]). Always call `super.attachLayer(width)`
  /// first — layers are ready after super returns.
  ///
  /// Example (render-owned animation):
  /// ```dart
  /// @override
  /// void attachLayer(double width) {
  ///   super.attachLayer(width);
  ///   _ticker = Ticker(_onTick)..start();
  /// }
  /// ```
  @mustCallSuper
  void attachLayer(double width) {
    assert(!_attached);
    layerWidth = width;
    layer = OffsetLayer(offset: Offset(0, offsetY));
    _attached = true;
    pictureInvalid = false;
    rerecordPicture();
  }

  /// Dispose the [PictureLayer] and [OffsetLayer], releasing the
  /// cached [ui.Picture].
  ///
  /// Override to react to leaving the visible zone (stop animations,
  /// dispose [Ticker]s, release resources). Call `super.detachLayer()` last —
  /// layers are still alive until super runs.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void detachLayer() {
  ///   _ticker?.dispose();
  ///   _ticker = null;
  ///   super.detachLayer();
  /// }
  /// ```
  @mustCallSuper
  void detachLayer() {
    assert(_attached);
    _disposePictureLayer();
    layer = null;
    _attached = false;
  }

  /// Re-record [paintMessage] into a fresh [PictureLayer].
  ///
  /// Called by the viewport when [pictureInvalid] or [needsRepaint] is `true`.
  /// Can also be called directly from a render-owned [Ticker] to drive
  /// per-message animations without involving the viewport's paint pass.
  ///
  /// Sets [PictureLayer.picture], which triggers [markNeedsAddToScene] —
  /// the compositor re-composites only this layer subtree. No
  /// [markNeedsPaint] on the parent [RenderBox] required.
  void rerecordPicture() {
    assert(_attached);
    _disposePictureLayer();
    final rect = Rect.fromLTWH(0, 0, layerWidth, height);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);
    paintMessage(canvas, Size(layerWidth, height));
    if (selectionMode) paintSelectionIndicator(canvas);
    _pictureLayer = PictureLayer(rect)..picture = recorder.endRecording();
    layer!.append(_pictureLayer!);
  }

  /// Paints the selection checkbox indicator at the right edge of the
  /// content area, vertically centered. Override for custom appearance.
  @protected
  void paintSelectionIndicator(Canvas canvas) {
    const radius = 12.0;
    const padding = 8.0;
    final cx = radius + padding;
    final cy = height - radius - padding;
    final center = Offset(cx, cy);

    if (selected) {
      // Filled circle.
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFF448AFF),
      );
      // Checkmark.
      final path = Path()
        ..moveTo(cx - 5, cy)
        ..lineTo(cx - 1.5, cy + 4)
        ..lineTo(cx + 5.5, cy - 4);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      // Empty circle.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFF9E9E9E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  /// Release resources (TextPainters, images, etc.).
  @mustCallSuper
  void dispose() {
    if (_attached) detachLayer();
  }

  // --- Private layer management ---

  void _disposePictureLayer() {
    if (_pictureLayer case final pictureLayer?) {
      pictureLayer.remove();
      _pictureLayer = null;
    }
  }

  /// The compositing layer for this message, held via [LayerHandle]
  /// to prevent disposal when the parent [ClipRectLayer] removes children.
  final LayerHandle<OffsetLayer> layerHandle = LayerHandle<OffsetLayer>();

  /// The [OffsetLayer] for this message. Accessible by the viewport.
  @internal
  OffsetLayer? get layer => layerHandle.layer;
  @internal
  set layer(OffsetLayer? value) => layerHandle.layer = value;

  PictureLayer? _pictureLayer;
  bool _attached = false;

  /// Width used for recording (set at [attachLayer] time).
  @internal
  double layerWidth = 0.0;

  // --- Managed by the viewport (not overridable) ---

  /// The Y offset within the viewport (set during layout).
  @nonVirtual
  double offsetY = 0.0;

  /// The computed height of this message (set after [performLayout]).
  @nonVirtual
  double height = 0.0;

  /// Whether this message needs to be re-laid out.
  @nonVirtual
  bool dirty = true;
}

/// Creates a [ChatMessageRender] for the given [message].
/// [message] is `null` for slots that have no content yet.
typedef ChatMessageRenderFactory =
    ChatMessageRender Function(IChatMessage? message);
