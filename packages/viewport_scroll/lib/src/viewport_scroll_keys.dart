import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One scroll key's move.
enum ViewportScrollStep {
  /// One line toward the start (`ArrowUp`).
  lineUp,

  /// One line toward the end (`ArrowDown`).
  lineDown,

  /// One page toward the start (`PageUp`).
  pageUp,

  /// One page toward the end (`PageDown`).
  pageDown,

  /// To the start (`Home`).
  start,

  /// To the end (`End`).
  end,
}

/// The intent of a [ViewportScrollKeys] key.
class ViewportScrollIntent extends Intent {
  /// An intent to make [step].
  const ViewportScrollIntent(this.step);

  /// The move.
  final ViewportScrollStep step;
}

/// The keyboard scroll keys of a viewport, bound around [child]:
///
/// * `ArrowUp` / `ArrowDown`: one [lineExtent] toward the start or the end.
/// * `PageUp` / `PageDown`: one [pageExtent], or when it is null this
///   widget's own measured height times [pageFraction] (so the step matches
///   the viewport, not the screen, under a bar or beside a panel; before the
///   first layout the ambient `MediaQuery` height stands in).
/// * `Home` / `End`: [onScrollToStart] / [onScrollToEnd]; without them the
///   keys are left to others.
///
/// [onScrollBy] takes pixels toward the end: positive reveals what is below,
/// whatever the viewport's own offset sign is.
///
/// The bindings act on a key the focused node below does not take: a
/// binding nearer the focus wins, and one that is disabled for the moment
/// (a roving focus that is not engaged) lets the key come here. This widget
/// holds no focus itself; the host decides when its viewport has it.
class ViewportScrollKeys extends StatefulWidget {
  /// Binds the scroll keys around [child].
  const ViewportScrollKeys({
    required this.onScrollBy,
    required this.child,
    this.onScrollToStart,
    this.onScrollToEnd,
    this.lineExtent = 60,
    this.pageExtent,
    this.pageFraction = 0.85,
    super.key,
  });

  /// Scrolls by pixels toward the end (negative: toward the start).
  final ValueChanged<double> onScrollBy;

  /// Goes to the start, or null to leave `Home` to others.
  final VoidCallback? onScrollToStart;

  /// Goes to the end, or null to leave `End` to others.
  final VoidCallback? onScrollToEnd;

  /// The arrow keys' step: 60 by default, about one chat row.
  final double lineExtent;

  /// The page keys' step, or null for the measured height times
  /// [pageFraction].
  final double? pageExtent;

  /// The share of the measured height a page key steps; 0.85 keeps an
  /// overlap between pages.
  final double pageFraction;

  /// The viewport and whatever holds its focus.
  final Widget child;

  /// The keys and their moves.
  static const Map<ShortcutActivator, Intent> shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp): ViewportScrollIntent(
          ViewportScrollStep.lineUp,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): ViewportScrollIntent(
          ViewportScrollStep.lineDown,
        ),
        SingleActivator(LogicalKeyboardKey.pageUp): ViewportScrollIntent(
          ViewportScrollStep.pageUp,
        ),
        SingleActivator(LogicalKeyboardKey.pageDown): ViewportScrollIntent(
          ViewportScrollStep.pageDown,
        ),
        SingleActivator(LogicalKeyboardKey.home): ViewportScrollIntent(
          ViewportScrollStep.start,
        ),
        SingleActivator(LogicalKeyboardKey.end): ViewportScrollIntent(
          ViewportScrollStep.end,
        ),
      };

  @override
  State<ViewportScrollKeys> createState() => _ViewportScrollKeysState();
}

class _ViewportScrollKeysState extends State<ViewportScrollKeys> {
  /// The latest height the layout gave this widget, or null before one.
  double? _height;

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ViewportScrollIntent: _ScrollAction(this),
  };

  void _scroll(ViewportScrollStep step) {
    final widget = this.widget;
    switch (step) {
      case ViewportScrollStep.lineUp:
        widget.onScrollBy(-widget.lineExtent);
      case ViewportScrollStep.lineDown:
        widget.onScrollBy(widget.lineExtent);
      case ViewportScrollStep.pageUp:
        widget.onScrollBy(-_page);
      case ViewportScrollStep.pageDown:
        widget.onScrollBy(_page);
      case ViewportScrollStep.start:
        widget.onScrollToStart?.call();
      case ViewportScrollStep.end:
        widget.onScrollToEnd?.call();
    }
  }

  double get _page =>
      widget.pageExtent ??
      (_height ?? MediaQuery.sizeOf(context).height) * widget.pageFraction;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: ViewportScrollKeys.shortcuts,
    child: Actions(
      actions: _actions,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedHeight) _height = constraints.maxHeight;
          return widget.child;
        },
      ),
    ),
  );
}

class _ScrollAction extends Action<ViewportScrollIntent> {
  _ScrollAction(this._state);

  final _ViewportScrollKeysState _state;

  @override
  bool isEnabled(ViewportScrollIntent intent) => switch (intent.step) {
    ViewportScrollStep.start => _state.widget.onScrollToStart != null,
    ViewportScrollStep.end => _state.widget.onScrollToEnd != null,
    _ => true,
  };

  @override
  Object? invoke(ViewportScrollIntent intent) {
    _state._scroll(intent.step);
    return null;
  }
}
