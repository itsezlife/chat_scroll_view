import 'package:chat_composer/src/input/soft_keyboard_mode.dart';
import 'package:chat_composer/src/query/composer_input_query.dart';
import 'package:chat_composer/src/query/composer_query_kind.dart';
import 'package:chat_composer/src/query/query_detector.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// The input side of the composer: the entity-aware text, focus, selection,
/// the field's scroll and height, the soft keyboard option, and the input
/// queries at the caret.
///
/// It holds input and nothing else. Whether the composer is replying,
/// editing or restricted, which ids those refer to, and what panel is open
/// belong to the host: the controller has no mode state and imports no panel,
/// inset or presentation type. Neither does it touch the platform text input
/// channel: showing and hiding the keyboard is the field's job, driven by
/// [softKeyboard] and [focusNode].
///
/// The creator disposes. A text controller, focus node or scroll controller
/// passed in is the host's and is left alone by [dispose]; the ones the
/// controller makes for itself are disposed with it.
///
/// Commands are no-ops after [dispose].
final class ComposerController {
  /// Creates a controller.
  ///
  /// [queryKinds] are the kinds registered from the start;
  /// [softKeyboard] is the initial option.
  ComposerController({
    ComposerTextController? text,
    FocusNode? focusNode,
    ScrollController? fieldScroll,
    Iterable<ComposerQueryKind> queryKinds = const [],
    SoftKeyboardMode softKeyboard = SoftKeyboardMode.auto,
  }) : text = text ?? ComposerTextController(),
       focusNode = focusNode ?? FocusNode(debugLabel: 'Composer'),
       fieldScroll = fieldScroll ?? ScrollController(),
       _ownsText = text == null,
       _ownsFocus = focusNode == null,
       _ownsScroll = fieldScroll == null,
       _softKeyboard = ObservableValue(softKeyboard) {
    queryKinds.forEach(registerQueryKind);
    this.text.addListener(_detectQuery);
    _detectQuery();
  }

  /// The entity-aware text of the field.
  final ComposerTextController text;

  /// Focus of the field.
  final FocusNode focusNode;

  /// Scroll of the field's content, for keeping the caret in view.
  final ScrollController fieldScroll;

  final bool _ownsText;
  final bool _ownsFocus;
  final bool _ownsScroll;
  final ObservableValue<SoftKeyboardMode> _softKeyboard;
  final _fieldHeight = ObservableValue<double>(0);
  final _extent = ObservableValue<double>(0);
  final _query = ObservableValue<ComposerInputQuery?>(null);
  final _kinds = <ComposerQueryKind>[];
  Rect? _anchor;
  var _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  // --- Content ---

  /// The text with its entities: what a host stores as a draft, sends, or
  /// compares.
  RichText get richText => text.richText;

  /// The field's selection.
  TextSelection get selection => text.selection;

  /// Moves the selection.
  void select(TextSelection selection) {
    if (_disposed) return;
    text.selection = selection;
  }

  /// Replaces the selection with the plain [value].
  void insertText(String value) {
    if (_disposed) return;
    text.insertText(value);
  }

  /// Replaces the selection with [reference], an atomic inline content
  /// entity over its alternative text.
  void insertContent(InlineContentRef reference) {
    if (_disposed) return;
    text.insertContent(reference);
  }

  /// Deletes the selection, or the unit behind the caret: a whole inline
  /// reference or mention, else one grapheme cluster.
  void backspace() {
    if (_disposed) return;
    text.deleteBackward();
  }

  /// Empties the field and drops every entity.
  void clear() {
    if (_disposed) return;
    text.clear();
  }

  /// Replaces the content with [draft], for a restored draft or a message
  /// loaded for editing.
  void restore(RichText draft, {TextSelection? selection}) {
    if (_disposed) return;
    text.restore(draft, selection: selection);
  }

  // --- Focus ---

  /// Whether the field has focus.
  bool get hasFocus => focusNode.hasFocus;

  /// Asks for focus. Whether the on-screen keyboard shows follows
  /// [softKeyboard].
  void requestFocus() {
    if (_disposed) return;
    focusNode.requestFocus();
  }

  /// Drops focus.
  void unfocus() {
    if (_disposed) return;
    focusNode.unfocus();
  }

  // --- Soft keyboard ---

  /// Whether focusing the field may show the on-screen keyboard.
  ValueObservable<SoftKeyboardMode> get softKeyboard => _softKeyboard;

