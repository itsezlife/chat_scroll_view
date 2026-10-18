import 'dart:async';
import 'dart:math' as math;

import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/menu/overlay_back_button_listener.dart';
import 'package:chat_composer/src/menu/selection_menu_card.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_layout.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chat_composer/src/shortcuts/composer_formatting_intents.dart';
import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/text/composer_link_edit.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart' show EntityListKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The composer's selection menu: the reference client's floating toolbar.
///
/// It replaces the platform's menu on every platform and is mounted by the
/// field's `contextMenuBuilder`. What it offers is the clipboard actions the
/// field gives it and the formatting items of `ComposerSpec.formatting` that
/// the selection allows; how it looks and moves is the reference's, row by row
/// (see [SelectionMenuMetrics] and `chrome_foundation`'s menu roles).
///
/// **Visibility.** The menu animates itself (it is returned inside
/// `ExtendedSelfFadingToolbar`, so the editable applies no fade of its own).
/// It enters over 150 ms; it hides over 100 ms while the editable says the
/// selection is scrolled or out of view and while the selection moves; and it
/// dismisses after an item with a 150 ms hold and a 100 ms fade. A moving
/// selection hides it only once it has been shown for 500 ms, and brings it
/// back 50 ms after the last move. The overflow page, if open, stays open
/// through a hide and a show: the widget stays mounted.
///
/// **Selection and keyboard.** An item runs its command, then the platform
/// action mode's finish: the menu closes and the selection collapses to a
/// caret (select all stays open; a link prompt keeps the selection until it is
/// answered). Escape closes it, and Tab moves focus into it, where the
/// traversal keys and Enter reach every item.
class ComposerSelectionMenu extends StatefulWidget {
  /// A menu over the selection of [editable], editing [text].
  const ComposerSelectionMenu({
    required this.editable,
    required this.text,
    required this.clipboard,
    required this.visibility,
    required this.options,
    required this.tokens,
    required this.strings,
    required this.motion,
    required this.metrics,
    this.linkPrompt,
    this.backPriority,
    super.key,
  });

  /// The editable the menu serves: its selection, its geometry and its toolbar.
  final ExtendedEditableTextState editable;

  /// The text the formatting commands edit.
  final ComposerTextController text;

  /// The clipboard actions, in order, ready to run.
  final List<SelectionMenuClipboardItem> clipboard;

  /// False while the editable has the toolbar hidden (a scroll in progress, the
  /// selection out of the viewport).
  final ValueListenable<bool> visibility;

  /// Which formatting items to offer (`ComposerSpec.formatting`).
  final Set<ComposerFormattingOption> options;

  /// Colours.
  final SelectionMenuTokens tokens;

  /// Labels.
  final FormattingStrings strings;

  /// Motion roles and speed.
  final ChromeMotionData motion;

  /// Geometry for the platform.
  final SelectionMenuMetrics metrics;

  /// Asks for a link's URL; without it the menu offers no link item.
  final ComposerLinkPrompt? linkPrompt;

  /// Takes Back ahead of the soft keyboard while the menu is open.
  final ComposerBackPriority? backPriority;

  @override
  State<ComposerSelectionMenu> createState() => _ComposerSelectionMenuState();
}

