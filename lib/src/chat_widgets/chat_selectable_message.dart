import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_chrome.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_metrics.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Headless selection host: mode/select animations and freeze-on-exit.
///
/// The viewport owns the selection pointer (long-press / tap). This widget
/// only paints chrome — [chromeBuilder] must not attach a competing
/// detector. Chrome is built by [chromeBuilder] (defaults to
/// [DefaultSelectionChrome.wrap]). Restyle the bundled chrome with
/// [ChatSelectionThemeData]; replace layout entirely with
/// `ChatScrollView.selectionChromeBuilder`.
///
/// ### Pointer forwarding
///
/// While **message selection** is active under mobile policy, unselected rows
/// wrap the body in [IgnorePointer] so link/code chrome does not steal toggle
/// taps. Selected rows stay hittable so a further long-press can enter **text
/// selection** after the viewport yields (ADR 015). Desktop/web keeps children
/// live so inline activation works during message selection without clearing
/// membership. The **text selection subject** always forwards pointers so the
/// per-body markdown scope can own continuous text gestures.
///
/// ### Freeze on exit
///
/// When selection mode turns off — [ChatSelectionController.clear] or toggling
/// the last selected id — [ChatSelectionChromeState.selectProgress] stays at
/// its last value. Only [ChatSelectionChromeState.modeProgress] animates to 0,
/// so the check does not play an unselect animation. Re-entering snaps
/// select progress to the live set before the mode animation runs.
///
/// Live flags ([ChatSelectionChromeState.isSelected],
/// [ChatSelectionChromeState.isSelectionMode]) still rebuild immediately on
/// facade notifies — bubble [ChatMessageChangeTransition.selectedColor] must
/// not wait for an animation tick (drag cancel mid mode-enter).
class SelectableMessage extends StatefulWidget {
  /// Wraps [child] with animated selection chrome for [id].
  const SelectableMessage({
    required this.id,
    required this.controller,
    required this.allowed,
    required this.child,
    this.scrollController,
    this.chromeBuilder = DefaultSelectionChrome.wrap,
    super.key,
  });

  /// Message id this row represents.
  final int id;

  /// Shared selection state.
  final ChatSelectionController controller;

  /// Per-id chrome / check grants. Membership is enforced by the controller;
  /// this drives [ChatSelectionChromeState.showsCheck].
  final ChatSelectionAllowed allowed;

  /// Suppresses chrome-driven tap / long-press while a fling-cancel is in
  /// progress. The viewport applies the same guard to its own pointer.
  final ChatScrollController? scrollController;

  /// Builds chrome around [child]. Must be a stable tear-off.
  final ChatSelectionChromeBuilder chromeBuilder;

  /// Message body. Built once per host rebuild; chrome animates around it.
  final Widget child;

  @override
  State<SelectableMessage> createState() => _SelectableMessageState();
}

