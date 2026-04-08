import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

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
  void update(covariant Object? message, ChatMessageStatus status);

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
  bool get needsRepaint => false;

  /// Hit-test at [position] (local to this message's origin).
  bool hitTest(Offset position) => false;

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
  /// load resources). Always call `super.attachLayer(width)` first.
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
  /// release resources). Call `super.detachLayer()` last.
  @mustCallSuper
  void detachLayer() {
    assert(_attached);
    _disposePictureLayer();
    layer = null;
    _attached = false;
  }

  /// Re-record [paintMessage] into a fresh [PictureLayer].
  @nonVirtual
  void rerecordPicture() {
    assert(_attached);
    _disposePictureLayer();
    final rect = Rect.fromLTWH(0, 0, layerWidth, height);
    final recorder = ui.PictureRecorder();
    paintMessage(Canvas(recorder, rect), Size(layerWidth, height));
    _pictureLayer = PictureLayer(rect)..picture = recorder.endRecording();
    layer!.append(_pictureLayer!);
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
    ChatMessageRender Function(Object? message);
