import 'package:chat_chrome/src/motion/scale_pressable.dart';
import 'package:chat_chrome/src/panel/emoji_panel_allow.dart';
import 'package:chat_chrome/src/panel/emoji_panel_bottom_bar.dart';
import 'package:chat_chrome/src/panel/emoji_panel_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shrink-wrapped type tabs + sliding indicator (`PagerSlidingTabStrip`).
class EmojiTypeTabsPill extends StatefulWidget {
  /// Creates the type-tabs pill.
  const EmojiTypeTabsPill({
    required this.tabs,
    required this.page,
    required this.pageDragging,
    required this.labels,
    required this.onSelectTab,
    required this.fill,
    required this.indicator,
    required this.activeText,
    required this.idleText,
    super.key,
  });

  /// Enabled tabs.
  final List<EmojiPanelTab> tabs;

  /// Continuous pager position.
  final double page;

  /// User is dragging the [PageView].
  final bool pageDragging;

  /// Host labels.
  final EmojiPanelLabels labels;

  /// Tab tap.
  final ValueChanged<int> onSelectTab;

  /// Pill fill.
  final Color fill;

  /// Sliding selected capsule.
  final Color indicator;

  /// Selected label color.
  final Color activeText;

  /// Idle label color.
  final Color idleText;

  @override
  State<EmojiTypeTabsPill> createState() => _EmojiTypeTabsPillState();
}

class _EmojiTypeTabsPillState extends State<EmojiTypeTabsPill>
    with SingleTickerProviderStateMixin {
  late List<GlobalKey> _textKeys;
  late final AnimationController _line;
  var _lineLeft = 0.0;
  var _lineRight = 0.0;
  var _fromLeft = 0.0;
  var _fromRight = 0.0;
  var _toLeft = 0.0;
  var _toRight = 0.0;
  var _hasLine = false;

  @override
  void initState() {
    super.initState();
    _textKeys = List<GlobalKey>.generate(
      widget.tabs.length,
      (_) => GlobalKey(),
    );
    _line =
        AnimationController(
          vsync: this,
          duration: EmojiPanelBottomBar.indicatorDuration,
        )..addListener(() {
          final t = Curves.easeOutQuint.transform(_line.value);
          _lineLeft = _fromLeft + (_toLeft - _fromLeft) * t;
          _lineRight = _fromRight + (_toRight - _fromRight) * t;
        });
    SchedulerBinding.instance.addPostFrameCallback((_) => _syncLine());
  }

  @override
  void didUpdateWidget(EmojiTypeTabsPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      _textKeys = List<GlobalKey>.generate(
        widget.tabs.length,
        (_) => GlobalKey(),
      );
      _hasLine = false;
    }
    if (oldWidget.page != widget.page ||
        oldWidget.pageDragging != widget.pageDragging ||
        oldWidget.labels != widget.labels) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _syncLine());
    }
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  double _hPad(EmojiPanelTab tab) => tab == EmojiPanelTab.gifs ? 12 : 16;

  List<Rect?> _textRects(RenderBox strip) {
    return <Rect?>[
      for (final key in _textKeys)
        () {
          final box = key.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return null;
          final topLeft = box.localToGlobal(Offset.zero, ancestor: strip);
          return topLeft & box.size;
        }(),
    ];
  }

  (double, double)? _targetLine(RenderBox strip) {
    final rects = _textRects(strip);
    final page = widget.page.clamp(0.0, widget.tabs.length - 1.0);
    final i = page.floor().clamp(0, widget.tabs.length - 1);
    final t = (page - i).clamp(0.0, 1.0);
    final a = rects[i];
    if (a == null) return null;
    final b = i + 1 < rects.length ? rects[i + 1] : null;
    final left = b == null ? a.left : a.left + (b.left - a.left) * t;
    final right = b == null ? a.right : a.right + (b.right - a.right) * t;
    final pad = EmojiPanelBottomBar.indicatorPad;
    return (left - pad, right + pad);
  }

  void _syncLine() {
    if (!mounted) return;
    final strip = context.findRenderObject() as RenderBox?;
    if (strip == null || !strip.hasSize) return;
    final target = _targetLine(strip);
    if (target == null) return;
    final (left, right) = target;

    final fraction = widget.page - widget.page.floorToDouble();
    final midPage = fraction > 0.001 && fraction < 0.999;

    if (!_hasLine || widget.pageDragging || midPage) {
      _line.stop();
      setState(() {
        _hasLine = true;
        _lineLeft = left;
        _lineRight = right;
        _fromLeft = left;
        _fromRight = right;
        _toLeft = left;
        _toRight = right;
      });
      return;
    }

    if ((left - _toLeft).abs() < 0.5 && (right - _toRight).abs() < 0.5) {
      return;
    }
    _fromLeft = _lineLeft;
    _fromRight = _lineRight;
    _toLeft = left;
    _toRight = right;
    _line
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.fill,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: EmojiPanelBottomBar.stripHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Stack(
            children: <Widget>[
              if (_hasLine)
                AnimatedBuilder(
                  animation: _line,
                  builder: (context, _) {
                    final t = _line.isAnimating
                        ? Curves.easeOutQuint.transform(_line.value)
                        : 1.0;
                    final left = _fromLeft + (_toLeft - _fromLeft) * t;
                    final right = _fromRight + (_toRight - _fromRight) * t;
                    return Positioned(
                      left: left,
                      width: (right - left).clamp(0.0, 400),
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.indicator,
                          borderRadius: BorderRadius.circular(
                            EmojiPanelBottomBar.stripHeight / 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (var i = 0; i < widget.tabs.length; i++)
                    _TabLabel(
                      textKey: _textKeys[i],
                      label: widget.labels.of(widget.tabs[i]),
                      hPad: _hPad(widget.tabs[i]),
                      progress: _selectProgress(i, widget.page),
                      activeText: widget.activeText,
                      idleText: widget.idleText,
                      onTap: () => widget.onSelectTab(i),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _selectProgress(int index, double page) {
    final delta = (page - index).abs();
    if (delta >= 1) return 0;
    return 1 - delta;
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.textKey,
    required this.label,
    required this.hPad,
    required this.progress,
    required this.activeText,
    required this.idleText,
    required this.onTap,
  });

  final GlobalKey textKey;
  final String label;
  final double hPad;
  final double progress;
  final Color activeText;
  final Color idleText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(idleText, activeText, progress)!;
    return ScalePressable(
      pressedScaleReduction: 0.025,
      releaseTension: 1.2,
      onPressed: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        child: Center(
          child: Text(
            label,
            key: textKey,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