class _ComposerSelectionMenuState extends State<ComposerSelectionMenu>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _fade = AnimationController(vsync: this);
  final _scope = FocusScopeNode(debugLabel: 'ComposerSelectionMenu');

  // --- Visibility inputs ---
  late var _hostVisible = widget.visibility.value;
  var _moving = false;
  var _outOfBounds = false;
  var _dismissing = false;
  // An item is running (a paste waiting for the clipboard); taps are ignored.
  var _running = false;
  // Focus has just moved into the menu on a Tab that is still being
  // dispatched.
  var _justEntered = false;

  // Whether the menu has been shown long enough for a moving selection to hide
  // it.
  var _graceElapsed = false;
  Timer? _graceTimer;
  Timer? _settleTimer;
  Timer? _dismissTimer;

  // The selection's rectangle, in global coordinates, as last measured.
  Rect? _content;
  var _checkScheduled = false;

  // Run once the menu is gone: the link prompt.
  Future<void> Function()? _afterDismiss;
  VoidCallback? _releaseBack;
  _Built? _built;
  _Built? _frozen;

  final _cardKey = GlobalKey<SelectionMenuCardState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    widget.visibility.addListener(_onHostVisibility);
    widget.text.addListener(_scheduleCheck);
    widget.editable.renderEditable.offset.addListener(_scheduleCheck);
    // The editable is laid out already when its toolbar is shown, so the first
    // build has the selection's rectangle and the card enters on the first
    // frame, not the second.
    _content = _contentRect();
    _outOfBounds = _content == null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
      _updateFade();
      // After the frame, so the platform callback is added after the soft
      // keyboard's and wins priority.
      _releaseBack = widget.backPriority?.call(_onBack);
    });
  }

  @override
  void didUpdateWidget(ComposerSelectionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.visibility, widget.visibility)) {
      oldWidget.visibility.removeListener(_onHostVisibility);
      widget.visibility.addListener(_onHostVisibility);
      _onHostVisibility();
    }
    _scheduleCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.visibility.removeListener(_onHostVisibility);
    widget.text.removeListener(_scheduleCheck);
    if (widget.editable.mounted) {
      widget.editable.renderEditable.offset.removeListener(_scheduleCheck);
    }
    _graceTimer?.cancel();
    _settleTimer?.cancel();
    _dismissTimer?.cancel();
    _releaseBack?.call();
    _scope.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() => _scheduleCheck();

  // --- Visibility ---

  void _onHostVisibility() {
    _hostVisible = widget.visibility.value;
    _updateFade();
  }

  bool get _shouldShow =>
      _hostVisible && !_moving && !_outOfBounds && !_dismissing;

  void _updateFade() {
    if (!mounted || _dismissing) return;
    if (_shouldShow) {
      if (_fade.status == AnimationStatus.forward || _fade.value == 1) return;
      final enter = widget.motion.specOf(MotionRole.menuEnter);
      _fade.animateTo(1, duration: enter.duration, curve: enter.curve);
      // Shown again: a move may hide it only after it has stayed 500 ms.
      _graceElapsed = false;
      _graceTimer?.cancel();
      _graceTimer = Timer(SelectionMenuTiming.movingGrace, () {
        _graceElapsed = true;
      });
    } else {
      final exit = widget.motion.specOf(MotionRole.menuExit);
      _fade.animateBack(0, duration: exit.duration, curve: exit.curve);
    }
  }

  // The selection's rectangle moved: hide while it keeps moving, but only once
  // the menu has been up for the grace period.
  void _onContentMoved() {
    if (!_graceElapsed && !_moving) return;
    _moving = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(SelectionMenuTiming.settleDebounce, () {
      _moving = false;
      _updateFade();
    });
    _updateFade();
  }

  // --- Geometry ---

  void _scheduleCheck() {
    if (_checkScheduled || !mounted || _dismissing) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted && !_dismissing) _measure();
    });
  }

  void _measure() {
    final next = _contentRect();
    final previous = _content;
    final outOfBounds = next == null;
    final moved =
        next != null && previous != null && !_sameRect(next, previous);
    final first = previous == null && next != null;
    if (outOfBounds == _outOfBounds && !moved && !first) return;
    setState(() {
      _content = next ?? previous;
      _outOfBounds = outOfBounds;
    });
    if (moved) _onContentMoved();
    _updateFade();
  }

  static bool _sameRect(Rect a, Rect b) =>
      (a.left - b.left).abs() < 0.5 &&
      (a.top - b.top).abs() < 0.5 &&
      (a.right - b.right).abs() < 0.5 &&
      (a.bottom - b.bottom).abs() < 0.5;

  // The selection's bounds in global coordinates, clipped to the field's own
  // box (with the reference's 20 dp allowance below it); null when none of it
  // is in view.
  Rect? _contentRect() {
    final editable = widget.editable;
    if (!editable.mounted) return null;
    final render = editable.renderEditable;
    final selection = editable.textEditingValue.selection;
    if (!render.attached || !render.hasSize || !selection.isValid) return null;
    final Rect local;
    if (selection.isCollapsed) {
      local = render.getLocalRectForCaret(selection.extent);
    } else {
      final boxes = render.getBoxesForSelection(selection);
      if (boxes.isEmpty) return null;
      local = boxes
          .map((box) => box.toRect())
          .reduce((a, b) => a.expandToInclude(b));
    }
    final toGlobal = render.getTransformTo(null);
    final content = MatrixUtils.transformRect(toGlobal, local);
    final view = MatrixUtils.transformRect(toGlobal, Offset.zero & render.size);
    const allowance = 20.0;
    final left = math.max(content.left, view.left);
    final top = math.max(content.top, view.top);
    final right = math.min(content.right, view.right);
    final bottom = math.min(content.bottom, view.bottom + allowance);
    if (left > right || top > bottom) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  // --- Dismissal ---

  Future<void> _dismiss({required SelectionMenuAfter after}) async {
    if (_dismissing) return;
    _frozen = _built;
    _dismissing = true;
    _graceTimer?.cancel();
    _settleTimer?.cancel();
    final editable = widget.editable;
    final text = widget.text;
    final exit = widget.motion.specOf(MotionRole.menuExit);
    final delay = widget.motion.speed.scale(SelectionMenuTiming.dismissDelay);
    final completer = Completer<void>();
    // The reference holds the card for 150 ms, then fades it over 100 ms
    // with no slide.
    _dismissTimer = Timer(delay, () {
      if (!mounted) {
        completer.complete();
        return;
      }
      _fade
          .animateBack(0, duration: exit.duration, curve: exit.curve)
          .whenCompleteOrCancel(completer.complete);
    });
    if (after == SelectionMenuAfter.dismiss) {
      final selection = text.selection;
      if (selection.isValid && !selection.isCollapsed) {
        text.selection = TextSelection.collapsed(offset: selection.end);
      }
    }
    setState(() {});
    await completer.future;
    final run = _afterDismiss;
    _afterDismiss = null;
    if (editable.mounted) {
      // Focus in the menu goes back to the field's own node, which would
      // otherwise be left to the nearest scope.
      if (_scope.hasFocus) editable.widget.focusNode.requestFocus();
      editable.hideToolbar(after == SelectionMenuAfter.dismiss);
    }
    if (run != null) unawaited(run());
  }

  Future<void> _select(SelectionMenuItem item) async {
    if (_dismissing || _running) return;
    _running = true;
    try {
      await item.onSelected();
    } finally {
      _running = false;
    }
    if (!mounted) return;
    switch (item.after) {
      case SelectionMenuAfter.stay:
        setState(() {});
        _scheduleCheck();
      case SelectionMenuAfter.dismiss:
      case SelectionMenuAfter.dismissKeepingSelection:
        await _dismiss(after: item.after);
    }
  }

  // The link item: asks for the URL once the menu is gone, so the dialog does
  // not open under a fading card, and applies it to the selection as it was.
  void _beginLink() {
    final prompt = widget.linkPrompt;
    if (prompt == null) return;
    final context = widget.editable.context;
    _afterDismiss = ComposerLinkEdit(
      text: widget.text,
      prompt: prompt,
      context: context,
      isAlive: () => context.mounted,
    ).ask;
  }

  VoidCallback? _toggleList(EntityListKind kind) {
    final context = widget.editable.context;
    final intent = ToggleListIntent(kind);
    final action = Actions.maybeFind<ToggleListIntent>(context);
    if (action == null ||
        !action.isActionEnabled ||
        !action.isEnabled(intent)) {
      return null;
    }
    return () => Actions.maybeInvoke(context, intent);
  }

  // --- Keyboard and Back ---

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || _dismissing) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_dismiss(after: SelectionMenuAfter.dismiss));
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        !_scope.hasFocus &&
        _fade.value > 0.5) {
      // Tab from the field enters the menu. The focus change is applied at
      // once so that this very key press, which goes on to the focus tree,
      // lands on the menu and is told it only entered.
      _justEntered = true;
      _scope.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      // A scope with nothing focused in it takes focus itself.
      if (FocusManager.instance.primaryFocus == _scope) {
        _scope.nextFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
      }
      return true;
    }
    return false;
  }

  // The menu's own keys, once focus is in it: Tab and Shift+Tab, and the
  // arrows, move between the items; Escape closes it.
  KeyEventResult _onScopeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      if (_justEntered) {
        _justEntered = false;
        return KeyEventResult.handled;
      }
      final current = FocusManager.instance.primaryFocus ?? node;
      if (HardwareKeyboard.instance.isShiftPressed) {
        current.previousFocus();
      } else {
        current.nextFocus();
      }
      return KeyEventResult.handled;
    }
    _justEntered = false;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      _ => null,
    };
    if (direction != null) {
      (FocusManager.instance.primaryFocus ?? node).focusInDirection(direction);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<bool> _onBack() async {
    if (!mounted) return false;
    // Back out of the overflow page before out of the menu, as the page's own
    // Back row does.
    final card = _cardKey.currentState;
    if (card != null && card.isOpen) {
      card.close();
      return true;
    }
    final editable = widget.editable;
    // Not awaited: the leave animation outlives the back event.
    unawaited(_dismiss(after: SelectionMenuAfter.dismiss));
    // Closing the toolbar can drop the input connection; the field stays
    // focused and its keyboard should stay up.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (editable.mounted) editable.requestKeyboard();
    });
    return true;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final frozen = _frozen;
    if (_dismissing && frozen != null) return _card(frozen);
    final content = _content;
    if (content == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final scaler = media.textScaler.clamp(
      maxScaleFactor: SelectionMenuMetrics.maxTextScale,
    );
    final direction = Directionality.of(context);
    final items = SelectionMenuItems.of(
      text: widget.text,
      options: widget.options,
      strings: widget.strings,
      clipboard: widget.clipboard,
      canLink: widget.linkPrompt != null,
      onLink: _beginLink,
      toggleList: _toggleList,
    );
    if (items.isEmpty) return const SizedBox.shrink();

    final padding = EdgeInsets.fromLTRB(
      math.max(media.padding.left, media.viewPadding.left),
      math.max(media.padding.top, media.viewPadding.top),
      math.max(media.padding.right, media.viewPadding.right),
      math.max(
        media.viewInsets.bottom,
        math.max(media.padding.bottom, media.viewPadding.bottom),
      ),
    );
    final viewport = Rect.fromLTRB(
      padding.left,
      padding.top,
      media.size.width - padding.right,
      media.size.height - padding.bottom,
    );
    final style = TextStyle(
      inherit: false,
      color: widget.tokens.text,
      fontSize: SelectionMenuMetrics.itemTextSize,
      fontWeight: FontWeight.w500,
      height: 1.2,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      fontFamilyFallback: Theme.of(
        context,
      ).textTheme.bodyMedium?.fontFamilyFallback,
    );

    final widths = [
      for (final item in items)
        _textWidth(
          item.label,
          selectionMenuLabelStyle(style, item.labelStyle),
          scaler,
          direction,
        ),
    ];
    final budget = SelectionMenuLayout.budget(viewport.width);
    final row = SelectionMenuLayout.mainRow(textWidths: widths, budget: budget);
    final mainItems = items.sublist(0, row.count);
    final overflowItems = items.sublist(row.count);
    final mainWidths = [
      for (var i = 0; i < row.count; i++)
        math.min(
          SelectionMenuLayout.mainItemWidth(
            widths[i],
            first: i == 0,
            last: i == items.length - 1,
          ),
          budget,
        ),
    ];
    final overflowWidth = SelectionMenuLayout.overflowWidth(
      widths.sublist(row.count),
      budget: budget,
    );
    final below = widget.metrics.belowClearance;
    final placement = SelectionMenuLayout.place(
      viewport: viewport,
      content: Rect.fromLTRB(
        content.left,
        content.top,
        content.right,
        content.bottom + below,
      ),
      main: Size(row.width, SelectionMenuMetrics.rowHeight),
      overflowWidth: overflowWidth,
      overflowCount: overflowItems.length,
      rtl: direction == TextDirection.rtl,
    );
    final built = _Built(
      placement: placement,
      mainItems: mainItems,
      mainWidths: mainWidths,
      overflowItems: overflowItems,
      style: style,
      scaler: scaler,
    );
    _built = built;
    return _card(built);
  }

  static double _textWidth(
    String label,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  Widget _card(_Built built) {
    // The dispatcher is the field's: the overlay this is built in is not under
    // the Router.
    final dispatcher = Router.maybeOf(
      widget.editable.context,
    )?.backButtonDispatcher;
    return OverlayBackButtonListener(
      parentDispatcher: dispatcher,
      onBackButtonPressed: _onBack,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: built.scaler),
        // A child of the field's own focus node, so that focus in the menu is
        // still focus in the field: the editable closes its toolbar when it
        // loses focus.
        child: FocusScope(
          node: _scope,
          parentNode: widget.editable.widget.focusNode,
          onKeyEvent: _onScopeKey,
          child: Stack(
            children: [
              SelectionMenuCard(
                key: _cardKey,
                placement: built.placement,
                mainItems: built.mainItems,
                mainWidths: built.mainWidths,
                overflowItems: built.overflowItems,
                itemStyle: built.style,
                tokens: widget.tokens,
                strings: widget.strings,
                motion: widget.motion,
                opacity: _fade,
                onSelected: (item) => unawaited(_select(item)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// What the last build laid out, kept so that a dismissal can go on showing it
// while the selection beneath it collapses.
class _Built {
  const _Built({
    required this.placement,
    required this.mainItems,
    required this.mainWidths,
    required this.overflowItems,
    required this.style,
    required this.scaler,
  });

  final SelectionMenuPlacement placement;
  final List<SelectionMenuItem> mainItems;
  final List<double> mainWidths;
  final List<SelectionMenuItem> overflowItems;
  final TextStyle style;
  final TextScaler scaler;
}
