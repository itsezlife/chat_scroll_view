import 'dart:math' as math;

import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/input/soft_keyboard_mode.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chat_composer/src/view/listen_value_builder.dart';
import 'package:chat_composer/src/view/slot_boxes.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The default panel: the entity-aware text field bound to a
/// [ComposerController].
///
/// It lays the text out in the controller's `ComposerTextController`, scrolls
/// with the controller's `fieldScroll`, and reports two things back as data:
/// its height (`reportFieldHeight`) and, while an input query is open, where
/// the caret is drawn (`reportCaretAnchor`).
///
/// **Soft keyboard.** While the controller's `softKeyboard` is
/// [SoftKeyboardMode.suppressed] the field declares `TextInputType.none`:
/// focus, caret, selection and hardware keys work, and the platform keeps its
/// on-screen keyboard down. No platform channel is used.
///
/// The platform keeps the input type a field attached with, and a change of
/// mode alone is meant to show nothing: a panel that closes lifts the
/// suppression and the keyboard stays down. When the keyboard is wanted (the
/// host calls `requestKeyboard`, or the user taps the field), a field that
/// attached suppressed **re-attaches**: it drops focus and takes it back a
/// frame later, with the type the mode declares now, which raises the
/// keyboard. Caret and selection are as they were; the hand-off with a panel is
/// the host's presentation's job.
///
/// Needs a Material ancestor and Material localisations, which the text
/// selection menu draws with.
class ComposerField extends StatefulWidget {
  /// A field for [controller].
  const ComposerField({
    required this.controller,
    required this.enabled,
    this.onTap,
    this.onPointerDown,
    this.onPointerEnd,
    super.key,
  });

  /// The input state.
  final ComposerController controller;

  /// Whether the field takes input.
  final bool enabled;

  /// Called when the field is tapped, also while it already has focus. A host
  /// uses it to leave a panel for the keyboard.
  final VoidCallback? onTap;

  /// Called when a pointer goes down on the field, before the field reacts.
  final VoidCallback? onPointerDown;

  /// Called when that pointer lifts or is cancelled.
  final VoidCallback? onPointerEnd;

  @override
  State<ComposerField> createState() => _ComposerFieldState();
}

