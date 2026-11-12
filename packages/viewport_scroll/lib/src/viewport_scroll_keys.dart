import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

/// What a [ViewportScrollKeys] viewport is to the [ViewportScrollRouter]
/// above it.
enum ViewportScrollRole {
  /// Nothing: its keys work only while the focus is in it.
  none,

  /// The surface's main viewport (a chat): it takes the scroll keys nobody
  /// nearer the focus took, so they work from the moment the surface shows.
  primary,

  /// A viewport that takes the scroll keys while the mouse is over it (a
  /// panel's catalogue), whoever holds the focus.
  pointer,
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
///
/// Under a [ViewportScrollRouter], [role] says what the viewport is to it:
/// the [ViewportScrollRole.primary] one takes the keys nobody nearer took,
/// and a [ViewportScrollRole.pointer] one takes them while the mouse is over
/// it, from any viewport's keys and from the router.
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
    this.role = ViewportScrollRole.none,
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

  /// What the viewport is to the [ViewportScrollRouter] above it, if any.
  final ViewportScrollRole role;

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

  _ViewportScrollRouterState? _router;

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ViewportScrollIntent: _ScrollAction(this),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = _ViewportScrollRouterScope.maybeOf(context);
    if (identical(router, _router)) return;
    _leave();
    _router = router;
    if (widget.role == ViewportScrollRole.primary) router?._primaries.add(this);
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  void _leave() {
    final router = _router;
    if (router == null) return;
    router._primaries.remove(this);
    if (identical(router._pointer, this)) router._pointer = null;
  }

  // The viewport a key here moves: the one under the mouse, else this one.
  _ViewportScrollKeysState get _target => _router?._pointer ?? this;

  bool _handles(ViewportScrollStep step) => switch (step) {
    ViewportScrollStep.start => widget.onScrollToStart != null,
    ViewportScrollStep.end => widget.onScrollToEnd != null,
    _ => true,
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
  Widget build(BuildContext context) {
    Widget child = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) _height = constraints.maxHeight;
        return widget.child;
      },
    );
    if (widget.role == ViewportScrollRole.pointer) {
      child = MouseRegion(
        opaque: false,
        onEnter: (event) {
          if (event.kind == PointerDeviceKind.mouse) _router?._pointer = this;
        },
        onExit: (_) {
          if (identical(_router?._pointer, this)) _router?._pointer = null;
        },
        child: child,
      );
    }
    return Shortcuts(
      shortcuts: ViewportScrollKeys.shortcuts,
      child: Actions(actions: _actions, child: child),
    );
  }
}

class _ScrollAction extends Action<ViewportScrollIntent> {
  _ScrollAction(this._state);

  final _ViewportScrollKeysState _state;

  @override
  bool isEnabled(ViewportScrollIntent intent) =>
      _state._target._handles(intent.step);

  @override
  Object? invoke(ViewportScrollIntent intent) {
    _state._target._scroll(intent.step);
    return null;
  }
}

/// Routes the scroll keys of a surface (a screen with a chat, its composer
/// and a panel) to one of its [ViewportScrollKeys] viewports, so that every
/// scroll key has an owner whoever holds the focus:
///
/// | Focus | ArrowUp / ArrowDown | PageUp / PageDown | Home / End |
/// |---|---|---|---|
/// | A text field, empty | target | target | target |
/// | A text field, collapsed caret at the start (Up) or the end (Down) | target | target | the field (a Mac: target) |
/// | A text field, caret elsewhere or a selection | the field | target | the field (a Mac: target) |
/// | A viewport's keys (a chat, a pressed catalogue) | target | target | target |
/// | Anything else under the router | target | target | target |
///
/// The target is the [ViewportScrollRole.pointer] viewport under the mouse,
/// else the [ViewportScrollRole.primary] one. A text field gives up only
/// what it cannot use: its arrows move its caret until the caret is at the
/// end it moves toward, and Home and End move it in any text, except on
/// Apple platforms, where they move no caret and so always scroll; the page keys
/// do nothing for a one-paragraph field, so they always scroll.
///
/// With [holdsFocus] the router keeps the keys from falling to nobody: when
/// the focus would rest on the route's scope itself (a field left with
/// Escape or a click elsewhere, a route shown with nothing focused), a node
/// of the router takes it, so the keys come here. When the surface shows,
/// and each time [refocusOn] notifies, [focusFallback] is asked instead: the
/// node it names takes the focus once mounted (from anything under the
/// router but a text field), and a null answer has the router's node take
/// it, from a text field too (a selection in the surface holds the keys). A
/// desktop surface sets it; a touch one leaves it off, as its focus drives
/// the soft keyboard.
class ViewportScrollRouter extends StatefulWidget {
  /// Routes the scroll keys of the viewports under [child].
  const ViewportScrollRouter({
    required this.child,
    this.holdsFocus = false,
    this.focusFallback,
    this.refocusOn,
    super.key,
  });

  /// Whether a node of the router takes the focus when nobody else under
  /// the route has it.
  final bool holdsFocus;

  /// With [holdsFocus], who has the focus when the surface shows and after
  /// [refocusOn] notifies: a node (the surface's text field, which the
  /// reference desktop client focuses when it shows a chat), or null for the
  /// router's own (while a selection in the surface holds the keys).
  final ValueGetter<FocusNode?>? focusFallback;

  /// With [holdsFocus], what changes [focusFallback]'s answer (a message or
  /// text selection that starts or ends): the router asks it again when it
  /// notifies.
  final Listenable? refocusOn;

  /// The surface.
  final Widget child;

  @override
  State<ViewportScrollRouter> createState() => _ViewportScrollRouterState();
}

