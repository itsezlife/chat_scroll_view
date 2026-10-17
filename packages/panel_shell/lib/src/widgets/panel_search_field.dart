import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' show ValueListenable;
import 'package:panel_shell/src/controller/panel_shell_controller.dart';
import 'package:panel_shell/src/widgets/panel_arrangement.dart';
import 'package:panel_shell/src/widgets/panel_search_state_icon.dart';

/// The search field of the panel: one field, one query, one focus, for
/// whichever page is selected.
///
/// The field is a projection of `PanelShellController.search`. Typing calls
/// `setQuery`; gaining focus while search is closed calls `openSearch`; losing
/// focus withdraws the focus intent; and the trailing control empties the
/// query. The text, the focus node and the query therefore cannot disagree.
///
/// ## The trailing control
///
/// A clear control that shows with text and nothing else, under either
/// arrangement: it empties the query and leaves search open. Search is left
/// through the controller (`closeSearch`, `handleBack`, Escape), never by a
/// control of the field. A cross over an empty field would have nothing to
/// clear, and the reference client's field shows none either.
///
/// ## Leading icon
///
/// A magnifier that morphs into a progress ring while a search is in flight
/// and, once a search for a non-empty query has settled, into a back chevron
/// that clears the query. See [PanelSearchStateIcon].
///
/// ## Where it sits
///
/// Where the field is drawn is the host's or the page's: the shell places it
/// above the pager for a page that declares `SearchPlacement.pinned`, and a
/// page that declares `SearchPlacement.inline` places it itself through
/// `PanelPageHost.buildSearchField`, inside its own scrolling content. The
/// field survives neither move: its text and focus are rebuilt from the
/// controller, which is why the controller holds them.
///
/// What the page shows while search is open with an emptied query is the
/// page's: the whole catalogue, so clearing is enough to see the grid again.
///
/// Built on `EditableText`, so no Material ancestor is required. Hosts that
/// want a selection toolbar (paste on touch) pass [contextMenuBuilder], or
/// give the shell one.
class PanelSearchField extends StatefulWidget {
  /// A field projecting the search state of [controller].
  const PanelSearchField({
    this.controller,
    this.shadow,
    this.contextMenuBuilder,
    super.key,
  });

  /// The controller whose search state the field shows and changes; null takes
  /// the one of the [PanelSearchFieldScope] above, which a `PanelShell` gives
  /// its pages.
  final PanelShellController? controller;

  /// Whether the hairline under the field shows: a page raises it while
  /// content scrolls beneath the pinned field. Null shows none.
  final ValueListenable<bool>? shadow;

  /// Builds the text selection toolbar; null falls back to the one the shell
  /// was given, if any.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  /// Layout height of the field row.
  static const double height = 50;

  /// Height of the painted pill.
  static const double pillHeight = 36;

  /// Space left and right of the pill.
  static const double pillMargin = 10;

  /// Space above the pill.
  static const double pillMarginTop = 6;

  /// Hit box of the leading and trailing controls.
  static const double iconBox = 36;

  /// Size of the leading icon.
  static const double iconSize = 24;

  /// Size of the clear glyph.
  static const double clearSize = 20;

  /// Largest text scale the fixed-height pill honours.
  static const double maxTextScale = 1.3;

  @override
  State<PanelSearchField> createState() => _PanelSearchFieldState();
}

