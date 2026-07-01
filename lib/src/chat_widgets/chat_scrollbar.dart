import 'package:flutter/material.dart';

/// Scrollbar colours registered as a [ThemeExtension].
///
/// Resolution order: [of], then [mergeTheme] fallback from ambient [ThemeData]
/// brightness. Per-screen overrides use a nested `Theme` with
/// `copyWith(extensions: […])`.
@immutable
class ChatScrollbarThemeData extends ThemeExtension<ChatScrollbarThemeData> {
  /// Creates scrollbar theme colours for thumb and uniform track.
  const ChatScrollbarThemeData({
    this.thumbColor = const Color(0x66000000),
    this.thumbDraggingColor = const Color(0x99000000),
    this.trackColor = const Color(0x1A000000),
  });

  /// Resolves scrollbar theme from [context].
  ///
  /// Uses `Theme.of(context).extension<ChatScrollbarThemeData>()` when
  /// registered; otherwise [mergeTheme] from ambient [ThemeData] brightness.
  factory ChatScrollbarThemeData.resolve(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ChatScrollbarThemeData>() ??
        ChatScrollbarThemeData.mergeTheme(theme);
  }

  /// Derives scrollbar colours from [theme] when no extension is registered.
  factory ChatScrollbarThemeData.mergeTheme(
    ThemeData theme, {
    Color? thumbColor,
    Color? thumbDraggingColor,
    Color? trackColor,
  }) {
    final base = theme.brightness == Brightness.dark ? dark : light;
    return ChatScrollbarThemeData(
      thumbColor: thumbColor ?? base.thumbColor,
      thumbDraggingColor: thumbDraggingColor ?? base.thumbDraggingColor,
      trackColor: trackColor ?? base.trackColor,
    );
  }

  /// Default colours for light surfaces (matches pre-enhancement visibility).
  static const light = ChatScrollbarThemeData();

  /// Default colours for dark surfaces.
  static const dark = ChatScrollbarThemeData(
    thumbColor: Color(0x66FFFFFF),
    thumbDraggingColor: Color(0x99FFFFFF),
    trackColor: Color(0x1AFFFFFF),
  );

  /// Idle thumb fill on the track.
  final Color thumbColor;

  /// Thumb fill while the user is dragging.
  final Color thumbDraggingColor;

  /// Uniform track fill for the full track height.
  final Color trackColor;

  @override
  ChatScrollbarThemeData copyWith({
    Color? thumbColor,
    Color? thumbDraggingColor,
    Color? trackColor,
  }) => ChatScrollbarThemeData(
    thumbColor: thumbColor ?? this.thumbColor,
    thumbDraggingColor: thumbDraggingColor ?? this.thumbDraggingColor,
    trackColor: trackColor ?? this.trackColor,
  );

  @override
  ChatScrollbarThemeData lerp(
    covariant ChatScrollbarThemeData? other,
    double t,
  ) {
    if (other == null) return this;
    return ChatScrollbarThemeData(
      thumbColor: Color.lerp(thumbColor, other.thumbColor, t)!,
      thumbDraggingColor: Color.lerp(
        thumbDraggingColor,
        other.thumbDraggingColor,
        t,
      )!,
      trackColor: Color.lerp(trackColor, other.trackColor, t)!,
    );
  }
}

/// Overlay scrollbar for the chat viewport.
///
/// Pure geometry, paint, and drag-pointer state — no dependency on the render
/// object, the data source, or the controller. [RenderChatScrollView] owns the
/// id ⇄ progress mapping; it routes pointer events here and feeds [paint] a
/// 0..1 thumb progress derived from the anchor.
///
/// The track uses a uniform colour; loaded/unloaded honesty is communicated in
/// the viewport, not via per-range track segments. Thumb position and size are
/// driven by [RenderChatScrollView] from height-weighted scroll metrics
/// (viewport ÷ estimated content extent).
class ChatScrollbar {
  /// Width of the invisible touch strip along the right edge.
  static const double hitWidth = 20;

  /// Default thumb height when no [thumbFraction] is supplied (legacy tests).
  static const double defaultThumbHeight = 48;

  /// Smallest painted thumb height on the track.
  static const double minThumbHeight = 16;

  static const double _trackWidth = 4;
  static const double _activeTrackWidth = 6;
  static const double _pad = 4;
  static const double _right = 4;

  /// Pointer id of the in-progress scrollbar drag, or `null` when idle.
  int? _pointer;

  /// Whether a scrollbar drag is currently in progress.
  bool get isDragging => _pointer != null;

  /// Whether [localX] and [localY] fall inside the trailing-edge touch strip
  /// over the inset-confined scroll band. The strip sits on the right in LTR
  /// and on the left in RTL — matching where the user expects the scrollbar
  /// to be in their reading order.
  bool inHitArea(
    double localX,
    double localY,
    Size size,
    TextDirection direction, {
    double topInset = 0,
    double bottomInset = 0,
  }) {
    final horizontal = direction == TextDirection.rtl
        ? localX <= hitWidth
        : localX >= size.width - hitWidth;
    if (!horizontal) return false;
    final geometry = _trackGeometry(
      size,
      topInset: topInset,
      bottomInset: bottomInset,
    );
    if (geometry.trackHeight <= 0) return false;
    final trackBottom = geometry.trackY + geometry.trackHeight;
    return localY >= geometry.trackY && localY <= trackBottom;
  }

