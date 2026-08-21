import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Telegram-like message edit transition for the demo bubble body.
///
/// Single progress factor (~250ms): crossfade old→new text, lerp reported
/// size (so the scroll viewport fan-out does not jump), and fade in an
/// “edited” meta prefix when [edited] becomes true.
///
/// Settled layout stays on [ChatMessageBody] (real [Text] for selection).
class DemoMessageEditBody extends StatefulWidget {
  /// Creates an edit-aware content + meta cluster.
  const DemoMessageEditBody({
    required this.content,
    required this.createdAt,
    required this.textStyle,
    required this.metaColor,
    required this.showStatus,
    required this.edited,
    this.sizeAlignment = Alignment.topLeft,
    this.spacing = 8,
    super.key,
  });

  /// Body text.
  final String content;

  /// Timestamp for the meta row.
  final DateTime createdAt;

  /// Body [Text] style.
  final TextStyle textStyle;

  /// Meta (time / edited / ticks) color.
  final Color metaColor;

  /// When true, show outgoing delivery ticks.
  final bool showStatus;

  /// When true, show the edited label in meta.
  final bool edited;

  /// Bubble cluster alignment while size lerps (outgoing → top-end).
  final AlignmentGeometry sizeAlignment;

  /// Gap between last text line and meta when packed inline.
  final double spacing;

  @override
  State<DemoMessageEditBody> createState() => _DemoMessageEditBodyState();
}

class _DemoMessageEditBodyState extends State<DemoMessageEditBody>
    with SingleTickerProviderStateMixin {
  /// Matches `ChatListItemAnimator.DEFAULT_DURATION`.
  static const Duration _duration = Duration(milliseconds: 250);

  /// Matches `ChatListItemAnimator.DEFAULT_INTERPOLATOR`.
  static const Curve _curve = Cubic(
    0.19919472913616398,
    0.010644531250000006,
    0.27920937042459737,
    0.91025390625,
  );

  late final AnimationController _controller;
  final GlobalKey _measureKey = GlobalKey();

  late String _current;
  String? _outgoing;
  late bool _edited;
  bool _editedEnter = false;
  Size? _fromSize;
  Size? _toSize;

  @override
  void initState() {
    super.initState();
    _current = widget.content;
    _edited = widget.edited;
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(covariant DemoMessageEditBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged = oldWidget.content != widget.content;
    final editedEnter = !oldWidget.edited && widget.edited;
    if (contentChanged || editedEnter || oldWidget.edited != widget.edited) {
      if (contentChanged || editedEnter) {
        _beginTransition(fromContent: _current, editedEnter: editedEnter);
      } else {
        _edited = widget.edited;
      }
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    setState(() {
      _outgoing = null;
      _fromSize = null;
      _toSize = null;
      _editedEnter = false;
    });
  }

  void _beginTransition({
    required String fromContent,
    required bool editedEnter,
  }) {
    final box = context.findRenderObject() as RenderBox?;
    final fromSize = box != null && box.hasSize ? box.size : null;

    _controller.stop();
    setState(() {
      _outgoing = fromContent;
      _current = widget.content;
      _edited = widget.edited;
      _editedEnter = editedEnter;
      _fromSize = fromSize;
      _toSize = null;
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final measured =
          _measureKey.currentContext?.findRenderObject() as RenderBox?;
      final toSize = measured != null && measured.hasSize
          ? measured.size
          : fromSize;
      setState(() => _toSize = toSize);
      _controller
        ..duration = _duration
        ..forward(from: 0);
    });
  }

  Widget _settled({
    required String content,
    required bool edited,
    double editedOpacity = 1,
    Key? key,
  }) => KeyedSubtree(
    key: key,
    child: ChatMessageBody(
      spacing: widget.spacing,
      content: Text(content, style: widget.textStyle),
      meta: _EditMetaRow(
        createdAt: widget.createdAt,
        color: widget.metaColor,
        showStatus: widget.showStatus,
        edited: edited,
        editedOpacity: editedOpacity,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final animating =
        _outgoing != null && (_controller.isAnimating || _toSize == null);

    if (!animating && _outgoing == null) {
      return _settled(content: _current, edited: _edited);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = _curve.transform(_controller.value.clamp(0.0, 1.0));
        final from = _fromSize;
        final to = _toSize;

        final editedOpacity = _editedEnter ? p : 1.0;

        final measure = Offstage(
          offstage: true,
          child: _settled(key: _measureKey, content: _current, edited: _edited),
        );

        if (from == null || to == null) {
          // Measuring target size — keep previous footprint if known.
          return Stack(
            children: [
              measure,
              if (from != null)
                SizedBox(
                  width: from.width,
                  height: from.height,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: widget.sizeAlignment,
                      minWidth: from.width,
                      maxWidth: math.max(from.width, 280),
                      minHeight: from.height,
                      maxHeight: math.max(from.height, 400),
                      child: _settled(
                        content: _outgoing ?? _current,
                        edited: _edited && !_editedEnter,
                      ),
                    ),
                  ),
                )
              else
                _settled(content: _outgoing ?? _current, edited: false),
            ],
          );
        }

        final w = lerpDouble(from.width, to.width, p)!;
        final h = lerpDouble(from.height, to.height, p)!;
        final layoutW = math.max(from.width, to.width);
        final layoutH = math.max(from.height, to.height);

        return Stack(
          children: [
            measure,
            SizedBox(
              width: w,
              height: h,
              child: ClipRect(
                child: OverflowBox(
                  alignment: widget.sizeAlignment,
                  minWidth: layoutW,
                  maxWidth: layoutW,
                  minHeight: layoutH,
                  maxHeight: layoutH,
                  child: Stack(
                    alignment: widget.sizeAlignment,
                    children: [
                      if (_outgoing != null)
                        Opacity(
                          opacity: (1 - p).clamp(0.0, 1.0),
                          child: IgnorePointer(
                            child: _settled(
                              content: _outgoing!,
                              edited: _edited && !_editedEnter,
                            ),
                          ),
                        ),
                      Opacity(
                        opacity: p.clamp(0.0, 1.0),
                        child: _settled(
                          content: _current,
                          edited: _edited,
                          editedOpacity: editedOpacity,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Time (+ optional “edited” + delivery ticks) for the meta slot.
class _EditMetaRow extends StatelessWidget {
  const _EditMetaRow({
    required this.createdAt,
    required this.color,
    required this.showStatus,
    required this.edited,
    this.editedOpacity = 1,
  });

  final DateTime createdAt;
  final Color color;
  final bool showStatus;
  final bool edited;
  final double editedOpacity;

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(createdAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (edited && editedOpacity > 0) ...<Widget>[
          Opacity(
            opacity: editedOpacity.clamp(0.0, 1.0),
            child: Text(
              'edited',
              style: TextStyle(color: color, fontSize: 11, height: 1),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(time, style: TextStyle(color: color, fontSize: 11, height: 1)),
        if (showStatus) ...<Widget>[
          const SizedBox(width: 3),
          Icon(Icons.done_all, size: 14, color: color),
        ],
      ],
    );
  }
}
