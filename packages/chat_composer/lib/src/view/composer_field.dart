import 'dart:async';
import 'dart:math' as math;

import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/input/soft_keyboard_mode.dart';
import 'package:chat_composer/src/shortcuts/composer_intents.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chat_composer/src/view/list_gutter_painter.dart';
import 'package:chat_composer/src/view/listen_value_builder.dart';
import 'package:chat_composer/src/view/slot_boxes.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart' show PastedMedia;
import 'package:flutter/foundation.dart'
    show clampDouble, defaultTargetPlatform;
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
/// **Media.** When the controller has an `onPastedMedia` host, an image a
/// keyboard inserts goes there (`ContentInsertionConfiguration`), as a pasted
/// image does.
///
/// **Clipboard.** When the controller has a `clipboard`, copy, cut and paste
/// go through it, from key shortcuts (and the macOS menu) and from the
/// selection menu, which also offers pasting as plain text; the text keeps its
/// entities across the clipboard. Without one the field keeps the platform's
/// plain-text clipboard and the stock menu.
///
/// Needs a Material ancestor and Material localisations, which the text
/// selection menu draws with.
class ComposerField extends StatefulWidget {
  /// A field for [controller].
  const ComposerField({
    required this.controller,
    required this.enabled,
    this.autofocus = false,
    this.onTap,
    this.onPointerDown,
    this.onPointerEnd,
    super.key,
  });

  /// The input state.
  final ComposerController controller;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes focus when it is first built.
  ///
  /// On a touch platform that focus brings no soft keyboard: the field
  /// attaches without a keyboard type, and the first tap on it or
  /// `requestKeyboard` re-attaches it with one (see "Soft keyboard" above).
  final bool autofocus;

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