class _PanelSearchFieldState extends State<PanelSearchField>
    with SingleTickerProviderStateMixin {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'PanelSearchField');
  final _editable = GlobalKey<EditableTextState>();
  late final AnimationController _shadow = AnimationController(
    vsync: this,
    value: (widget.shadow?.value ?? false) ? 1 : 0,
  );
  var _syncing = false;

  // Whether a search for a non-empty query has settled: the icon shows the
  // back chevron only then, not on the first keystroke before the progress
  // ring has had its turn.
  var _settled = false;

  late PanelShellController _shell;

  PanelShellController _resolve() {
    final given = widget.controller;
    if (given != null) return given;
    final scope = context
        .getInheritedWidgetOfExactType<PanelSearchFieldScope>();
    assert(
      scope != null,
      'A PanelSearchField without a controller needs a PanelSearchFieldScope '
      'above it: it belongs under a PanelShell.',
    );
    return scope!.controller;
  }

  @override
  void initState() {
    super.initState();
    _shell = _resolve();
    _bind(_shell);
    widget.shadow?.addListener(_onShadow);
    _focus.addListener(_onFocus);
    _text.addListener(_onText);
    _applyState();
  }

  @override
  void didUpdateWidget(PanelSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _unbind(_shell);
      _shell = _resolve();
      _bind(_shell);
      _applyState();
    }
    if (!identical(oldWidget.shadow, widget.shadow)) {
      oldWidget.shadow?.removeListener(_onShadow);
      widget.shadow?.addListener(_onShadow);
      _onShadow();
    }
  }

  @override
  void dispose() {
    _unbind(_shell);
    widget.shadow?.removeListener(_onShadow);
    _shadow.dispose();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text
      ..removeListener(_onText)
      ..dispose();
    super.dispose();
  }

  void _bind(PanelShellController controller) {
    controller.search.addListener(_onSearch);
    controller.searchBusy.addListener(_onBusy);
  }

  void _unbind(PanelShellController controller) {
    controller.search.removeListener(_onSearch);
    controller.searchBusy.removeListener(_onBusy);
  }

  void _onShadow() {
    final shown = widget.shadow?.value ?? false;
    final duration = ChromeMotionScope.of(context).durationOf(MotionRole.fade);
    if (shown) {
      unawaited(_shadow.animateTo(1, duration: duration));
    } else {
      unawaited(_shadow.animateBack(0, duration: duration));
    }
  }

  void _onBusy() {
    if (!_shell.searchBusy.value && _text.text.isNotEmpty) _settled = true;
    setState(() {});
  }

  void _onSearch() {
    _applyState();
    setState(() {});
  }

  // Brings the text and focus node to what the controller says. The guard
  // keeps the echo of our own change from being sent back as a new one.
  void _applyState() {
    final state = _shell.search.value;
    if (_text.text != state.query) {
      _syncing = true;
      _text.value = TextEditingValue(
        text: state.query,
        selection: TextSelection.collapsed(offset: state.query.length),
      );
      _syncing = false;
    }
    if (state.query.isEmpty) _settled = false;
    if (state.isOpen && state.wantsFocus && !_focus.hasFocus) {
      _focus.requestFocus();
    } else if (!state.isOpen && _focus.hasFocus) {
      _focus.unfocus();
    }
  }

  void _onText() {
    if (_syncing) return;
    if (_text.text.isEmpty) _settled = false;
    setState(() {});
    _shell.setQuery(_text.text);
  }

  void _onFocus() {
    final state = _shell.search.value;
    if (_focus.hasFocus) {
      if (!state.isOpen) {
        _shell.openSearch();
      } else {
        _shell.requestSearchFocus();
      }
    } else if (state.wantsFocus) {
      _shell.releaseSearchFocus();
    }
  }

  // A field with no selection gestures of its own: a press on it while it is
  // focused raises the keyboard the host may have lowered (the catalogue was
  // dragged), and asks search for its focus back.
  void _onFieldPressed() {
    if (!_focus.hasFocus) return;
    _editable.currentState?.requestKeyboard();
    final state = _shell.search.value;
    if (state.isOpen && !state.wantsFocus) _shell.requestSearchFocus();
  }

  void _clear() => _shell.setQuery('');

  PanelSearchIconState get _leading {
    if (_shell.searchBusy.value) return PanelSearchIconState.progress;
    if (_text.text.isNotEmpty && _settled) return PanelSearchIconState.back;
    return PanelSearchIconState.search;
  }

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    final placeholder = ChromeThemeScope.placeholderOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final strings = ChromeStringsScope.of(context);
    final textStyle = TextStyle(color: panel.searchText, fontSize: 16);
    final leading = _leading;
    final pointer =
        PanelArrangementScope.of(context) == PanelArrangement.pointer;
    final menu =
        widget.contextMenuBuilder ??
        PanelSearchFieldScope.maybeOf(context)?.contextMenuBuilder;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: PanelSearchField.maxTextScale,
      child: SizedBox(
        height: PanelSearchField.height,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: PanelSearchField.pillMargin,
                  end: PanelSearchField.pillMargin,
                  top: PanelSearchField.pillMarginTop,
                  bottom:
                      PanelSearchField.height -
                      PanelSearchField.pillMarginTop -
                      PanelSearchField.pillHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: panel.searchFill,
                    borderRadius: BorderRadius.circular(
                      PanelSearchField.pillHeight / 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      _Control(
                        label: strings.panel.clearAction,
                        onPressed: leading == PanelSearchIconState.back
                            ? _clear
                            : null,
                        child: PanelSearchStateIcon(
                          state: leading,
                          color: panel.searchIcon,
                          size: PanelSearchField.iconSize,
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          label: strings.semantics.searchFieldLabel,
                          textField: true,
                          child: Stack(
                            alignment: AlignmentDirectional.centerStart,
                            children: [
                              if (_text.text.isEmpty)
                                ExcludeSemantics(
                                  child: Text(
                                    strings.panel.searchHint,
                                    maxLines: 1,
                                    style: textStyle.copyWith(
                                      color: placeholder.fieldHint,
                                    ),
                                  ),
                                ),
                              // A press on a field that kept its focus
                              // when search let go of the keyboard (the
                              // catalogue was dragged) asks for it again.
                              Listener(
                                onPointerDown: (_) => _onFieldPressed(),
                                child: EditableText(
                                  key: _editable,
                                  controller: _text,
                                  focusNode: _focus,
                                  style: textStyle,
                                  cursorColor: palette.accent,
                                  backgroundCursorColor: panel.searchFill,
                                  textInputAction: TextInputAction.search,
                                  contextMenuBuilder: menu,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_text.text.isNotEmpty)
                        _Control(
                          label: pointer
                              ? strings.panel.cancelAction
                              : strings.panel.clearAction,
                          onPressed: _clear,
                          child: ChromeIcon(
                            ChromeIconId.close,
                            size: PanelSearchField.clearSize,
                            color: panel.searchIcon,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _shadow,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(_shadow.value);
                  if (t <= 0.001) return const SizedBox.shrink();
                  // Alpha on the fill, not an Opacity: no saveLayer while the
                  // line fades in over scrolling content.
                  return ColoredBox(
                    color: panel.hairline.withValues(
                      alpha: panel.hairline.a * t,
                    ),
                    child: const SizedBox(height: 1, width: double.infinity),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a `PanelShell` tells the search fields below it: the controller they
/// project and the selection toolbar they build, so a page that places the
/// field inline asks for neither.
@immutable
class PanelSearchFieldScope extends InheritedWidget {
  /// Gives the fields below [child] the shell's [controller] and
  /// [contextMenuBuilder].
  const PanelSearchFieldScope({
    required this.controller,
    required this.contextMenuBuilder,
    required super.child,
    super.key,
  });

  /// The controller whose search state the fields project.
  final PanelShellController controller;

  /// The selection toolbar builder of the shell, or null for none.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  /// The scope above [context], or null when the field is not under a shell.
  static PanelSearchFieldScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelSearchFieldScope>();

  @override
  bool updateShouldNotify(PanelSearchFieldScope oldWidget) =>
      oldWidget.controller != controller ||
      oldWidget.contextMenuBuilder != contextMenuBuilder;
}

// A square hit box that is a button when it has an action and inert when it
// has none, so the leading icon only answers taps as a back chevron.
//
// The tree is the same with an action or without: the leading icon gains and
// loses its action as it morphs, and a plain box swapped for a button would
// remount the icon, which then jumps to its new shape instead of morphing.
class _Control extends StatelessWidget {
  const _Control({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox.square(
      dimension: PanelSearchField.iconBox,
      child: Center(child: child),
    );
    final action = onPressed;
    final enabled = action != null;
    return Semantics(
      button: enabled,
      label: enabled ? label : null,
      onTap: action,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              action?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: enabled
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onTap: action,
          child: box,
        ),
      ),
    );
  }
}
