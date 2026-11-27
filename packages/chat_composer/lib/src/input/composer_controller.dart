import 'dart:async';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/src/capabilities/composer_capability_state.dart';
import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/capabilities/composer_denied_forms.dart';
import 'package:chat_composer/src/capabilities/composer_op.dart';
import 'package:chat_composer/src/capabilities/composer_slow_mode_forms.dart';
import 'package:chat_composer/src/capabilities/composer_slow_mode_state.dart';
import 'package:chat_composer/src/capabilities/slow_mode_countdown.dart';
import 'package:chat_composer/src/input/composer_paste.dart';
import 'package:chat_composer/src/input/soft_keyboard_mode.dart';
import 'package:chat_composer/src/query/composer_input_query.dart';
import 'package:chat_composer/src/query/composer_query_kind.dart';
import 'package:chat_composer/src/query/query_detector.dart';
import 'package:chat_composer/src/spec/action_descriptor.dart';
import 'package:chat_composer/src/spec/composer_panel.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:chat_composer/src/text/mention_downgrade.dart';
import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromeHintTiming, PointerMenuTiming;
import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter/widgets.dart' hide RichText;
import 'package:listen/listen.dart' as listen;

/// The input side of the composer: the entity-aware text, focus, selection,
/// the field's scroll and height, the soft keyboard option, and the input
/// queries at the caret.
///
/// It holds input and nothing else. Whether the composer is replying,
/// editing or restricted, which ids those refer to, and what panel is open
/// belong to the host: the controller has no mode state and imports no panel,
/// inset or presentation type. Neither does it touch the platform text input
/// channel: showing and hiding the keyboard is the field's job, driven by
/// [softKeyboard], [focusNode] and [requestKeyboard].
///
/// ## Clipboard
///
/// Given a [clipboard], [copySelection], [cutSelection] and [paste] keep the
/// text's entities across the system clipboard (ADR 032), and the field routes
/// its copy, cut and paste there. Where the platform performs those commands
/// itself (a browser's keys and menu), the controller takes them over through
/// [RichClipboard.attach] while its field has focus. Without a clipboard the
/// field keeps the platform's plain-text clipboard.
///
/// The creator disposes. A text controller, focus node or scroll controller
/// passed in is the host's and is left alone by [dispose]; the ones the
/// controller makes for itself are disposed with it.
///
/// ## Capabilities
///
/// What the chat's capabilities decide is the controller's, so a host that
/// draws its own row keeps the rules: the view binds the chat's
/// capabilities ([bindCapabilities]) while it is mounted, and
/// [capabilities] says which panel replaces the row, whether the field is
/// locked, which actions are denied ([actionDenial]) and the chat's
/// message budget, with the host's texts already asked from
/// [capabilityFeedback]. [reportDenied] reports an attempt, the host
/// hearing of it once per [deniedRepeatWindow] per action. Without
/// feedback texts are null and attempts go unreported, as before.
///
/// Slow mode's countdown is the controller's too: [slowMode] is the
/// countdown, read at [clock], [slowModeEdges] its starts and ends, and
/// [refuseEarlySend] holds a send during the wait.
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
    this.clipboard,
    this.onPastedMedia,
    this.onPaste,
    this.confirmMention,
    this.capabilityFeedback = CapabilityFeedback.none,
    this.chatId,
    this.deniedRepeatWindow = defaultDeniedRepeatWindow,
    this.clock = ComposerClock.system,
  }) : text = text ?? ComposerTextController(),
       focusNode = focusNode ?? FocusNode(debugLabel: 'Composer'),
       fieldScroll = fieldScroll ?? ScrollController(),
       _ownsText = text == null,
       _ownsFocus = focusNode == null,
       _ownsScroll = fieldScroll == null,
       _softKeyboard = listen.ValueNotifier(softKeyboard) {
    queryKinds.forEach(registerQueryKind);
    this.text.addListener(_detectQuery);
    _detectQuery();
    _detachClipboard = clipboard?.attach(_ClipboardField(this));
    _slowMode = SlowModeCountdown(clock: clock, correlation: () => correlation);
  }

  /// The entity-aware text of the field.
  final ComposerTextController text;

  /// Focus of the field.
  final FocusNode focusNode;

  /// Scroll of the field's content, for keeping the caret in view.
  final ScrollController fieldScroll;

  /// The clipboard copy, cut and paste go through; null leaves the field on
  /// the platform's plain-text clipboard.
  final RichClipboard? clipboard;

  /// Takes the images and files the user puts into the field: a paste while
  /// the [clipboard] holds media, and an image a keyboard inserts. The host
  /// sends them and completes with whether it did: a paste whose media the
  /// host did not send (the user cancelled) pastes the text that came with it.
  /// Null leaves pastes text only and keyboards without image
  /// insertion.
  final Future<bool> Function(List<PastedMedia> media)? onPastedMedia;

  /// Told of each paste that put text into the field, after it did: its range,
  /// its plain text and whether it was rich. Paste itself is unchanged by it
  /// (plain stays plain, rich is the clipboard's payload; nothing parses
  /// markdown), so the host that offers to apply formatting does so from here.
  ///
  /// Only pastes through the [clipboard] are reported. Without one the field
  /// keeps the platform's paste, which reaches the controller as an edit and
  /// is not told apart from typing. A host that throws is reported to
  /// [FlutterError.reportError] and the paste stands.
  final void Function(ComposerPaste paste)? onPaste;

  /// Whether the host knows the party with this mention id, asked at send time
  /// ([sendableText]) for a mention the draft did not resolve itself: one
  /// that came in with a paste. The host answers from its own users (the chat's
  /// members, say), never from the clipboard's claim (ADR 032). Null confirms
  /// none, so every pasted mention is sent as its `@name`.
  final bool Function(String id)? confirmMention;

  /// The host's denial texts and the report of attempts.
  final CapabilityFeedback capabilityFeedback;

  /// The chat the composer writes in, correlating the composer's
  /// diagnostics events; null correlates none.
  final String? chatId;

  /// How long after an attempt the host heard of [reportDenied] keeps the
  /// next one of the same action from the host, so a burst of taps on a
  /// dimmed control shows one hint: the host's tooltip for the first is
  /// still showing.
  final Duration deniedRepeatWindow;

  /// The stock [deniedRepeatWindow]: how long the host's hint at the
  /// control stays up.
  static const defaultDeniedRepeatWindow = ChromeHintTiming.controlHint;

  /// The time slow mode's countdown is read at and redrawn by.
  final ComposerClock clock;

  final bool _ownsText;
  final bool _ownsFocus;
  final bool _ownsScroll;
  final listen.ValueNotifier<SoftKeyboardMode> _softKeyboard;
  final _fieldHeight = listen.ValueNotifier<double>(0);
  final _extent = listen.ValueNotifier<double>(0);
  final _query = listen.ValueNotifier<ComposerInputQuery?>(null);
  final _keyboardRequests = _Signal();
  final _caretReveals = _Signal();
  final _selectionUiHides = _Signal();
  final _kinds = <ComposerQueryKind>[];
  final _resolvedMentions = <String>{};
  Rect? _anchor;
  void Function()? _detachClipboard;
  final _deniedGuards = <CapabilityAction, Timer>{};
  late final SlowModeCountdown _slowMode;
  final _capabilities = listen.ValueNotifier<ComposerCapabilityState>(
    ComposerCapabilityState.unbound,
  );
  listen.ValueListenable<ChatCapabilities>? _source;
  listen.ValueListenable<_RowGroup>? _rowGroup;
  listen.ValueListenable<SlowMode>? _slowModeGroup;
  final _actionDenials = <CapabilityAction, ComposerDenial>{};
  Map<String, Object>? _reportedPanel;
  ComposerDeniedForms _forms = ComposerDeniedForms.android;
  bool Function(ComposerPanelId panel) _hostBuilds = _noHostPanels;

  static bool _noHostPanels(ComposerPanelId panel) => false;
  var _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  // --- Content ---

  /// The text with its entities: what a host stores as a draft, sends, or
  /// compares.
  RichText get richText => text.richText;

  /// [richText] as it may be sent: every mention the host did not resolve in
  /// this draft is rewritten to the `@name` it displays
  /// ([downgradeUnresolvedMentions]), so the host encodes this, not
  /// [richText], with `RichTextMarkdown.encode`. ADR 034.
  ///
  /// A mention is resolved here when the host picked it ([replaceQuery]),
  /// loaded it ([restore]), marked it ([trustMention]) or [confirmMention]
  /// accepts it. A mention a paste brought in is none of those until the
  /// host confirms it. Nothing is trimmed or otherwise changed: skipping the
  /// trim of an emoji-only message stays the host's.
  RichText get sendableText => downgradeUnresolvedMentions(
    richText,
    (id) =>
        _resolvedMentions.contains(id) || (confirmMention?.call(id) ?? false),
  );

  /// Marks the mention [id] as resolved in this draft, for a host that puts a
  /// mention in through `text.insert` rather than [replaceQuery]. Forgotten
  /// by [clear] and [restore], with the rest of the draft.
  void trustMention(String id) {
    if (_disposed) return;
    _resolvedMentions.add(id);
  }

  /// The length of the text in code points, the unit of
  /// `ComposerSpec.messageLengthLimit`.
  ///
  /// Not UTF-16 units (a surrogate pair is one) and not the length of any
  /// markdown the host will encode. Current also while the input method
  /// composes.
  int get length => text.text.runes.length;

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
    _caretReveals.signal();
  }

  /// Replaces the selection with [reference], an atomic inline content
  /// entity over its alternative text.
  void insertContent(InlineContentRef reference) {
    if (_disposed) return;
    text.insertContent(reference);
    _caretReveals.signal();
  }

  /// Deletes the selection, or the unit behind the caret: a whole inline
  /// reference or mention, else one grapheme cluster.
  void backspace() {
    if (_disposed) return;
    text.deleteBackward();
    _caretReveals.signal();
  }

  /// Empties the field and drops every entity.
  void clear() {
    if (_disposed) return;
    _resolvedMentions.clear();
    text.clear();
  }

  /// Replaces the content with [draft], for a restored draft or a message
  /// loaded for editing.
  void restore(RichText draft, {TextSelection? selection}) {
    if (_disposed) return;
    _resolvedMentions
      ..clear()
      ..addAll(_mentionIds(draft));
    text.restore(draft, selection: selection);
  }

  static Iterable<String> _mentionIds(RichText value) => [
    for (final entity in value.entities)
      if (entity.kind case EntityKind$Mention(:final id)) id,
  ];

  // --- Edit menu state ---

  /// The field's undo history, which `ComposerField` hands to its editable.
  ///
  /// Owned here so the edit menu can ask whether there is anything to undo
  /// or redo, and do it, without reaching into the editable (whose own history
  /// is internal). The history records the text value, which is what the
  /// undo and redo keys step through too, so the menu and the keys agree.
  final UndoHistoryController undoHistory = UndoHistoryController();

  /// Whether [undo] would change anything now.
  bool get canUndo => !_disposed && undoHistory.value.canUndo;

  /// Whether [redo] would change anything now.
  bool get canRedo => !_disposed && undoHistory.value.canRedo;

  /// Steps the field's history back, as the undo key does.
  void undo() {
    if (_disposed) return;
    undoHistory.undo();
  }

  /// Steps the field's history forward, as the redo key does.
  void redo() {
    if (_disposed) return;
    undoHistory.redo();
  }

  /// Removes the selected text, leaving a caret where it was, without touching
  /// the clipboard. Does nothing at a caret.
  void deleteSelection() {
    final selection = text.selection;
    if (_disposed || !selection.isValid || selection.isCollapsed) return;
    text.replaceRange(selection.start, selection.end, RichText.empty);
    _caretReveals.signal();
  }

  /// Selects the whole text.
  void selectAll() {
    if (_disposed) return;
    text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.text.length,
    );
  }

  /// Whether a paste would put anything in: the [clipboard] holds text, or
  /// media an [onPastedMedia] host takes; without a [clipboard], whether the
  /// platform's holds text.
  ///
  /// Reads the clipboard, so it is asked once when a menu opens, not on every
  /// frame. A clipboard that cannot be read is reported to
  /// [FlutterError.reportError] and counts as empty; one that does not answer
  /// within `PointerMenuTiming.clipboardProbe` counts as holding something.
  Future<bool> canPaste() async {
    if (_disposed) return false;
    final source = clipboard;
    try {
      return await _holdsPastable(
        source,
      ).timeout(PointerMenuTiming.clipboardProbe, onTimeout: () => true);
    } on Object catch (error, stack) {
      _report(error, stack, 'while reading the clipboard to enable Paste');
      return false;
    }
  }

  Future<bool> _holdsPastable(RichClipboard? source) async {
    if (source == null) return Clipboard.hasStrings();
    final contents = await source.readWithMedia();
    final held = contents.text;
    if (held != null && held.plain.isNotEmpty) return true;
    return onPastedMedia != null && contents.media.isNotEmpty;
  }

  // --- Clipboard ---

  /// Puts the selection on the [clipboard] with its entities. False when there
  /// is no clipboard, the selection is collapsed, or the clipboard failed
  /// (reported to [FlutterError.reportError]).
  Future<bool> copySelection() async {
    final selection = text.selection;
    if (_disposed || !selection.isValid || selection.isCollapsed) return false;
    return _write(richText.slice(selection.start, selection.end));
  }

  /// Puts the selection on the [clipboard] and removes it from the text; see
  /// [copySelection]. The text is left as it was when the copy fails.
  Future<bool> cutSelection() async {
    final selection = text.selection;
    if (_disposed || !selection.isValid || selection.isCollapsed) return false;
    final cut = richText.slice(selection.start, selection.end);
    if (!await _write(cut) || _disposed) return false;
    // Cut what was copied: the text may have moved on while the clipboard
    // wrote.
    if (text.richText.slice(selection.start, selection.end) == cut) {
      text.replaceRange(selection.start, selection.end, RichText.empty);
      _caretReveals.signal();
    }
    return true;
  }

  /// Replaces the selection with what the [clipboard] holds: its rich text
  /// when it has one, its plain text otherwise or when [plain] is true.
  ///
  /// When the clipboard holds images or files and there is an
  /// [onPastedMedia] host, a paste (not one as [plain] text) hands them to it
  /// and inserts no text: what was copied was the media. When the host does
  /// not send them, the text that came with them goes in (an office app's
  /// copied range comes with a picture of it).
  ///
  /// Plain text with two or more marker lines (`- a`, `1. b`) becomes list
  /// items when the text controller edits lists (see
  /// `ComposerTextController.withPastedLists`); a paste as [plain] text does
  /// not.
  ///
  /// Pasted into a quote, the text's own quotes are unwrapped, so quotes never
  /// nest; entities that cannot sit where the text lands are dropped and the
  /// text still goes in (see [ComposerTextController.replaceRange]). A paste
  /// whose text changed while the clipboard was read (a platform that asks
  /// the user first) or the host looked at the media lands nowhere; one whose
  /// selection was lost meanwhile lands where the selection was.
  ///
  /// True when media went to the host or text went in; false when there is
  /// no clipboard, it holds nothing to paste, the text moved on, or the
  /// clipboard failed (reported to [FlutterError.reportError]).
  Future<bool> paste({bool plain = false}) async {
    final source = clipboard;
    if (_disposed || source == null) return false;
    final before = (rich: richText, selection: text.selection);
    final withMedia = !plain && onPastedMedia != null;
    final ClipboardContents contents;
    try {
      // One read for text and media: one paste prompt where the platform
      // asks.
      contents = withMedia
          ? await source.readWithMedia()
          : ClipboardContents(text: await source.read());
    } on Object catch (error, stack) {
      _report(error, stack, 'while reading the clipboard to paste');
      return false;
    }
    return _insertPasted(contents, before: before, plain: plain);
  }

  // What [paste] does once it has the clipboard's [contents], the platform's
  // own paste too; [before] is the text and selection the paste began on.
  Future<bool> _insertPasted(
    ClipboardContents contents, {
    required ({RichText rich, TextSelection selection}) before,
    required bool plain,
  }) async {
    if (_disposed) return false;
    final withMedia = !plain && onPastedMedia != null;
    if (withMedia && contents.media.isNotEmpty) {
      if (await _handOver(contents.media) || _disposed) return true;
    }
    final held = contents.text;
    if (held == null) return false;
    if (richText != before.rich) return false;
    if (!text.selection.isValid) text.selection = before.selection;
    var pasted = plain ? RichText.plain(held.plain) : held.richOrPlain;
    if (pasted.isEmpty) return false;
    // Plain text with marker lines is a list pasted, for a field that edits
    // lists; "as plain text" asks for the text as it is.
    if (!plain) pasted = text.withPastedLists(pasted);
    if (_insideQuote(text.selection)) {
      pasted = RichText(pasted.plain, [
        for (final entity in pasted.entities)
          if (entity.kind != EntityKind.quote) entity,
      ]);
    }
    text.insert(pasted);
    _caretReveals.signal();
    _reportPaste(pasted.plain, wasRich: !plain && held.rich != null);
    return true;
  }

  // The insert leaves the caret after the text, wherever the selection
  // widened to, so the landed range ends there.
  void _reportPaste(String pasted, {required bool wasRich}) {
    final host = onPaste;
    if (host == null) return;
    final end = text.selection.end;
    try {
      host(
        ComposerPaste(
          range: TextRange(start: end - pasted.length, end: end),
          text: pasted,
          wasRich: wasRich,
        ),
      );
    } on Object catch (error, stack) {
      _report(error, stack, 'while telling the host of a paste');
    }
  }

  /// Hands [media] the user put into the field (a keyboard's inserted image,
  /// a paste) to [onPastedMedia]. Does nothing without one, after [dispose]
  /// or for no media.
  void receiveMedia(List<PastedMedia> media) {
    if (_disposed || media.isEmpty) return;
    unawaited(_handOver(media));
  }

  // Whether the host sent [media]; a host that fails did not (reported).
  Future<bool> _handOver(List<PastedMedia> media) async {
    final host = onPastedMedia;
    if (host == null) return false;
    try {
      return await host(List.unmodifiable(media));
    } on Object catch (error, stack) {
      _report(error, stack, 'while handing pasted media to the host');
      return false;
    }
  }

  Future<bool> _write(RichText copied) async {
    final target = clipboard;
    if (target == null) return false;
    try {
      await target.write(copied);
      return true;
    } on Object catch (error, stack) {
      _report(error, stack, 'while writing the clipboard');
      return false;
    }
  }

  bool _insideQuote(TextSelection selection) {
    final at = selection.isValid ? selection.start : text.text.length;
    return richText.entities.any(
      (entity) =>
          entity.kind == EntityKind.quote &&
          entity.offset <= at &&
          at <= entity.end,
    );
  }

  static void _report(Object error, StackTrace stack, String doing) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'chat_composer',
        context: ErrorDescription(doing),
      ),
    );
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
  listen.ValueListenable<SoftKeyboardMode> get softKeyboard => _softKeyboard;

  /// Sets the soft keyboard option.
  ///
  /// The option alone shows nothing: a field that has focus keeps the input
  /// connection it has, so lifting the suppression (a panel closing) leaves the
  /// keyboard down until the user taps the field or the host calls
  /// [requestKeyboard].
  void setSoftKeyboard(SoftKeyboardMode mode) {
    if (_disposed) return;
    _softKeyboard.value = mode;
  }

  /// Asks the field to raise the on-screen keyboard, after the frame that
  /// applies the current [softKeyboard] option.
  ///
  /// The field takes focus if it has none. A field that took focus while the
  /// keyboard was suppressed attached to the platform with no keyboard type,
  /// which the platform keeps; it attaches again, with the current option, and
  /// that raises the keyboard. Nothing shows while [softKeyboard] is
  /// suppressed.
  void requestKeyboard() {
    if (_disposed) return;
    _keyboardRequests.signal();
  }

  /// Signals each [requestKeyboard]; the field answers it. For the view.
  listen.Listenable get keyboardRequests => _keyboardRequests;

  /// Signals each edit made through this controller ([insertText],
  /// [insertContent], [backspace]); the field answers by scrolling its caret
  /// into view. For the view.
  ///
  /// A field reveals its caret after the edits typed into it, but not after
  /// the ones its controller makes: without this, a field past its maximum
  /// lines would leave the line an inserted emoji lands on out of sight.
  listen.Listenable get caretReveals => _caretReveals;

  /// Takes down the field's selection handles and toolbar (a host whose
  /// panel stands in for the keyboard, or that types into the field from
  /// outside it: the handle a tap left must not stay up).
  void hideSelectionUi() {
    if (_disposed) return;
    _selectionUiHides.signal();
  }

  /// Signals each [hideSelectionUi]; the field answers it. For the view.
  listen.Listenable get selectionUiHides => _selectionUiHides;

  // --- Field geometry ---

  /// The height of the field as last reported, zero before the first report.
  /// The host feeds it, with the other extents, to the chat bottom padding.
  listen.ValueListenable<double> get fieldHeight => _fieldHeight;

  /// Reports the laid-out [height] of the field. Called by the field.
  void reportFieldHeight(double height) {
    if (_disposed) return;
    _fieldHeight.value = height;
  }

  /// The height the composer view takes in its parent, as last reported, zero
  /// before the first report: the island with its header and margins, without
  /// the bottom safe-area pad and without any panel or keyboard.
  ///
  /// It follows the header reveal and the field growth frame by frame, so a
  /// host that feeds it into its chat bottom padding moves with the
  /// animation. The composer imports no inset type; the host adds the bottom
  /// band itself (the larger of the safe area and the presentation's
  /// occupancy), which it knows without waiting for a layout.
  listen.ValueListenable<double> get extent => _extent;

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
  listen.ValueListenable<ComposerInputQuery?> get query => _query;

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
  /// mention or an inline reference, and its own trailing space if wanted. A
  /// mention in it is one the host resolved (it picked it), and [sendableText]
  /// keeps it.
  bool replaceQuery(ComposerInputQuery query, RichText replacement) {
    if (_disposed) return false;
    final current = _query.value;
    if (current == null || !current.isSameToken(query)) return false;
    _resolvedMentions.addAll(_mentionIds(replacement));
    text.replaceRange(current.range.start, current.range.end, replacement);
    return true;
  }

  void _detectQuery() {
    if (_disposed) return;
    final selection = text.selection;
    final detected = selection.isValid && selection.isCollapsed
        ? QueryDetector.detect(
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

  // --- Capabilities ---

  /// The diagnostics correlation of this composer's chat.
  ChatCorrelation get correlation => switch (chatId) {
    final chatId? => ChatCorrelation(chatId: chatId),
    null => ChatCorrelation.none,
  };

  /// The host's text for [action] denied for [reason], drawn in place as
  /// [form], or null for the silent form; a null text is reported as
  /// `denialTextMissing`.
  String? denialText(
    CapabilityAction action,
    DenialReason reason, {
    required ComposerDenialForm form,
  }) => capabilityFeedback.denialText(
    action,
    reason,
    correlation: correlation,
    form: form,
  );

  /// Reports that the user attempted [action], denied for [reason] (a tap
  /// on the locked field or a dimmed action), and returns whether the host
  /// heard of it.
  ///
  /// The window is per action: an attempt of the same action within
  /// [deniedRepeatWindow] of the last one the host heard of reports
  /// `denied` as `repeated` and skips the host's `onDenied`, whose feedback
  /// for the first is still up; an attempt of another action (a send in
  /// slow mode after a tap on a dimmed action) is its own. After [dispose]
  /// nothing is reported.
  ///
  /// [remaining] is slow mode's wait, for a `sendNow`.
  bool reportDenied(
    CapabilityAction action,
    DenialReason reason, {
    Duration? remaining,
  }) {
    if (_disposed) return false;
    final repeated = _deniedGuards.containsKey(action);
    if (!repeated) {
      _deniedGuards[action] = Timer(
        deniedRepeatWindow,
        () => _deniedGuards.remove(action),
      );
    }
    capabilityFeedback.onDenied(
      action,
      reason,
      consumer: CapabilityConsumer.composer,
      remaining: remaining,
      repeated: repeated,
      correlation: correlation,
    );
    return !repeated;
  }

  /// The chat's capabilities as the row draws them: the replacing panel,
  /// the locked field, the denied actions and the message budget, with the
  /// host's texts already asked.
  ///
  /// [ComposerCapabilityState.unbound] until a view binds capabilities
  /// ([bindCapabilities]); it changes on each new value of the groups it
  /// reads (a slow mode tick is not one).
  listen.ValueListenable<ComposerCapabilityState> get capabilities =>
      _capabilities;

  /// Follows [source], the chat's capabilities, drawn in [forms]: called by
  /// the view while it is mounted, with each new source or forms.
  ///
  /// From then on the controller owns what the capabilities decide: the
  /// panel that replaces the row (reported as `panelChosen` once per
  /// change of the choice, with [hostBuilds] telling whether the host's
  /// resolver builds that panel), the locked field and its text, the denied
  /// actions, the chat's message budget and slow mode's countdown,
  /// redrawn at the forms' refresh. Null unbinds.
  void bindCapabilities(
    listen.ValueListenable<ChatCapabilities>? source, {
    required ComposerDeniedForms forms,
    required bool Function(ComposerPanelId panel) hostBuilds,
  }) {
    if (_disposed) return;
    _hostBuilds = hostBuilds;
    final rebind = !identical(source, _source);
    _forms = forms;
    if (!rebind) {
      if (_slowModeGroup case final group?) _trackSlowMode(group.value);
      return;
    }
    _unsubscribe();
    _source = source;
    if (source == null) {
      _slowMode.untrack();
      _reportedPanel = null;
      _capabilities.value = ComposerCapabilityState.unbound;
      return;
    }
    _rowGroup = source.select(
      (c) => (
        writeAccess: c.writeAccess,
        sending: c.sending,
        messageLength: c.limits.messageLength,
        slowModeActive: c.slowMode.isActive,
      ),
    )..addListener(_onRowGroup);
    final slowMode = _slowModeGroup = source.select((c) => c.slowMode)
      ..addListener(_onSlowModeGroup);
    _trackSlowMode(slowMode.value);
    _onRowGroup();
  }

  /// Stops following the capabilities (the view went away): the countdown
  /// stops redrawing and [capabilities] is unbound.
  void unbindCapabilities() {
    if (_disposed) return;
    _unsubscribe();
    _source = null;
    _slowMode.untrack();
    _reportedPanel = null;
    _capabilities.value = ComposerCapabilityState.unbound;
  }

  /// The denial of [action] in the current capabilities, with the host's
  /// text for its dimmed form, or null when it is allowed (or unbound).
  ///
  /// The text is asked once per change of the capabilities, not per build.
  ComposerDenial? actionDenial(CapabilityAction action) {
    final reason = _capabilities.value.denialOf(action);
    if (reason == null) return null;
    return _actionDenials[action] ??= (
      reason: reason,
      text: denialText(action, reason, form: ComposerDenialForm.dimmedAction),
    );
  }

  /// Whether [action] is held by slow mode now: an action that starts a
  /// send (`ActionDescriptor.heldBySlowMode`) during the wait, where the
  /// forms hold such actions.
  bool isHeldBySlowMode(ActionDescriptor action) =>
      action.heldBySlowMode &&
      _forms.slowMode.holdsSendActions &&
      _capabilities.value.slowModeActive &&
      _slowMode.state.value.holdsSend;

  /// Whether slow mode disables the primary action now: a message still
  /// sending, where the forms disable the send for it.
  bool get isSendDisabledBySlowMode =>
      _capabilities.value.slowModeActive &&
      _slowMode.state.value.pending &&
      _forms.slowMode.pendingSend == ComposerPendingSend.disabled;

  /// The forms the capabilities are drawn in, as last bound.
  ComposerDeniedForms get deniedForms => _forms;

  void _trackSlowMode(SlowMode value) =>
      _slowMode.track(value, refresh: _forms.slowMode.refresh);

  void _onSlowModeGroup() {
    if (_slowModeGroup case final group?) _trackSlowMode(group.value);
  }

  void _onRowGroup() {
    final group = _rowGroup?.value;
    if (group == null) return;
    final before = _capabilities.value;
    final textChanged =
        !before.isBound ||
        before.writeAccess != group.writeAccess ||
        before.sending != group.sending;
    if (textChanged) _actionDenials.clear();
    _capabilities.value = ComposerCapabilityState(
      writeAccess: group.writeAccess,
      sending: group.sending,
      messageLength: group.messageLength,
      slowModeActive: group.slowModeActive,
      accessText: textChanged
          ? _accessText(group.writeAccess)
          : before.accessText,
      lockedHint: textChanged
          ? _lockedHint(group.writeAccess, group.sending)
          : before.lockedHint,
    );
    if (textChanged) _reportPanel(group.writeAccess);
  }

  String? _accessText(WriteAccess access) => switch (access.denialReason) {
    final reason? => denialText(
      CapabilityAction.sendText,
      reason,
      form: ComposerDenialForm.restrictionBar,
    ),
    null => null,
  };

  // The field is not drawn while a panel replaces the row, so its text is
  // not asked for then.
  String? _lockedHint(WriteAccess access, SendingCapabilities sending) =>
      switch ((access, sending.text.reason)) {
        (WriteAccess$CanWrite(), final reason?) => denialText(
          CapabilityAction.sendText,
          reason,
          form: ComposerDenialForm.lockedField,
        ),
        _ => null,
      };

  // Once per change of the choice: a new value with the same write access
  // says nothing new.
  void _reportPanel(WriteAccess access) {
    final panel = ComposerPanelId.forWriteAccess(access);
    final choice = <String, Object>{
      'writeAccess': access.diagnosticForm,
      if (access case WriteAccess$Restricted(:final reason))
        'reason': reason.diagnosticForm,
      if (access case WriteAccess$Custom(:final tag))
        'tag': ChatEvent.clip(tag),
      'panel': ChatEvent.clip((panel ?? ComposerPanelId.text).value),
      'builder': switch (panel) {
        null => 'field',
        final panel when _hostBuilds(panel) => 'host',
        _ => 'default',
      },
    };
    if (_samePanelChoice(choice, _reportedPanel)) return;
    _reportedPanel = choice;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.capabilities,
      ComposerOp.panelChosen,
      correlation: correlation,
      fields: () => choice,
    );
  }

  static bool _samePanelChoice(Map<String, Object> a, Map<String, Object>? b) {
    if (b == null || a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (b[key] != value) return false;
    }
    return true;
  }

  void _unsubscribe() {
    _rowGroup?.removeListener(_onRowGroup);
    _rowGroup = null;
    _slowModeGroup?.removeListener(_onSlowModeGroup);
    _slowModeGroup = null;
  }

  // --- Slow mode ---

  /// Slow mode's countdown as the composer draws it: the wait left and
  /// whether a message is still sending, redrawn while the wait runs.
  ///
  /// [ComposerSlowModeState.free] until capabilities with a slow mode are
  /// bound. It changes on each redraw while counting, and at once on a new
  /// value from the host (slow mode cleared, a bypass); the countdown ends
  /// at the next send time without one. No timer runs while slow mode
  /// holds nothing or nothing is bound.
  listen.ValueListenable<ComposerSlowModeState> get slowMode => _slowMode.state;

  /// Each start and end of slow mode's countdown, as it happens: what a
  /// view announces (politely). A listener that subscribes during a
  /// running countdown hears only its end.
  ///
  /// The same moments report `capabilities / slowModeStarted` and
  /// `slowModeEnded` (debug) with the interval, the wait left and whether a
  /// message is pending.
  Stream<ComposerSlowModeEdge> get slowModeEdges => _slowMode.edges;

  /// Whether slow mode holds a send now: during the countdown, or while a
  /// message is still sending. When it does, the text stays where it is
  /// and the attempt is reported as `sendNow` with the wait left
  /// ([reportDenied], its own repeat window); the reason is the state's
  /// [ComposerSlowModeState.denial].
  ///
  /// Read at [clock] from the last bound value, so a send between two
  /// redraws is judged by the time it is made.
  bool refuseEarlySend() {
    if (_disposed) return false;
    final state = _slowMode.now();
    final reason = state.denial;
    if (reason == null) return false;
    reportDenied(
      CapabilityAction.sendNow,
      reason,
      remaining: state.isCounting ? state.remaining : null,
    );
    return true;
  }

  // --- Lifecycle ---

  /// Stops listening and disposes what this controller created. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final guard in _deniedGuards.values) {
      guard.cancel();
    }
    _deniedGuards.clear();
    _unsubscribe();
    _slowMode.dispose();
    _capabilities.dispose();
    _detachClipboard?.call();
    text.removeListener(_detectQuery);
    _softKeyboard.dispose();
    _keyboardRequests.dispose();
    _caretReveals.dispose();
    _selectionUiHides.dispose();
    _fieldHeight.dispose();
    _extent.dispose();
    _query.dispose();
    undoHistory.dispose();
    if (_ownsText) text.dispose();
    if (_ownsFocus) focusNode.dispose();
    if (_ownsScroll) fieldScroll.dispose();
  }
}