  // The focus autofocus gives on a touch platform attaches as if suppressed,
  // so the caret shows and the keyboard stays down until it is asked for.
  late var _quietFocus =
      widget.autofocus &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia => true,
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => false,
      };
  var _revealScheduled = false;

  // The markers of a list, painted beside the text; null for a text that does
  // not edit lists. The room it takes follows the markers the text holds.
  ComposerListGutterPainter? _gutter;
  var _gutterExtent = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.text.addListener(_scheduleAnchor);
    widget.controller.text.addListener(_onGutterText);
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
      oldWidget.controller.text.removeListener(_onGutterText);
      _gutter?.dispose();
      _gutter = null;
      oldWidget.controller.keyboardRequests.removeListener(_onKeyboardRequest);
      oldWidget.controller.caretReveals.removeListener(_onCaretReveal);
      oldWidget.controller.focusNode.removeListener(_onFocus);
      widget.controller.text.addListener(_scheduleAnchor);
      widget.controller.text.addListener(_onGutterText);
      widget.controller.keyboardRequests.addListener(_onKeyboardRequest);
      widget.controller.caretReveals.addListener(_onCaretReveal);
      widget.controller.focusNode.addListener(_onFocus);
      _onFocus();
    }
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_scheduleAnchor);
    widget.controller.text.removeListener(_onGutterText);
    widget.controller.keyboardRequests.removeListener(_onKeyboardRequest);
    widget.controller.caretReveals.removeListener(_onCaretReveal);
    widget.controller.focusNode.removeListener(_onFocus);
    _gutter?.dispose();
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
    final focused = widget.controller.focusNode.hasFocus;
    _attachedMode = focused ? _builtMode : null;
    // Attached quietly: from now on the field is built with the mode the
    // controller says, and a tap or a request re-attaches it with a keyboard.
    if (focused && _quietFocus) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _quietFocus = false);
      });
    }
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

  // The text gained or lost its first or widest marker: the field makes room.
  void _onGutterText() {
    final gutter = _gutter;
    if (gutter == null || gutter.extent == _gutterExtent) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  // The gutter painter in the field's text style, made on the first build of a
  // text that edits lists.
  ComposerListGutterPainter? _gutterFor(TextStyle style, TextScaler scaler) {
    if (!widget.controller.text.lists) return null;
    final gutter = _gutter ??= ComposerListGutterPainter(
      text: widget.controller.text,
      style: style,
      textScaler: scaler,
    );
    gutter
      ..style = style
      ..textScaler = scaler;
    return gutter;
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

  void _onContentInserted(KeyboardInsertedContent content) {
    final data = content.data;
    if (data == null || data.isEmpty) return;
    widget.controller.receiveMedia([
      PastedMedia.bytes(data, mimeType: content.mimeType),
    ]);
  }

  // --- Selection menu ---

  // `AdaptiveTextSelectionToolbar.editableText` takes Flutter's own editable
  // state, which the leaf editable's state is not: the menu is built from the
  // state's anchors and button items instead.
  static Widget _stockMenu(
    BuildContext context,
    ExtendedEditableTextState editable,
  ) => AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editable.contextMenuAnchors,
    buttonItems: editable.contextMenuButtonItems,
  );

  // The stock menu, its Copy, Cut and Paste routed through the clipboard,
  // and Paste as plain text after Paste.
  Widget _clipboardMenu(
    ExtendedEditableTextState editable,
    String pastePlainLabel,
  ) {
    final controller = widget.controller;
    final items = <ContextMenuButtonItem>[];
    for (final item in editable.contextMenuButtonItems) {
      switch (item.type) {
        case ContextMenuButtonType.copy:
          items.add(item.copyWith(onPressed: () => _menuCopy(editable)));
        case ContextMenuButtonType.cut:
          items.add(
            item.copyWith(
              onPressed: () => _menuDone(editable, controller.cutSelection()),
            ),
          );
        case ContextMenuButtonType.paste:
          items
            ..add(
              item.copyWith(
                onPressed: () => _menuDone(editable, controller.paste()),
              ),
            )
            ..add(
              ContextMenuButtonItem(
                label: pastePlainLabel,
                onPressed: () =>
                    _menuDone(editable, controller.paste(plain: true)),
              ),
            );
        case _:
          items.add(item);
      }
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: items,
    );
  }

  // As the field's own Copy: the menu closes, and on Android the selection
  // collapses to its end.
  Future<void> _menuCopy(ExtendedEditableTextState editable) async {
    final controller = widget.controller;
    final end = controller.selection.end;
    editable.hideToolbar(false);
    await controller.copySelection();
    if (!mounted || controller.isDisposed) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      controller.select(TextSelection.collapsed(offset: end));
    }
  }

  static void _menuDone(ExtendedEditableTextState editable, Future<bool> done) {
    editable.hideToolbar();
    unawaited(done);
  }

  // The field does not expose its editable; the caret rectangle is only
  // available from the render object the text lays out in.
  ExtendedEditableTextState? _editableTextState() {
    ExtendedEditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element case StatefulElement(
        state: final ExtendedEditableTextState state,
      )) {
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
    final fieldStyle = TextStyle(
      color: composer.text,
      fontSize: fontSize,
      height: lineHeight,
    );
    final gutter = _gutterFor(fieldStyle, MediaQuery.textScalerOf(context));
    _gutterExtent = gutter?.extent ?? 0;

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
              builder: (context, controllerMode) {
                final mode = _quietFocus
                    ? SoftKeyboardMode.suppressed
                    : controllerMode;
                _builtMode = mode;
                final field = ExtendedTextField(
                  key: _textFieldKey,
                  controller: controller.text,
                  focusNode: controller.focusNode,
                  scrollController: controller.fieldScroll,
                  // The tap region the stock field and every host widget that
                  // stays "inside" it (a button, a popup) join by default.
                  // The leaf editable's own default group is its own type,
                  // which those widgets would not find.
                  groupId: EditableText,
                  // Telegram's handles are drawn by the composer, not the
                  // platform's: Material on every platform.
                  selectionControls:
                      extendedMaterialTextSelectionHandleControls,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  minLines: 1,
                  maxLines: ComposerMetrics.fieldMaxLines,
                  keyboardType: mode == SoftKeyboardMode.suppressed
                      ? TextInputType.none
                      : TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  onTap: _onTap,
                  cursorColor: composer.cursor,
                  style: fieldStyle,
                  // The markers of list items sit beside the text, in room
                  // the field makes only while there is a marker.
                  gutterPainter: gutter,
                  gutterExtent: _gutterExtent,
                  gutterInset: _gutterExtent,
                  decoration: InputDecoration.collapsed(
                    hintText: strings.messageHint,
                    hintStyle: TextStyle(
                      color: placeholder.fieldHint,
                      fontSize: fontSize,
                      height: lineHeight,
                    ),
                  ),
                  // An image a keyboard inserts (Android) is media the host
                  // sends, as a pasted image is.
                  contentInsertionConfiguration:
                      controller.onPastedMedia == null
                      ? null
                      : ContentInsertionConfiguration(
                          onContentInserted: _onContentInserted,
                        ),
                  contextMenuBuilder: controller.clipboard == null
                      ? _stockMenu
                      : (context, editable) =>
                            _clipboardMenu(editable, strings.pastePlainAction),
                );
                if (controller.clipboard == null) return field;
                // Above the field's own: an overridable action finds these
                // first, so shortcuts and the macOS menu selectors land here.
                return Actions(
                  actions: {
                    CopySelectionTextIntent: _CopyAction(controller),
                    PasteTextIntent: _PasteAction(controller),
                    PastePlainTextIntent: _PastePlainAction(controller),
                  },
                  child: field,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// --- Clipboard actions ---

class _CopyAction extends Action<CopySelectionTextIntent> {
  _CopyAction(this._controller);

  final ComposerController _controller;

  @override
  bool isEnabled(CopySelectionTextIntent intent) {
    final selection = _controller.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    // Cut is the copy intent that collapses the selection.
    unawaited(
      intent.collapseSelection
          ? _controller.cutSelection()
          : _controller.copySelection(),
    );
    return null;
  }
}

class _PasteAction extends Action<PasteTextIntent> {
  _PasteAction(this._controller);

  final ComposerController _controller;

  @override
  Object? invoke(PasteTextIntent intent) {
    unawaited(_controller.paste());
    return null;
  }
}

class _PastePlainAction extends Action<PastePlainTextIntent> {
  _PastePlainAction(this._controller);

  final ComposerController _controller;

  @override
  Object? invoke(PastePlainTextIntent intent) {
    unawaited(_controller.paste(plain: true));
    return null;
  }
}