class _ComposerFieldState extends State<ComposerField> {
  final _textFieldKey = GlobalKey();
  var _anchorScheduled = false;
  var _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.text.addListener(_scheduleAnchor);
    widget.controller.keyboardRequests.addListener(_onKeyboardRequest);
    widget.controller.caretReveals.addListener(_onCaretReveal);
    widget.controller.focusNode.addListener(_onFocus);
    _onFocus();
  }

  @override
  void didUpdateWidget(ComposerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.text.removeListener(_scheduleAnchor);
      oldWidget.controller.keyboardRequests.removeListener(_onKeyboardRequest);
      oldWidget.controller.caretReveals.removeListener(_onCaretReveal);
      oldWidget.controller.focusNode.removeListener(_onFocus);
      widget.controller.text.addListener(_scheduleAnchor);
      widget.controller.keyboardRequests.addListener(_onKeyboardRequest);
      widget.controller.caretReveals.addListener(_onCaretReveal);
      widget.controller.focusNode.addListener(_onFocus);
      _onFocus();
    }
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_scheduleAnchor);
    widget.controller.keyboardRequests.removeListener(_onKeyboardRequest);
    widget.controller.caretReveals.removeListener(_onCaretReveal);
    widget.controller.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  // The mode the field was last built with, and the one it attached to the
  // platform with when it took focus (null without focus).
  SoftKeyboardMode? _builtMode;
  SoftKeyboardMode? _attachedMode;
  var _reattaching = false;

  // The field attached while suppressed and the keyboard is allowed now: the
  // platform still holds no keyboard type for it.
  bool get _attachedStale =>
      _attachedMode == SoftKeyboardMode.suppressed &&
      widget.controller.softKeyboard.value == SoftKeyboardMode.auto;

  void _onFocus() {
    if (_reattaching) return;
    _attachedMode = widget.controller.focusNode.hasFocus ? _builtMode : null;
  }

  // Answered after the frame, so the field is built with the option the host
  // set together with the request.
  void _onKeyboardRequest() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _raiseKeyboard();
    });
  }

  void _raiseKeyboard() {
    final controller = widget.controller;
    if (!widget.enabled ||
        _reattaching ||
        controller.softKeyboard.value == SoftKeyboardMode.suppressed) {
      return;
    }
    final node = controller.focusNode;
    if (!node.hasFocus) {
      node.requestFocus();
      return;
    }
    if (!_attachedStale) {
      _editableTextState()?.requestKeyboard();
      return;
    }
    _reattaching = true;
    node.unfocus();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reattaching = false;
      if (!mounted || !widget.enabled) return;
      node.requestFocus();
    });
  }

  // After the frame that lays the edit out, so the line is measured where the
  // caret landed. Edits in one frame reveal once.
  void _onCaretReveal() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (mounted) _revealCaretLine();
    });
  }

  // Scrolls the field, at once, by just enough to show the whole line the
  // caret is on, as the reference clients' fields do. The stock
  // `bringIntoView` reveals a box of the preferred line height around the
  // caret, which can stop a fraction of a pixel short of the line as laid
  // out; the line's own glyph boxes (the caret alone for an empty line) are
  // the exact extent.
  void _revealCaretLine() {
    final selection = widget.controller.selection;
    final scroll = widget.controller.fieldScroll;
    final render = _editableTextState()?.renderEditable;
    if (render == null || !selection.isValid || !scroll.hasClients) return;
    final caret = render.getLocalRectForCaret(selection.extent);
    final line = render.getLineAtOffset(selection.extent);
    var top = caret.top;
    var bottom = caret.bottom;
    // An empty field has no line (the range is -1..-1, which the painter
    // asserts on): the caret is all there is to show.
    if (line.isValid) {
      for (final box in render.getBoxesForSelection(
        TextSelection(baseOffset: line.start, extentOffset: line.end),
      )) {
        top = math.min(top, box.top);
        bottom = math.max(bottom, box.bottom);
      }
    }
    final shift = switch (render.size.height) {
      final height when bottom > height => bottom - height,
      _ when top < 0 => top,
      _ => 0.0,
    };
    if (shift == 0) return;
    final position = scroll.position;
    scroll.jumpTo(
      clampDouble(
        position.pixels + shift,
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _onTap() {
    widget.onTap?.call();
    if (_attachedStale) _raiseKeyboard();
  }

  void _scheduleAnchor() {
    if (_anchorScheduled || widget.controller.query.value == null) return;
    _anchorScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _anchorScheduled = false;
      if (mounted) _reportAnchor();
    });
  }

  void _reportAnchor() {
    final controller = widget.controller;
    if (controller.query.value == null) return;
    final editable = _editableTextState();
    final fieldBox = context.findRenderObject();
    final selection = controller.selection;
    if (editable == null || !selection.isValid) return;
    if (fieldBox is! RenderBox || !fieldBox.hasSize) return;
    final render = editable.renderEditable;
    final caret = render.getLocalRectForCaret(
      TextPosition(offset: selection.baseOffset),
    );
    final topLeft = fieldBox.globalToLocal(render.localToGlobal(caret.topLeft));
    controller.reportCaretAnchor(topLeft & caret.size);
  }

  // The stock TextField does not expose its EditableText; the caret rectangle
  // is only available from the render object the text lays out in.
  EditableTextState? _editableTextState() {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element case StatefulElement(state: final EditableTextState state)) {
        found = state;
        return;
      }
      element.visitChildren(visit);
    }

    _textFieldKey.currentContext?.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final composer = ChromeThemeScope.composerOf(context);
    final placeholder = ChromeThemeScope.placeholderOf(context);
    final strings = ChromeStringsScope.composerOf(context);
    const lineHeight = ComposerMetrics.fieldLineHeight;
    const fontSize = ComposerMetrics.fieldFontSize;

    return HeightReporter(
      onHeight: controller.reportFieldHeight,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => widget.onPointerDown?.call(),
        onPointerUp: (_) => widget.onPointerEnd?.call(),
        onPointerCancel: (_) => widget.onPointerEnd?.call(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: ComposerMetrics.islandHeight,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              top: ComposerMetrics.fieldTopPad,
              bottom: ComposerMetrics.fieldBottomPad,
              end: ComposerMetrics.fieldEndPad,
            ),
            child: ListenValueBuilder<SoftKeyboardMode>(
              listenable: controller.softKeyboard,
              builder: (context, mode) {
                _builtMode = mode;
                return TextField(
                  key: _textFieldKey,
                  controller: controller.text,
                  focusNode: controller.focusNode,
                  scrollController: controller.fieldScroll,
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: ComposerMetrics.fieldMaxLines,
                  keyboardType: mode == SoftKeyboardMode.suppressed
                      ? TextInputType.none
                      : TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  onTap: _onTap,
                  cursorColor: composer.cursor,
                  style: TextStyle(
                    color: composer.text,
                    fontSize: fontSize,
                    height: lineHeight,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: strings.messageHint,
                    hintStyle: TextStyle(
                      color: placeholder.fieldHint,
                      fontSize: fontSize,
                      height: lineHeight,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