  /// Sets the soft keyboard option.
  void setSoftKeyboard(SoftKeyboardMode mode) {
    if (_disposed) return;
    _softKeyboard.value = mode;
  }

  // --- Field geometry ---

  /// The height of the field as last reported, zero before the first report.
  /// The host feeds it, with the other extents, to the chat bottom padding.
  ValueObservable<double> get fieldHeight => _fieldHeight;

  /// Reports the laid-out [height] of the field. Called by the field.
  void reportFieldHeight(double height) {
    if (_disposed) return;
    _fieldHeight.value = height;
  }

  /// The height the composer view takes in its parent, as last reported, zero
  /// before the first report: the island with its header, margins and bottom
  /// safe-area pad, without any panel or keyboard.
  ///
  /// It follows the header reveal and the field growth frame by frame, so a
  /// host that feeds it into its chat bottom padding moves with the
  /// animation. The composer imports no inset type; the host adds the
  /// presentation occupancy itself.
  ValueObservable<double> get extent => _extent;

  /// Reports the laid-out [height] of the composer view. Called by the view.
  void reportExtent(double height) {
    if (_disposed) return;
    _extent.value = height;
  }

  /// Scrolls the field to its end once it has laid out. Programmatic edits do
  /// not scroll the caret into view by themselves.
  void scrollFieldToEnd() => _scrollFieldToEnd(0);

  void _scrollFieldToEnd(int frame) {
    if (_disposed) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      if (fieldScroll.hasClients) {
        fieldScroll.jumpTo(fieldScroll.position.maxScrollExtent);
        if (frame < 2) _scrollFieldToEnd(frame + 1);
      } else if (frame < 4) {
        _scrollFieldToEnd(frame + 1);
      }
    });
  }

  // --- Input queries ---

  /// The token at the caret that a registered kind recognises, or null.
  ///
  /// A signal means the token, its kind or its anchor changed.
  ValueObservable<ComposerInputQuery?> get query => _query;

  /// The registered kinds, in registration order.
  List<ComposerQueryKind> get queryKinds => List.unmodifiable(_kinds);

  /// Registers [kind]. When two kinds recognise the same token, the one
  /// registered first wins. Throws an [ArgumentError] when a kind with the
  /// same id is registered.
  void registerQueryKind(ComposerQueryKind kind) {
    if (_kinds.any((existing) => existing.id == kind.id)) {
      throw ArgumentError.value(kind.id, 'kind', 'Already registered.');
    }
    _kinds.add(kind);
    _detectQuery();
  }

  /// Stops watching for the kind with [id]. Unknown ids are ignored.
  void unregisterQueryKind(String id) {
    _kinds.removeWhere((kind) => kind.id == id);
    _detectQuery();
  }

  /// Reports where the caret is drawn, in the field's coordinate space, so
  /// the open query can carry it. Called by the field after layout; ignored
  /// when there is no query.
  void reportCaretAnchor(Rect? anchor) {
    if (_disposed) return;
    final current = _query.value;
    if (current == null) return;
    _anchor = anchor;
    _query.value = current.withAnchor(anchor);
  }

  /// Replaces the token of [query] with [replacement] and puts the caret
  /// after it. Returns whether it did.
  ///
  /// A query that no longer matches the current one (the user kept typing
  /// while the host looked up suggestions) is refused with `false` and
  /// nothing changes. The replacement carries its own entities, such as a
  /// mention or an inline reference, and its own trailing space if wanted.
  bool replaceQuery(ComposerInputQuery query, RichText replacement) {
    if (_disposed) return false;
    final current = _query.value;
    if (current == null || !current.isSameToken(query)) return false;
    text.replaceRange(current.range.start, current.range.end, replacement);
    return true;
  }

  void _detectQuery() {
    if (_disposed) return;
    final selection = text.selection;
    final detected = selection.isValid && selection.isCollapsed
        ? detectQuery(
            _kinds,
            text.text,
            selection.baseOffset,
            text.richText.entities,
          )
        : null;
    if (detected == null) {
      _anchor = null;
      _query.value = null;
      return;
    }
    _query.value = detected.withAnchor(_anchor);
  }

  // --- Lifecycle ---

  /// Stops listening and disposes what this controller created. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    text.removeListener(_detectQuery);
    _softKeyboard.dispose();
    _fieldHeight.dispose();
    _extent.dispose();
    _query.dispose();
    if (_ownsText) text.dispose();
    if (_ownsFocus) focusNode.dispose();
    if (_ownsScroll) fieldScroll.dispose();
  }
}
