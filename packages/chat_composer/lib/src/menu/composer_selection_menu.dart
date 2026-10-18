import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/menu/overlay_back_button_listener.dart';
import 'package:chat_composer/src/menu/selection_menu_appearance.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chat_composer/src/menu/selection_menu_overflow.dart';
import 'package:chat_composer/src/menu/selection_menu_pages.dart';
import 'package:chat_composer/src/menu/selection_menu_position.dart';
import 'package:chat_composer/src/menu/selection_menu_shell.dart';
import 'package:chat_composer/src/menu/selection_menu_swipe_back.dart';
import 'package:chat_composer/src/shortcuts/composer_formatting_intents.dart';
import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/text/composer_link_edit.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart' show EntityListKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The composer's selection menu: a card over the selection with the clipboard
/// actions on one row and the formatting actions on a second page.
///
/// It replaces the platform's menu on every platform and is mounted by the
/// field's `contextMenuBuilder`. The main row holds Cut, Copy, Paste and Select
/// all, whichever the field offers, and a More button; the clipboard actions
/// that do not fit the row go to the top of the More page, above the
/// formatting actions of `ComposerSpec.formatting`. The More page slides in
/// from the right over 300 ms, with a Back tile at the end nearer the
/// selection, and can be swiped shut. A formatting action whose command cannot
/// apply to the selection stays on the page, greyed.
///
/// **Appearance.** The card fades in over 150 ms. After an action, Escape or
/// Back it fades out over 220 ms while drifting 5 dp away from the selection,
/// the content frozen as it was so the collapsing selection does not change
/// the rows mid-fade. The editable's toolbar wrapper fades the whole menu while
/// a scroll hides it or the selection is out of view; the open page stays
/// through that, because the card stays mounted.
///
/// **Selection and keyboard.** An action runs its command, then the menu
/// closes and the selection collapses to a caret at its extent (select all
/// stays open; a link prompt keeps the selection until it is answered). Escape
/// closes it, and so does Back, from either page. Tab moves focus into the
/// menu, where the traversal keys and Enter reach every action.
class ComposerSelectionMenu extends StatefulWidget {
  /// A menu over the selection of [editable], editing [text].
  const ComposerSelectionMenu({
    required this.editable,
    required this.text,
    required this.clipboard,
    required this.options,
    required this.tokens,
    required this.strings,
    required this.motion,
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

  /// Which formatting actions to offer (`ComposerSpec.formatting`).
  final Set<ComposerFormattingOption> options;

  /// Colours.
  final SelectionMenuTokens tokens;

  /// Labels.
  final FormattingStrings strings;

  /// Motion roles and speed.
  final ChromeMotionData motion;

  /// Asks for a link's URL; without it the menu offers no link action.
  final ComposerLinkPrompt? linkPrompt;

  /// Takes Back ahead of the soft keyboard while the menu is open.
  final ComposerBackPriority? backPriority;

  @override
  State<ComposerSelectionMenu> createState() => _ComposerSelectionMenuState();
}

class _ComposerSelectionMenuState extends State<ComposerSelectionMenu>
    with WidgetsBindingObserver {
  final _scope = FocusScopeNode(debugLabel: 'ComposerSelectionMenu');
  final _pages = SelectionMenuPageController();
  final _appearance = GlobalKey<SelectionMenuAppearanceState>();

  var _closing = false;
  // An action is running (a paste waiting for the clipboard); taps are ignored.
  var _running = false;
  // Focus has just moved into the menu on a Tab that is still being
  // dispatched.
  var _justEntered = false;

  // What the last build laid out, kept so that a closing menu goes on showing
  // it while the selection beneath it collapses.
  Widget? _frozen;

  // Run once the menu is gone: the link prompt.
  Future<void> Function()? _afterClose;
  VoidCallback? _releaseBack;

  // The editable's scroll position, which moves the selection under the menu.
  ViewportOffset? _scrollOffset;
  var _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    widget.text.addListener(_scheduleRefresh);
    _scrollOffset = widget.editable.renderEditable.offset
      ..addListener(_scheduleRefresh);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // After the frame, so the platform callback is added after the soft
      // keyboard's and wins priority.
      _releaseBack = widget.backPriority?.call(_onBack);
    });
  }

  @override
  void didUpdateWidget(ComposerSelectionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editable.mounted) {
      final next = widget.editable.renderEditable.offset;
      if (!identical(next, _scrollOffset)) {
        _scrollOffset?.removeListener(_scheduleRefresh);
        _scrollOffset = next..addListener(_scheduleRefresh);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.text.removeListener(_scheduleRefresh);
    _scrollOffset?.removeListener(_scheduleRefresh);
    _releaseBack?.call();
    _scope.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() => _scheduleRefresh();

  // --- Following the selection ---

  // The card follows the selection: a scroll or a metrics change rebuilds it
  // with fresh anchors. Two frames, because the editable lays out after the
  // frame the scroll happened in, and its endpoints are those of the next.
  void _scheduleRefresh() {
    if (_refreshScheduled || !mounted || _closing) return;
    _refreshScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted || _closing) return;
      setState(() {});
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closing) setState(() {});
      });
    });
  }

  // --- Closing ---

  void _collapseSelection() {
    final selection = widget.text.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    widget.text.selection = TextSelection.collapsed(
      offset: selection.extentOffset,
    );
  }

  // Leaves the card and goes: the content stays as it was while it fades, the
  // selection collapses to a caret at its extent in parallel, and the toolbar
  // is hidden when the fade is over. [collapse] false keeps the selection and
  // its handles for an action that still needs them.
  Future<void> _close({bool collapse = true}) async {
    if (_closing) return;
    _closing = true;
    final leave = _appearance.currentState?.dismiss() ?? Future<void>.value();
    if (collapse) _collapseSelection();
    await leave;
    final editable = widget.editable;
    if (editable.mounted) {
      // Focus in the menu goes back to the field's own node, which would
      // otherwise be left to the nearest scope.
      if (_scope.hasFocus) editable.widget.focusNode.requestFocus();
      editable.hideToolbar(collapse);
    }
    final run = _afterClose;
    _afterClose = null;
    if (run != null) unawaited(run());
  }

  Future<void> _select(SelectionMenuItem item) async {
    if (_closing || _running) return;
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
        _scheduleRefresh();
      case SelectionMenuAfter.dismiss:
        await _close();
      case SelectionMenuAfter.dismissKeepingSelection:
        await _close(collapse: false);
    }
  }

  // The link action: asks for the URL once the menu is gone, so the dialog
  // does not open under a fading card, and applies it to the selection as it
  // was.
  void _beginLink() {
    final prompt = widget.linkPrompt;
    if (prompt == null) return;
    final context = widget.editable.context;
    _afterClose = ComposerLinkEdit(
      text: widget.text,
      prompt: prompt,
      context: context,
      isAlive: () => context.mounted,
    ).ask;
  }

  // The command that makes the selected lines items of [kind]; null while the
  // composer has no list editing, which the registered action tells.
  VoidCallback? _toggleList(EntityListKind kind) {
    final context = widget.editable.context;
    if (Actions.maybeFind<ToggleListIntent>(context) == null) return null;
    final intent = ToggleListIntent(kind);
    return () => Actions.maybeInvoke(context, intent);
  }

  // --- Keyboard and Back ---

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || _closing) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_close());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab && !_scope.hasFocus) {
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
  // arrows, move between the actions.
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

  // Back closes the whole menu from either page, and keeps the keyboard.
  Future<bool> _onBack() async {
    if (!mounted) return false;
    final editable = widget.editable;
    // Not awaited: the leave outlives the back event, and waiting for it would
    // hold the pop.
    unawaited(_close());
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
    if (_closing && frozen != null) return frozen;
    final editable = widget.editable;
    if (!editable.mounted || !editable.renderEditable.hasSize) {
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final view = View.of(context);
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

    final theme = Theme.of(context);
    final tokens = widget.tokens;
    final label = selectionMenuLabelStyle(theme, tokens);
    final placement = _placement(media, view, editable);
    final clipboard = [
      for (final i in items)
        if (i.kind.isClipboard) i,
    ];
    final formatting = [
      for (final i in items)
        if (!i.kind.isClipboard) i,
    ];
    final split = splitSelectionMenuRow(
      labels: [for (final item in clipboard) item.label],
      style: label,
      maxWidth: placement.maxWidth,
      textScaler: scaler,
      textDirection: direction,
    );
    final pageItems = [...clipboard.skip(split.count), ...formatting];
    final hasMore = pageItems.isNotEmpty;
    final maxHeight = placement.maxHeight > 0 ? placement.maxHeight : null;
    final page = widget.motion.specOf(MotionRole.menuPage);

    final menu = OverlayBackButtonListener(
      // The dispatcher is the field's: the overlay this is built in is not
      // under the Router.
      parentDispatcher: Router.maybeOf(editable.context)?.backButtonDispatcher,
      onBackButtonPressed: _onBack,
      child: MediaQuery(
        data: media.copyWith(textScaler: scaler),
        // A child of the field's own focus node, so that focus in the menu is
        // still focus in the field: the editable closes its toolbar when it
        // loses focus.
        child: FocusScope(
          node: _scope,
          parentNode: editable.widget.focusNode,
          onKeyEvent: _onScopeKey,
          child: SelectionMenuPositioned(
            placement: placement,
            // The page narrows the card; centring it as the row keeps one edge
            // still as it opens.
            referenceWidth:
                split.width +
                (hasMore ? SelectionMenuMetrics.moreButtonWidth : 0),
            child: SelectionMenuAppearance(
              key: _appearance,
              fitsAbove: placement.fitsAbove,
              motion: widget.motion,
              child: SelectionMenuCard(
                tokens: tokens,
                maxWidth: placement.maxWidth,
                maxHeight: maxHeight,
                child: SelectionMenuSwipeBack(
                  controller: _pages,
                  pageColor: tokens.background,
                  dim: tokens.pageDim,
                  duration: page.duration,
                  curve: page.curve,
                  borderRadius: SelectionMenuTokens.cornerRadius,
                  root: SelectionMenuRootPage(
                    items: clipboard.sublist(0, split.count),
                    tokens: tokens,
                    labelStyle: label,
                    moreLabel: widget.strings.moreAction,
                    onSelected: (item) => unawaited(_select(item)),
                    onOpenMore: hasMore ? _pages.openForeground : null,
                  ),
                  foreground: hasMore
                      ? SizedBox(
                          width: SelectionMenuMetrics.pageWidth,
                          child: SelectionMenuMorePage(
                            items: pageItems,
                            tokens: tokens,
                            labelStyle: label,
                            backLabel: widget.strings.backAction,
                            // Next to the text the menu points at.
                            backPlacement: placement.fitsAbove
                                ? SelectionMenuBackPlacement.bottom
                                : SelectionMenuBackPlacement.top,
                            maxHeight: maxHeight,
                            onSelected: (item) => unawaited(_select(item)),
                            onBack: _pages.closeForeground,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _frozen = menu;
    return menu;
  }

  SelectionMenuPlacement _placement(
    MediaQueryData media,
    FlutterView view,
    ExtendedEditableTextState editable,
  ) {
    // The platform's own insets as well as the app's: an ancestor may have
    // consumed the app's.
    final raw = EdgeInsets.fromViewPadding(
      view.viewPadding,
      view.devicePixelRatio,
    );
    final keyboard = EdgeInsets.fromViewPadding(
      view.viewInsets,
      view.devicePixelRatio,
    ).bottom;
    return computeSelectionMenuPlacement(
      screen: media.size,
      safe: EdgeInsets.only(
        top: math.max(
          raw.top,
          math.max(media.viewPadding.top, media.padding.top),
        ),
        bottom: math.max(
          raw.bottom,
          math.max(media.viewPadding.bottom, media.padding.bottom),
        ),
      ),
      keyboardInset: math.max(keyboard, media.viewInsets.bottom),
      anchors: selectionMenuAnchors(editable),
    );
  }
}
