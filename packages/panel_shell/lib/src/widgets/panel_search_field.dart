import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_shell_controller.dart';

/// The search field the shell owns: one field, one query, one focus, for
/// whichever page is selected.
///
/// The field is a projection of `PanelShellController.search`. Typing calls
/// `setQuery`; gaining focus while search is closed calls `openSearch`; losing
/// focus withdraws the focus intent; and the trailing control clears the
/// query first and closes search on the second press. The text, the focus
/// node and the query therefore cannot disagree, and they survive page
/// switches because the field sits outside the pager.
///
/// Built on `EditableText`, so no Material ancestor is required. Hosts that
/// want a selection toolbar (paste on touch) pass [contextMenuBuilder].
class PanelSearchField extends StatefulWidget {
  /// A field projecting the search state of [controller].
  const PanelSearchField({
    required this.controller,
    this.contextMenuBuilder,
    super.key,
  });

  /// The controller whose search state the field shows and changes.
  final PanelShellController controller;

  /// Builds the text selection toolbar; null shows none.
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

  /// Size of the search icon and the progress indicator.
  static const double iconSize = 20;

  /// Largest text scale the fixed-height pill honours.
  static const double maxTextScale = 1.3;

  @override
  State<PanelSearchField> createState() => _PanelSearchFieldState();
}

class _PanelSearchFieldState extends State<PanelSearchField> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'PanelSearchField');
  var _syncing = false;

  PanelShellController get _shell => widget.controller;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
    _focus.addListener(_onFocus);
    _text.addListener(_onText);
    _applyState();
  }

  @override
  void didUpdateWidget(PanelSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _unbind(oldWidget.controller);
      _bind(widget.controller);
      _applyState();
    }
  }

  @override
  void dispose() {
    _unbind(widget.controller);
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

  void _onBusy() => setState(() {});

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
    if (state.isOpen && state.wantsFocus && !_focus.hasFocus) {
      _focus.requestFocus();
    } else if (!state.isOpen && _focus.hasFocus) {
      _focus.unfocus();
    }
  }

  void _onText() {
    if (_syncing) return;
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

  void _onTrailing() {
    if (_text.text.isNotEmpty) {
      _shell.setQuery('');
    } else {
      _shell.closeSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    final placeholder = ChromeThemeScope.placeholderOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final strings = ChromeStringsScope.of(context);
    final motion = ChromeMotionScope.of(context);
    final state = _shell.search.value;
    final showTrailing = state.isOpen || _text.text.isNotEmpty;
    final textStyle = TextStyle(color: panel.searchText, fontSize: 16);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: PanelSearchField.maxTextScale,
      child: SizedBox(
        height: PanelSearchField.height,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: PanelSearchField.pillMargin,
            end: PanelSearchField.pillMargin,
            top: PanelSearchField.pillMarginTop,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: panel.searchFill,
              borderRadius: BorderRadius.circular(
                PanelSearchField.pillHeight / 2,
              ),
            ),
            child: SizedBox(
              height: PanelSearchField.pillHeight,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: PanelSearchField.iconBox,
                    child: Center(
                      child: _shell.searchBusy.value
                          ? SizedBox.square(
                              dimension: PanelSearchField.iconSize - 4,
                              child: _Progress(color: panel.searchIcon),
                            )
                          : ChromeIcon(
                              ChromeIconId.search,
                              size: PanelSearchField.iconSize,
                              color: panel.searchIcon,
                            ),
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
                          EditableText(
                            controller: _text,
                            focusNode: _focus,
                            style: textStyle,
                            cursorColor: palette.accent,
                            backgroundCursorColor: panel.searchFill,
                            textInputAction: TextInputAction.search,
                            contextMenuBuilder: widget.contextMenuBuilder,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: motion.durationOf(MotionRole.search),
                    switchInCurve: motion.curveOf(MotionRole.search),
                    child: showTrailing
                        ? _TrailingButton(
                            key: const ValueKey('trailing'),
                            label: strings.panel.cancelAction,
                            color: panel.searchIcon,
                            onPressed: _onTrailing,
                          )
                        : const SizedBox.square(
                            key: ValueKey('none'),
                            dimension: PanelSearchField.iconBox,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailingButton extends StatelessWidget {
  const _TrailingButton({
    required this.label,
    required this.color,
    required this.onPressed,
    super.key,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onPressed();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: PanelSearchField.iconBox,
          child: Center(
            child: ChromeIcon(
              ChromeIconId.close,
              size: PanelSearchField.iconSize,
              color: color,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A small indeterminate ring in [color]; the widgets layer has none of its
/// own, and the Material one would need a Material ancestor.
class _Progress extends StatefulWidget {
  const _Progress({required this.color});

  final Color color;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _spin,
    child: CustomPaint(painter: _RingPainter(widget.color)),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, 0, 4.2, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.color != color;
}