class _ViewportScrollRouterState extends State<ViewportScrollRouter> {
  final List<_ViewportScrollKeysState> _primaries = [];
  _ViewportScrollKeysState? _pointer;
  final FocusNode _node = FocusNode(
    debugLabel: 'ViewportScrollRouter',
    skipTraversal: true,
  );
  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    ViewportScrollIntent: _RouterAction(this),
  };
  var _holdScheduled = false;

  _ViewportScrollKeysState? get _target => _pointer ?? _primaries.lastOrNull;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    widget.refocusOn?.addListener(_onRefocus);
    _onFocusChanged();
  }

  @override
  void didUpdateWidget(ViewportScrollRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.refocusOn, widget.refocusOn)) {
      oldWidget.refocusOn?.removeListener(_onRefocus);
      widget.refocusOn?.addListener(_onRefocus);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    widget.refocusOn?.removeListener(_onRefocus);
    _node.dispose();
    super.dispose();
  }

  // Frames the router still waits for [ViewportScrollRouter.focusFallback]
  // to be mounted while it holds the focus itself.
  var _fallbackWait = 0;
  static const int _fallbackFrames = 60;

  // Whether the fallback is due the focus: when the surface shows and after
  // each [ViewportScrollRouter.refocusOn] notification, not when a field is
  // left later (a press elsewhere in the surface, which may start a text
  // selection there, keeps what it pressed).
  var _wantsFallback = true;

  void _onRefocus() {
    _wantsFallback = true;
    _onFocusChanged();
  }

  // The focus rests on the route's scope itself: nobody under it has the
  // keys, so the fallback when it is due (or the router's own node) takes
  // them, once the frame is done.
  void _onFocusChanged() {
    if (!widget.holdsFocus || _holdScheduled) return;
    _holdScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _holdScheduled = false;
        if (!mounted || !widget.holdsFocus) return;
        final scope = _node.enclosingScope;
        final primary = FocusManager.instance.primaryFocus;
        final wants = _wantsFallback;
        final under = primary != null && primary.ancestors.contains(_node);
        final fallback = wants ? widget.focusFallback?.call() : null;
        // Asked, the fallback says the router holds the keys itself (a
        // selection in the surface): it takes them from a field too.
        final yields =
            wants && widget.focusFallback != null && fallback == null;
        final resting =
            primary == null ||
            primary == scope ||
            primary == _node ||
            (under && yields) ||
            (wants && under && _RouterAction._fieldOf(primary) == null);
        if (scope == null || !resting) {
          // Something under the router took the focus itself.
          if (under) _wantsFallback = false;
          _fallbackWait = 0;
          return;
        }
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        if (fallback != null &&
            fallback.context != null &&
            fallback.canRequestFocus) {
          _wantsFallback = false;
          _fallbackWait = 0;
          fallback.requestFocus();
          return;
        }
        if (primary != _node) _node.requestFocus();
        // The fallback is not mounted yet (the surface still loads): look
        // again next frame, for a while.
        if (fallback != null && _fallbackWait++ < _fallbackFrames) {
          _onFocusChanged();
        } else {
          _wantsFallback = false;
          _fallbackWait = 0;
        }
      })
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => _ViewportScrollRouterScope(
    state: this,
    child: Shortcuts(
      shortcuts: ViewportScrollKeys.shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(focusNode: _node, child: widget.child),
      ),
    ),
  );
}

class _ViewportScrollRouterScope extends InheritedWidget {
  const _ViewportScrollRouterScope({required this.state, required super.child});

  final _ViewportScrollRouterState state;

  static _ViewportScrollRouterState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ViewportScrollRouterScope>()
      ?.state;

  @override
  bool updateShouldNotify(_ViewportScrollRouterScope oldWidget) =>
      !identical(state, oldWidget.state);
}

class _RouterAction extends Action<ViewportScrollIntent> {
  _RouterAction(this._router);

  final _ViewportScrollRouterState _router;

  @override
  bool isEnabled(ViewportScrollIntent intent) {
    final target = _router._target;
    if (target == null || !target._handles(intent.step)) return false;
    return switch (_fieldOf(FocusManager.instance.primaryFocus)) {
      final field? => _fieldGivesUp(intent.step, field.currentTextEditingValue),
      null => true,
    };
  }

  @override
  Object? invoke(ViewportScrollIntent intent) {
    _router._target?._scroll(intent.step);
    return null;
  }

  // Whether a field holding [value] has no use for [step].
  static bool _fieldGivesUp(ViewportScrollStep step, TextEditingValue? value) {
    if (value == null || value.text.isEmpty) return true;
    final selection = value.selection;
    final caret = selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : null;
    return switch (step) {
      ViewportScrollStep.pageUp || ViewportScrollStep.pageDown => true,
      ViewportScrollStep.lineUp => caret == 0,
      ViewportScrollStep.lineDown => caret == value.text.length,
      ViewportScrollStep.start || ViewportScrollStep.end => !_homeEndEdit,
    };
  }

  // Whether Home and End move a text field's caret on this platform. On
  // Apple platforms they scroll a text view and leave the caret (the
  // caret's line ends are Cmd+Left / Cmd+Right), so a field has no use for
  // them; elsewhere they take the caret to its line's start and end.
  static bool get _homeEndEdit => switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => false,
    _ => true,
  };

  // The text field [node] belongs to, or null when it is none's.
  static TextInputClient? _fieldOf(FocusNode? node) {
    final context = node?.context;
    if (context == null) return null;
    if (context case StatefulElement(:final TextInputClient state)) {
      return state;
    }
    TextInputClient? found;
    context.visitAncestorElements((element) {
      if (element case StatefulElement(:final TextInputClient state)) {
        found = state;
        return false;
      }
      return true;
    });
    return found;
  }
}