/// The composer as the field whose clipboard commands a platform performs
/// itself (a browser's): see [RichClipboard.attach].
final class _ClipboardField implements RichClipboardField {
  _ClipboardField(this._composer);

  final ComposerController _composer;

  @override
  bool get hasFocus => !_composer.isDisposed && _composer.hasFocus;

  @override
  RichText? copySelection() {
    final selection = _composer.selection;
    if (!selection.isValid || selection.isCollapsed) return null;
    return _composer.richText.slice(selection.start, selection.end);
  }

  @override
  RichText? cutSelection() {
    final copied = copySelection();
    if (copied == null) return null;
    final selection = _composer.selection;
    _composer.text.replaceRange(selection.start, selection.end, RichText.empty);
    _composer._caretReveals.signal();
    return copied;
  }

  @override
  void paste(ClipboardContents contents) {
    final composer = _composer;
    unawaited(
      composer._insertPasted(
        contents,
        before: (rich: composer.richText, selection: composer.selection),
        plain: false,
      ),
    );
  }
}

/// The signal behind [ComposerController.keyboardRequests] and
/// [ComposerController.caretReveals]: `notifyListeners` is protected, so the
/// controller reaches it through this subclass.
final class _Signal extends listen.ChangeNotifier {
  void signal() => notifyListeners();
}

/// A denied action as the row draws it: why, and the host's text for its
/// dimmed form (null for the silent form).
typedef ComposerDenial = ({DenialReason reason, String? text});

// The groups the row reads, compared by value.
typedef _RowGroup = ({
  WriteAccess writeAccess,
  SendingCapabilities sending,
  int messageLength,
  bool slowModeActive,
});
