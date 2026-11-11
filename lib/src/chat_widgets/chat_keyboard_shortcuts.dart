import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

/// Wraps a [child] in a `Shortcuts` + `Actions` + `Focus` stack that handles
/// the canonical desktop keyboard navigation for a chat viewport. The scroll
/// keys are the shared [ViewportScrollKeys] (the panel catalogue binds the
/// same ones); this widget adds the focus and Escape:
///
/// * `ArrowUp` / `ArrowDown` — scroll by one [lineExtent] (default 60 px).
///   Tune to your typical message-row height — this is not derived from
///   text-line metrics.
/// * `PageUp` / `PageDown` — scroll by [pageExtent]; when `null`, falls back
///   to the wrapper's *own* measured height (via an internal `LayoutBuilder`)
///   times [pageFraction], so the page step matches the actual chat viewport
///   even when the wrapper sits under an `AppBar` / next to a side panel.
///   The latest measurement is captured each rebuild — keys fired before
///   the first layout fall back to the ambient `MediaQuery` height.
/// * `Home` — `controller.jumpTo(controller.oldestKnownId)` (or newest when
///   [reverse]). No-op when the target id is unknown (initial load).
/// * `End` — `controller.jumpTo(controller.newestKnownId)` (or oldest when
///   [reverse]).
/// * `Escape` — cancels active selection via
///   [ChatSelectionController.cancelSelection] when [selectionController] is
///   provided and selection is active.
///
/// `controller.scrollBy` is anchor-relative, so PageUp / ArrowUp always
/// reveal older history in both layouts — no direction flip is needed for
/// scroll. Home / End target ids do flip with [reverse]: in a chat-style
/// layout Home lands on the newest (top of the reverse stack), End on the
/// oldest.
///
/// ### Focus
///
/// The default [autofocus] is **false**. Most chat layouts host a composer
/// `TextField` below the viewport which should keep focus on mount — an
/// autofocused wrapper here would silently steal the cursor and force the
/// user to tap the input before typing. Pass `autofocus: true` when the
/// wrapper is the only focusable on the route.
///
/// Tapping or clicking the wrapped child also requests focus on the
/// internal node, so the shortcuts become live after the user interacts
/// with the chat even when [autofocus] is `false`. Focus is *not* re-
/// requested if the wrapper already owns it (no churn for repeated taps).
///
/// When [preserveExternalFocus] is `true` (typical chat demo with a
/// sibling composer `TextField`), pointer-down on the viewport does *not*
/// steal focus from an external editor — scroll and tap keep the soft
/// keyboard open. Shortcuts still activate when nothing else in the scope
/// is focused (tap viewport with no composer focus).
///
/// ### Example
///
/// ```dart
/// ChatKeyboardShortcuts(
///   controller: _controller,
///   child: ChatScrollView(
///     controller: _controller,
///     dataSource: _ds,
///     messageBuilder: _buildBubble,
///   ),
/// )
/// ```
class ChatKeyboardShortcuts extends StatefulWidget {
  /// Wraps [child] with desktop scroll shortcuts bound to [controller]
  /// boundary ids and optional [selectionController] Escape dismissal.
  const ChatKeyboardShortcuts({
    required this.controller,
    required this.child,
    this.selectionController,
    this.reverse = false,
    this.lineExtent = 60.0,
    this.pageExtent,
    this.pageFraction = 0.85,
    this.autofocus = false,
    this.preserveExternalFocus = false,
    super.key,
  });

  /// Scroll controller receiving [ChatScrollController.scrollBy] and jumps.
  final ChatScrollController controller;

  /// Typically a [ChatScrollView] — receives focus on tap when shortcuts
  /// should become active.
  final Widget child;

  /// Optional selection controller whose active selection mode is cancelled
  /// on Escape key press via [ChatSelectionController.cancelSelection].
  final ChatSelectionController? selectionController;

  /// Mirrors `ChatScrollView.reverse`. When `true`, PageUp / Home reveal
  /// older history (the chat-app intuition) instead of "scroll the
  /// container up".
  final bool reverse;

  /// Pixel step for arrow keys. Approximates one message-row scroll —
  /// tune to your typical row height. Not derived from text-line metrics.
  final double lineExtent;

  /// Pixel step for PageUp / PageDown. `null` derives the step from the
  /// wrapper's measured height × [pageFraction] at key-fire time (falling
  /// back to `MediaQuery.sizeOf(context).height` only before the first
  /// layout has produced a measurement).
  final double? pageExtent;

  /// Fraction of the viewport height to use as the page step when
  /// [pageExtent] is `null`. 0.85 keeps a small overlap between pages.
  final double pageFraction;

  /// When `true`, the wrapper claims keyboard focus on mount so the
  /// shortcuts respond without a click. Defaults to `false` so the typical
  /// chat layout's composer `TextField` keeps focus by default.
  final bool autofocus;

  /// When `true`, pointer-down on the viewport does not call
  /// [FocusNode.requestFocus] while another node in the enclosing
  /// [FocusScope] already has focus outside this wrapper (e.g. a sibling
  /// composer). Enables compose-while-scroll without dismissing the soft
  /// keyboard. Defaults to `false` so a viewport tap still activates
  /// desktop shortcuts when no external editor is focused.
  final bool preserveExternalFocus;

  @override
  State<ChatKeyboardShortcuts> createState() => _ChatKeyboardShortcutsState();
}

class _ChatKeyboardShortcutsState extends State<ChatKeyboardShortcuts> {
  late final FocusNode _focusNode;

