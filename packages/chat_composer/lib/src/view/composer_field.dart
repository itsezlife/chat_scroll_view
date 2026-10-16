import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/input/soft_keyboard_mode.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chat_composer/src/view/listen_value_builder.dart';
import 'package:chat_composer/src/view/slot_boxes.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
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
/// on-screen keyboard down. That is the whole mechanism; no platform channel
/// is used, and the hand-off with a panel is the host's presentation's job.
///
/// Needs a Material ancestor and Material localisations, which the text
/// selection menu draws with.
class ComposerField extends StatefulWidget {
  /// A field for [controller].
  const ComposerField({
    required this.controller,
    required this.enabled,
    this.onTap,
    super.key,
  });

  /// The input state.
  final ComposerController controller;

  /// Whether the field takes input.
  final bool enabled;

  /// Called when the field is tapped, also while it already has focus. A host
  /// uses it to leave a panel for the keyboard.
  final VoidCallback? onTap;

  @override
  State<ComposerField> createState() => _ComposerFieldState();
}

class _ComposerFieldState extends State<ComposerField> {
  final _textFieldKey = GlobalKey();
  var _anchorScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.text.addListener(_scheduleAnchor);
  }

  @override
  void didUpdateWidget(ComposerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.text.removeListener(_scheduleAnchor);
      widget.controller.text.addListener(_scheduleAnchor);
    }
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_scheduleAnchor);
    super.dispose();
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
            builder: (context, mode) => TextField(
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
              onTap: widget.onTap,
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
            ),
          ),
        ),
      ),
    );
  }
}