class _SelectableMessageState extends State<SelectableMessage>
    with TickerProviderStateMixin {
  // The controllers are made by the first animation. Every row of the list
  // has this state, and most never animate; two controllers each made two
  // tickers per row, each listening to the shared ticker mode, which every
  // row entering and leaving the list then had to join and leave.
  AnimationController? _mode;
  AnimationController? _select;

  /// The progress values while their controller does not exist yet.
  late double _modeAt;
  late double _selectAt;

  Duration _modeDuration = ChatSelectionMetrics.modeDuration;
  Duration _selectDuration = ChatSelectionMetrics.selectDuration;

  late Listenable _animation;
  late bool _liveMode;

  double get _modeValue => _mode?.value ?? _modeAt;
  double get _selectValue => _select?.value ?? _selectAt;

  AnimationController get _modeController =>
      _mode ??= _controller(_modeAt, _modeDuration);
  AnimationController get _selectController =>
      _select ??= _controller(_selectAt, _selectDuration);

  AnimationController _controller(double value, Duration duration) {
    final controller = AnimationController(
      vsync: this,
      duration: duration,
      value: value,
    );
    // The builder listens to the new controller from its next build on.
    _bindAnimation(controller);
    if (mounted) setState(() {});
    return controller;
  }

  // Merge the facade: [isSelected] / [isSelectionMode] can flip without an
  // animation tick (e.g. clearDrag mid mode-enter). Listening only to the
  // controllers left [ChatSelectionStateScope] stale and painted ghost
  // [ChatMessageChangeTransition.selectedColor].
  void _bindAnimation([AnimationController? made]) {
    _animation = Listenable.merge(<Listenable?>[
      _mode,
      _select,
      made,
      widget.controller,
    ]);
  }

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _liveMode = c.isSelectionMode;
    _modeAt = _liveMode ? 1.0 : 0.0;
    _selectAt = c.isSelected(widget.id) ? 1.0 : 0.0;
    _bindAnimation();
    c.addListener(_onSelectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = ChatScrollTheme.selectionOf(context);
    _modeDuration = theme.modeDuration;
    _selectDuration = theme.selectDuration;
    _mode?.duration = _modeDuration;
    _select?.duration = _selectDuration;
  }

  @override
  void didUpdateWidget(SelectableMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerSwapped = !identical(
      oldWidget.controller,
      widget.controller,
    );
    final idSwapped = oldWidget.id != widget.id;
    if (controllerSwapped) {
      oldWidget.controller.removeListener(_onSelectionChanged);
      widget.controller.addListener(_onSelectionChanged);
      _bindAnimation();
    }
    // Only re-sync when something the animation depends on actually changed.
    // Parent rebuilds with the same id+controller would otherwise enqueue
    // animation work for every visible message every frame.
    if (controllerSwapped || idSwapped) {
      _onSelectionChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelectionChanged);
    _mode?.dispose();
    _select?.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final c = widget.controller;
    final mode = c.isSelectionMode;
    final selected = c.isSelected(widget.id);
    if (mode && !_liveMode) {
      final at = selected ? 1.0 : 0.0;
      if (_select case final select?) {
        select.value = at;
      } else {
        _selectAt = at;
      }
      _modeController.animateTo(1);
    } else if (!mode && _liveMode) {
      _modeController.animateTo(0);
    } else if (mode) {
      final target = selected ? 1.0 : 0.0;
      // Without a controller there is nothing in flight to retarget.
      if (_select != null || _selectAt != target) {
        _selectController.animateTo(target);
      }
    }
    _liveMode = mode;
  }

  bool get _flingCancelSuppressesGestures =>
      widget.scrollController?.flingCancelSuppressesLongPress ?? false;

  void _handleLongPress() {
    if (_flingCancelSuppressesGestures) return;
    final c = widget.controller;
    // Already selected: long-press on an already-selected message is a no-op
    // for the controller, so don't buzz either.
    if (c.isSelected(widget.id)) return;
    HapticFeedback.vibrate();
    c.startSelection(widget.id);
  }

  void _handleTap() {
    if (_flingCancelSuppressesGestures) return;
    final c = widget.controller;
    // Outside selection mode a tap on a message does nothing (there is no
    // in-message interaction in this demo); inside it toggles the message.
    if (!c.isSelectionMode) return;
    c.toggle(widget.id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, child) {
      final isSubject =
          widget.controller.isTextSelectionActive &&
          widget.controller.textSelectionSubject == widget.id;
      final policy = widget.controller.selectionPolicy;
      // Mobile multiselect: ignore unselected bodies so link/code do not steal
      // row toggles. Selected rows stay hittable — viewport yields long-press
      // into the per-body text scope (ADR 015). Text **subject** stays
      // hittable for handles / drag. Host chrome gates via [canPerformActions].
      final suppressHostChrome =
          policy.suppressesLinkTapInMessageSelection &&
          (widget.controller.isSelectionMode ||
              widget.controller.isTextSelectionActive);
      final ignoreChildren =
          suppressHostChrome &&
          !isSubject &&
          !widget.controller.isSelected(widget.id);
      final canPerformActions = !suppressHostChrome;
      final state = ChatSelectionChromeState(
        id: widget.id,
        modeProgress: _modeValue.clamp(0.0, 1.0),
        selectProgress: _selectValue.clamp(0.0, 1.0),
        isSelectionMode: widget.controller.isSelectionMode,
        isSelected: widget.controller.isSelected(widget.id),
        showsCheck: widget.allowed.showsCheck,
        onTap: _handleTap,
        onLongPress: _handleLongPress,
        policy: policy,
        canPerformActions: canPerformActions,
      );
      return ChatSelectionStateScope(
        state: state,
        child: widget.chromeBuilder(
          context,
          state,
          IgnorePointer(ignoring: ignoreChildren, child: child!),
        ),
      );
    },
    child: widget.child,
  );
}

/// Ambient selection state for a single selectable message row.
///
/// Descendant widgets (such as bubble containers or avatars) can query this
/// to adapt their presentation when the row is selected.
class ChatSelectionStateScope extends InheritedWidget {
  /// Creates an ambient selection state scope for [state].
  const ChatSelectionStateScope({
    required this.state,
    required super.child,
    super.key,
  });

  /// The animated selection chrome state for this message row.
  final ChatSelectionChromeState state;

  /// Retrieves the ambient [ChatSelectionChromeState] for this message, or `null`.
  static ChatSelectionChromeState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChatSelectionStateScope>()
      ?.state;

  /// Retrieves the ambient [ChatSelectionChromeState] for this message.
  static ChatSelectionChromeState of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No ChatSelectionStateScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(ChatSelectionStateScope oldWidget) =>
      state.modeProgress != oldWidget.state.modeProgress ||
      state.selectProgress != oldWidget.state.selectProgress ||
      state.isSelected != oldWidget.state.isSelected ||
      state.isSelectionMode != oldWidget.state.isSelectionMode ||
      state.canPerformActions != oldWidget.state.canPerformActions;
}