  /// Begin a drag if [event] landed in the touch strip. Returns `true` when
  /// the drag was claimed (the caller should then consume the event).
  bool tryStartDrag(
    PointerDownEvent event,
    Size size,
    TextDirection direction, {
    double topInset = 0,
    double bottomInset = 0,
  }) {
    if (!inHitArea(
      event.localPosition.dx,
      event.localPosition.dy,
      size,
      direction,
      topInset: topInset,
      bottomInset: bottomInset,
    )) {
      return false;
    }
    _pointer = event.pointer;
    return true;
  }

  /// Whether [event] belongs to the active scrollbar drag.
  bool ownsPointer(PointerEvent event) => event.pointer == _pointer;

  /// End the active drag.
  void endDrag() => _pointer = null;

  /// Resolves thumb height from [thumbFraction] of the track, or
  /// [defaultThumbHeight] when [thumbFraction] is null.
  ///
  /// Proportional thumbs are floored at [minThumbHeight] by default so the thumb
  /// stays visible; pass [enforceMinHeight: false] only for diagnostics.
  double resolveThumbHeight(
    double trackHeight, {
    double? thumbFraction,
    bool enforceMinHeight = true,
  }) {
    if (trackHeight <= 0) return 0;
    if (thumbFraction == null) {
      return defaultThumbHeight.clamp(minThumbHeight, trackHeight);
    }
    final height = trackHeight * thumbFraction;
    final minH = enforceMinHeight ? minThumbHeight : 0.0;
    return height.clamp(minH, trackHeight).toDouble();
  }

  /// Map a pointer Y inside the track to a 0..1 thumb progress (clamped).
  double progressFromY(
    double localY,
    Size size, {
    double topInset = 0,
    double bottomInset = 0,
    double? thumbFraction,
  }) {
    final geometry = _trackGeometry(
      size,
      topInset: topInset,
      bottomInset: bottomInset,
    );
    final thumbHeight = resolveThumbHeight(
      geometry.trackHeight,
      thumbFraction: thumbFraction,
      enforceMinHeight: true,
    );
    final travel = geometry.trackHeight - thumbHeight;
    if (travel <= 0) return 0;
    return ((localY - geometry.trackY - thumbHeight / 2) / travel).clamp(
      0.0,
      1.0,
    );
  }

  ({double trackY, double trackHeight}) _trackGeometry(
    Size size, {
    double topInset = 0,
    double bottomInset = 0,
  }) {
    final trackY = topInset + _pad;
    final trackHeight = size.height - topInset - bottomInset - _pad * 2;
    return (trackY: trackY, trackHeight: trackHeight > 0 ? trackHeight : 0);
  }

  /// Cached paints — every Tier-1 paint tick hits this method, so allocating
  /// fresh [Paint] objects each time is wasted GC pressure.
  final Paint _trackPaint = Paint();
  final Paint _thumbPaint = Paint();

  /// Paint the uniform track and thumb.
  ///
  /// Paint order: full-track [ChatScrollbarThemeData.trackColor] RRect → thumb
  /// on top. [progress] is 0..1 scroll position; [thumbFraction] is viewport
  /// height ÷ estimated content extent (defaults to fixed [defaultThumbHeight]).
  void paint(
    Canvas canvas,
    Offset offset,
    Size size,
    double progress,
    TextDirection direction, {
    required ChatScrollbarThemeData theme,
    double topInset = 0,
    double bottomInset = 0,
    double? thumbFraction,
  }) {
    final trackWidth = isDragging ? _activeTrackWidth : _trackWidth;
    final trackX = direction == TextDirection.rtl
        ? offset.dx + _right
        : offset.dx + size.width - _right - trackWidth;
    final geometry = _trackGeometry(
      size,
      topInset: topInset,
      bottomInset: bottomInset,
    );
    final trackY = offset.dy + geometry.trackY;
    final trackHeight = geometry.trackHeight;
    if (trackHeight <= 0) return;

    _trackPaint.color = theme.trackColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackX, trackY, trackWidth, trackHeight),
        Radius.circular(trackWidth / 2),
      ),
      _trackPaint,
    );

    final thumbHeight = resolveThumbHeight(
      trackHeight,
      thumbFraction: thumbFraction,
    );
    final travel = trackHeight - thumbHeight;
    if (travel <= 0) return;
    final thumbY = trackY + travel * progress;
    _thumbPaint.color = isDragging
        ? theme.thumbDraggingColor
        : theme.thumbColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackX, thumbY, trackWidth, thumbHeight),
        Radius.circular(trackWidth / 2),
      ),
      _thumbPaint,
    );
  }
}
