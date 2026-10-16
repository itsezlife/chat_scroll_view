import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/input/panel_intents.dart';
import 'package:panel_shell/src/page/panel_page.dart';

/// How the type tabs show a page's [PanelTab].
enum PanelTabDisplay {
  /// The tab's name, resolved through the chrome strings.
  label,

  /// The tab's semantic icon, resolved through the chrome icon registry. The
  /// name is still its spoken label.
  icon,
}

/// The shrink-wrapped pill of type tabs with a selection capsule that follows
/// the pager.
///
/// [position] is the pager's continuous page, so the capsule tracks a drag
/// between two tabs and settles with the `headerReveal` motion role once the
/// pager rests. Selecting a tab invokes [PanelSelectPageIntent] through
/// `Actions`; the pill holds no selection state of its own.
class PanelTypeTabs extends StatefulWidget {
  /// Tabs for [pages], with the capsule following [position].
  const PanelTypeTabs({
    required this.pages,
    required this.position,
    required this.dragging,
    required this.selectedPageId,
    this.display = PanelTabDisplay.label,
    super.key,
  });

  /// The pages whose tabs are shown, in order.
  final List<PanelPage> pages;

  /// The pager's continuous page, in page units.
  final ValueListenable<double> position;

  /// Whether the pager is between pages (dragged or settling), during which
  /// the capsule follows [position] exactly instead of animating.
  final ValueListenable<bool> dragging;

  /// The selected page.
  final String selectedPageId;

  /// Whether the tabs show names or icons.
  final PanelTabDisplay display;

  /// Height of the pill.
  static const double height = 36;

  /// How far the capsule extends past a tab's content on each side.
  static const double capsulePad = 11;

  /// Horizontal padding inside each tab.
  static const double tabPadding = 16;

  @override
  State<PanelTypeTabs> createState() => _PanelTypeTabsState();
}