  /// Static shortcut map — `const`-promotable so the framework can compare
  /// by identity across rebuilds rather than reallocating per frame. The
  /// scroll keys are [ViewportScrollKeys]'.
  static const Map<ShortcutActivator, Intent> _kShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _CancelSelectionIntent(),
      };

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    _CancelSelectionIntent: _CancelSelectionAction(this),
  };

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ChatKeyboardShortcuts');
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    widget.selectionController?.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(ChatKeyboardShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionController != widget.selectionController) {
      oldWidget.selectionController?.removeListener(_onSelectionChanged);
      widget.selectionController?.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    widget.selectionController?.removeListener(_onSelectionChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!_wantsFocusForSelection || _focusNode.hasFocus) return;
    _focusNode.requestFocus();
    // A host that lets go of its composer's focus when the selection starts
    // does so from its own listener, after this one, and `unfocus` hands the
    // focus to the enclosing scope: the request above is lost and the copy
    // and escape keys have no chat to reach. Asking again once the listeners
    // and the frame are done keeps the focus on the selection.
    if (_focusRetryScheduled) return;
    _focusRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRetryScheduled = false;
      if (mounted && _wantsFocusForSelection && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  bool _focusRetryScheduled = false;

  // Message selection without a text range: the keys act on the messages.
  bool get _wantsFocusForSelection {
    final selection = widget.selectionController;
    return selection != null &&
        selection.isSelectionMode &&
        !selection.isTextSelectionActive;
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    final selection = widget.selectionController;
    if (selection == null) return false;
    if (selection.isTextSelectionActive || selection.isSelectionMode) {
      selection.cancelSelection();
      return true;
    }
    return false;
  }

  /// The keys' pixels toward the end are toward the newest message.
  /// `controller.scrollBy` is *anchor*-relative — positive reveals older
  /// history and its sign does not flip with `reverse` (the message-id
  /// direction is the same in both layouts; `reverse` only changes
  /// short-content stacking and a11y labelling) — so PageUp / ArrowUp always
  /// scroll by a positive step.
  void _onScrollBy(double towardEnd) => widget.controller.scrollBy(-towardEnd);

  void _onJumpHome() {
    // In a chat-style (`reverse: true`) layout Home conventionally lands on
    // the most recent message — the top of a reverse-stacked list — so the
    // jump-target ids flip with reverse even though the scroll signs do
    // not.
    final id = widget.reverse
        ? widget.controller.newestKnownId
        : widget.controller.oldestKnownId;
    if (id != null) widget.controller.jumpTo(id);
  }

  void _onJumpEnd() {
    final id = widget.reverse
        ? widget.controller.oldestKnownId
        : widget.controller.newestKnownId;
    if (id != null) widget.controller.jumpTo(id);
  }

  /// Translucent pointer-down handler that grabs focus when the user taps
  /// or clicks anywhere inside the viewport. Without this the shortcuts
  /// are dead until the wrapper is focused by traversal — `autofocus` is
  /// off by default so the composer keeps focus on mount, but the user
  /// still expects a tap on the chat to make arrow keys work.
  ///
  /// The translucent `Listener` always fires regardless of who else
  /// consumed the pointer, so a tap on a focusable descendant (e.g. an
  /// inline reply input, a focusable selectable text inside a message)
  /// would otherwise have its focus immediately yanked back to the
  /// wrapper. Skip the grab when focus already landed inside our subtree.
  ///
  /// With [preserveExternalFocus], also skip when focus sits outside the
  /// wrapper (e.g. a sibling composer) so scroll/tap do not dismiss the
  /// soft keyboard.
  void _handlePointerDown(PointerDownEvent _) {
    if (_focusNode.hasFocus) return;
    final selection = widget.selectionController;
    final inSelectionMode =
        selection != null &&
        (selection.isSelectionMode || selection.isTextSelectionActive);
    if (!inSelectionMode) {
      final scope = _focusNode.enclosingScope;
      final focused = scope?.focusedChild ?? FocusManager.instance.primaryFocus;
      if (focused != null && focused != _focusNode) {
        // Walk up: if the current primary focus sits inside our subtree, the
        // descendant intentionally claimed focus on this tap. Leave it alone.
        FocusNode? n = focused;
        while (n != null) {
          if (n == _focusNode) return;
          n = n.parent;
        }
        if (widget.preserveExternalFocus) return;
      }
    }
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => ViewportScrollKeys(
    onScrollBy: _onScrollBy,
    onScrollToStart: _onJumpHome,
    onScrollToEnd: _onJumpEnd,
    lineExtent: widget.lineExtent,
    pageExtent: widget.pageExtent,
    pageFraction: widget.pageFraction,
    // The surface's main viewport: under a router it takes the keys nobody
    // nearer the focus took.
    role: ViewportScrollRole.primary,
    child: Shortcuts(
      shortcuts: _kShortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handlePointerDown,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

// --- Intents --------------------------------------------------------------

class _CancelSelectionIntent extends Intent {
  const _CancelSelectionIntent();
}

class _CancelSelectionAction extends Action<_CancelSelectionIntent> {
  _CancelSelectionAction(this._state);

  final _ChatKeyboardShortcutsState _state;

  @override
  bool isEnabled(_CancelSelectionIntent intent) {
    if (_state.widget.selectionController case final selection?) {
      return selection.isTextSelectionActive || selection.isSelectionMode;
    }
    return false;
  }

  @override
  Object? invoke(_CancelSelectionIntent intent) {
    _state.widget.selectionController?.cancelSelection();
    return null;
  }
}