class _PanelTypeTabsState extends State<PanelTypeTabs>
    with SingleTickerProviderStateMixin {
  late List<GlobalKey> _contentKeys;
  late final AnimationController _settle;
  var _hasCapsule = false;
  var _fromLeft = 0.0;
  var _fromRight = 0.0;
  var _toLeft = 0.0;
  var _toRight = 0.0;
  Curve _curve = Curves.linear;

  @override
  void initState() {
    super.initState();
    _contentKeys = _newKeys();
    _settle = AnimationController(vsync: this);
    widget.position.addListener(_scheduleSync);
    widget.dragging.addListener(_scheduleSync);
    SchedulerBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(PanelTypeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.position, widget.position)) {
      oldWidget.position.removeListener(_scheduleSync);
      widget.position.addListener(_scheduleSync);
    }
    if (!identical(oldWidget.dragging, widget.dragging)) {
      oldWidget.dragging.removeListener(_scheduleSync);
      widget.dragging.addListener(_scheduleSync);
    }
    if (oldWidget.pages.length != widget.pages.length) {
      _contentKeys = _newKeys();
      _hasCapsule = false;
    }
    _scheduleSync();
  }

  @override
  void dispose() {
    widget.position.removeListener(_scheduleSync);
    widget.dragging.removeListener(_scheduleSync);
    _settle.dispose();
    super.dispose();
  }

  List<GlobalKey> _newKeys() =>
      List.generate(widget.pages.length, (_) => GlobalKey());

  void _scheduleSync() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _sync());
  }

  // The capsule spans the measured content of the tabs it sits between, so
  // it fits whatever the text, icon size, text scale or direction make of
  // them. Measuring needs laid-out children, hence the post-frame hop.
  (double, double)? _target(RenderBox strip) {
    final rects = <Rect?>[
      for (final key in _contentKeys)
        () {
          final box = key.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return null;
          return box.localToGlobal(Offset.zero, ancestor: strip) & box.size;
        }(),
    ];
    final last = widget.pages.length - 1.0;
    final page = widget.position.value.clamp(0.0, last);
    final i = page.floor().clamp(0, widget.pages.length - 1);
    final t = (page - i).clamp(0.0, 1.0);
    final a = rects[i];
    if (a == null) return null;
    final b = i + 1 < rects.length ? rects[i + 1] : null;
    final left = b == null ? a.left : a.left + (b.left - a.left) * t;
    final right = b == null ? a.right : a.right + (b.right - a.right) * t;
    return (left - PanelTypeTabs.capsulePad, right + PanelTypeTabs.capsulePad);
  }

  void _sync() {
    if (!mounted) return;
    final strip = context.findRenderObject() as RenderBox?;
    if (strip == null || !strip.hasSize) return;
    final target = _target(strip);
    if (target == null) return;
    final (left, right) = target;

    final page = widget.position.value;
    final fraction = page - page.floorToDouble();
    final midPage = fraction > 0.001 && fraction < 0.999;

    if (!_hasCapsule || widget.dragging.value || midPage) {
      _settle.stop();
      setState(() {
        _hasCapsule = true;
        _fromLeft = _toLeft = left;
        _fromRight = _toRight = right;
      });
      return;
    }
    if ((left - _toLeft).abs() < 0.5 && (right - _toRight).abs() < 0.5) return;

    final spec = ChromeMotionScope.of(context).specOf(MotionRole.headerReveal);
    final t = _settle.isAnimating ? _curve.transform(_settle.value) : 1.0;
    _fromLeft = _fromLeft + (_toLeft - _fromLeft) * t;
    _fromRight = _fromRight + (_toRight - _fromRight) * t;
    _toLeft = left;
    _toRight = right;
    _curve = spec.curve;
    _settle
      ..duration = spec.duration
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final action = ChromeThemeScope.actionOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: action.floatingFill,
        borderRadius: BorderRadius.circular(PanelTypeTabs.height / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PanelTypeTabs.height / 2),
        child: SizedBox(
          height: PanelTypeTabs.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Stack(
              children: [
                if (_hasCapsule)
                  AnimatedBuilder(
                    animation: _settle,
                    builder: (context, _) {
                      final t = _settle.isAnimating
                          ? _curve.transform(_settle.value)
                          : 1.0;
                      final left = _fromLeft + (_toLeft - _fromLeft) * t;
                      final right = _fromRight + (_toRight - _fromRight) * t;
                      return Positioned(
                        left: left,
                        width: (right - left).clamp(0.0, 400.0),
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: action.floatingSelectedFill,
                            borderRadius: BorderRadius.circular(
                              PanelTypeTabs.height / 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ValueListenableBuilder<double>(
                  valueListenable: widget.position,
                  builder: (context, position, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.pages.length; i++)
                        _TabButton(
                          contentKey: _contentKeys[i],
                          page: widget.pages[i],
                          display: widget.display,
                          selected: widget.pages[i].id == widget.selectedPageId,
                          progress: _selectProgress(i, position),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _selectProgress(int index, double page) {
    final delta = (page - index).abs();
    return delta >= 1 ? 0 : 1 - delta;
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.contentKey,
    required this.page,
    required this.display,
    required this.selected,
    required this.progress,
  });

  final GlobalKey contentKey;
  final PanelPage page;
  final PanelTabDisplay display;
  final bool selected;
  final double progress;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  var _focused = false;

  void _select() {
    Actions.maybeInvoke<PanelSelectPageIntent>(
      context,
      PanelSelectPageIntent(widget.page.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = ChromeThemeScope.actionOf(context);
    final label = ChromeStringsScope.panelOf(
      context,
    ).tabLabel(widget.page.tab.labelKey);
    final color = Color.lerp(
      action.floatingLabelMuted,
      action.floatingLabel,
      widget.progress,
    )!;
    final content = switch (widget.display) {
      PanelTabDisplay.label => Text(
        label,
        key: widget.contentKey,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.1,
        ),
      ),
      PanelTabDisplay.icon => SizedBox(
        key: widget.contentKey,
        child: ChromeIcon(widget.page.tab.icon, size: 22, color: color),
      ),
    };
    return Semantics(
      button: true,
      selected: widget.selected,
      label: label,
      onTap: _select,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _select();
              return null;
            },
          ),
        },
        child: ExcludeSemantics(
          child: ScalePressable(
            pressedScaleReduction: 0.025,
            releaseTension: 1.2,
            onPressed: _select,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PanelTypeTabs.height / 2),
                border: _focused
                    ? Border.all(color: action.floatingLabel, width: 1.5)
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PanelTypeTabs.tabPadding,
                ),
                child: Center(child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
