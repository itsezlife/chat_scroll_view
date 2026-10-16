import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackClaim;
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/emoji_panel_page.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/stub_panel_pages.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart' hide RichText;
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

/// What the screen does with what the input set produces.
typedef ChatBodySender = Future<void> Function(String body);

/// Saves the edited [body] of message [id].
typedef ChatBodyEditor = Future<void> Function(int id, String body);

/// Asks the user whether to clear the recent content of [kind]; true when
/// they agreed.
typedef ClearRecentsConfirm = Future<bool> Function(SemanticKind kind);

/// The message being edited: what the composer's header names.
@immutable
final class ChatEditTarget {
  /// Edit of message [id], whose text reads [preview].
  const ChatEditTarget({required this.id, required this.preview});

  /// The message id.
  final int id;

  /// The message text, for the header.
  final String preview;

  @override
  bool operator ==(Object other) =>
      other is ChatEditTarget && other.id == id && other.preview == preview;

  @override
  int get hashCode => Object.hash(id, preview);
}

/// The per-chat controller set: everything one chat screen creates, wires to
/// the app's [AppServices] and disposes with the screen.
///
/// | Created here | Role |
/// | --- | --- |
/// | [composer] | the input: text, focus, extent, soft-keyboard option |
/// | [shell] | the panel's pages, search and events (one emoji page) |
/// | [presentation] | where the panel appears and how much space it takes |
/// | the three strategies | keyboard replacement, anchored popup, docked |
/// | [insets] | the aggregation into what the viewport reserves |
///
/// The creator disposes: [dispose] frees all of the above in the reverse of
/// the order they were made, and leaves [AppServices] as it found it. The
/// shell disposes the page controllers it holds, among them the glyph atlas
/// host of the emoji page.
///
/// What the set decides, in one place each:
///
/// - **Insert and record.** A picked emoji becomes an inline content
///   reference in the composer and one `RecentsStore.record`; backspace edits
///   the composer; clearing recents asks [confirmClearRecents] first.
/// - **Soft keyboard.** While a keyboard-replacement panel is on screen the
///   composer declares no soft keyboard; every other time it does. A raised
///   keyboard is asked to lower when the panel takes its place, and is asked
///   for again only when the panel leaves for it ([handOffToKeyboard]): a
///   panel closed with back leaves focus in the field and the keyboard down.
/// - **Paced mount.** A panel that grows into a free slot mounts its page over
///   three frames (grid, search field, strip); one that replaces the keyboard
///   mounts at once.
/// - **Back.** While the panel is on screen the set holds a pre-IME back claim
///   so back closes search, then the panel.
final class ChatInputSet {
  /// Creates the set for one chat screen.
  ///
  /// [view] is the screen's view (the atlas bakes on its frames), [keyboard]
  /// the soft keyboard's readings and commands. [send] and [edit] take the
  /// markdown body of a message. [policy] defaults to the one of the platform.
  factory ChatInputSet({
    required AppServices services,
    required FlutterView view,
    required ChatBodySender send,
    required ChatBodyEditor edit,
    required ClearRecentsConfirm confirmClearRecents,
    SoftKeyboardPort keyboard = const PlatformSoftKeyboard(),
    PanelPresentationPolicy? policy,
  }) {
    // What has been made so far, to free in reverse if a later step throws
    // (a constructor assertion, a keyboard that cannot be read): a half-built
    // set has no handle for anyone to dispose.
    final unwind = <void Function()>[];
    T owned<T>(T value, void Function(T value) dispose) {
      unwind.add(() => dispose(value));
      return value;
    }

    try {
      final ime = owned(ImeInput(), (ime) => ime.dispose());
      final window = owned(
        listen.ValueNotifier<PanelWindow>(
          const PanelWindow(width: 0, height: 0),
        ),
        (window) => window.dispose(),
      );
      final text = owned(
        ComposerTextController(
          inlineContentBuilder: contentSpanBuilder(scope: services.assets),
        ),
        (text) => text.dispose(),
      );
      final composer = owned(
        ComposerController(text: text),
        (composer) => composer.dispose(),
      );
      final keyboardStrategy = owned(
        KeyboardReplacementStrategy(
          ime: ime,
          heights: services.keyboardHeights,
          window: window,
        ),
        (strategy) => strategy.dispose(),
      );
      final popup = owned(
        AnchoredPopupStrategy(
          style: _popupStyle,
          composerFocus: composer.focusNode,
        ),
        (strategy) => strategy.dispose(),
      );
      final docked = owned(
        DockedStrategy(style: _dockedStyle, composerFocus: composer.focusNode),
        (strategy) => strategy.dispose(),
      );
      late final ChatInputSet set;
      final frames = owned(
        SchedulerBakeFrameSource(view: view),
        (frames) => frames.dispose(),
      );
      final shell = owned(
        PanelShellController(
          pages: [
            EmojiPanelPage.of(
              services: services,
              frames: frames,
              // The panel that grows into a free slot mounts while nothing
              // else moves; the one that replaces the keyboard is on screen
              // already.
              deferChrome: () =>
                  set.presentation.state.value.kind is KeyboardReplacement &&
                  !keyboardStrategy.keyboardIsUp,
            ),
            // Type tabs in the order of the panel: emoji, GIFs, stickers.
            StubPanelPages.gif(),
            StubPanelPages.stickers(),
          ],
          preferences: services.preferences,
        ),
        (shell) => shell.dispose(),
      );
      final presentation = owned(
        PanelPresentationController(
          shell: shell,
          policy: policy,
          strategies: [keyboardStrategy, popup, docked],
          window: window.value,
          preferences: services.preferences,
        ),
        (presentation) => presentation.dispose(),
      );
      final insets = owned(
        ChatViewportInsets(
          composerExtent: composer.extent,
          occupancy: presentation.occupancy,
        ),
        (insets) => insets.dispose(),
      );
      return set = ChatInputSet._(
        services: services,
        frames: frames,
        keyboardPort: keyboard,
        send: send,
        edit: edit,
        confirmClearRecents: confirmClearRecents,
        ime: ime,
        window: window,
        text: text,
        composer: composer,
        keyboardStrategy: keyboardStrategy,
        popup: popup,
        docked: docked,
        shell: shell,
        presentation: presentation,
        insets: insets,
      );
    } on Object {
      for (final undo in unwind.reversed) {
        undo();
      }
      rethrow;
    }
  }

  ChatInputSet._({
    required this.services,
    required SchedulerBakeFrameSource frames,
    required SoftKeyboardPort keyboardPort,
    required ChatBodySender send,
    required ChatBodyEditor edit,
    required ClearRecentsConfirm confirmClearRecents,
    required this.ime,
    required listen.ValueNotifier<PanelWindow> window,
    required ComposerTextController text,
    required this.composer,
    required this.keyboardStrategy,
    required this.popup,
    required this.docked,
    required this.shell,
    required this.presentation,
    required this.insets,
  }) : _frames = frames,
       _keyboardPort = keyboardPort,
       _send = send,
       _edit = edit,
       _confirmClearRecents = confirmClearRecents,
       _window = window,
       _text = text {
    StreamSubscription<double>? heights;
    StreamSubscription<PanelEvent>? panelEvents;
    try {
      // A screen opened with the keyboard already up has no stream event yet.
      _lastImeHeight = keyboardPort.restingHeight;
      _imeHeights = heights = keyboardPort.heights.listen(_onImeHeight);
      _panelEvents = panelEvents = shell.events.listen(_onPanelEvent);
      presentation.state.addListener(_onPresentationState);
      _onPresentationState();
    } on Object {
      // The factory frees what it passed in; the rest is this object's.
      unawaited(heights?.cancel());
      unawaited(panelEvents?.cancel());
      presentation.state.removeListener(_onPresentationState);
      _editing.dispose();
      _busy.dispose();
      rethrow;
    }
  }

  static const AnchoredPopupStyle _popupStyle = AnchoredPopupStyle(
    width: 380,
    cornerRadius: 14,
    shadows: <BoxShadow>[
      BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
  );

  static const DockedStyle _dockedStyle = DockedStyle(
    width: 360,
    separator: Color(0x24FFFFFF),
  );

  /// The app's services this set is wired to.
  final AppServices services;

  /// The single port the soft keyboard's readings enter the presentation by.
  final ImeInput ime;

  /// The input.
  final ComposerController composer;

  /// The keyboard-replacement strategy (mobile).
  final KeyboardReplacementStrategy keyboardStrategy;

  /// The anchored-popup strategy (desktop and web).
  final AnchoredPopupStrategy popup;

  /// The docked strategy (desktop and web, wide windows).
  final DockedStrategy docked;

  /// The panel's pages, search and events.
  final PanelShellController shell;

  /// Where the panel appears.
  final PanelPresentationController presentation;

  /// What the viewport reserves for the composer and the panel.
  final ChatViewportInsets insets;

  final SchedulerBakeFrameSource _frames;
  final SoftKeyboardPort _keyboardPort;
  final ChatBodySender _send;
  final ChatBodyEditor _edit;
  final ClearRecentsConfirm _confirmClearRecents;
  final listen.ValueNotifier<PanelWindow> _window;
  final ComposerTextController _text;

  final ValueNotifier<ChatEditTarget?> _editing =
      ValueNotifier<ChatEditTarget?>(null);
  final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);

  late StreamSubscription<double> _imeHeights;
  late StreamSubscription<PanelEvent> _panelEvents;
  double _lastImeHeight = 0;
  double _safeBottom = 0;
  ChatPreImeBackClaim? _backClaim;
  var _handingOff = false;
  var _wasVisible = false;
  var _disposed = false;

  // --- State ----------------------------------------------------------------

  /// The message being edited, or null.
  ValueListenable<ChatEditTarget?> get editing => _editing;

  /// Whether a send or an edit is in flight.
  ValueListenable<bool> get busy => _busy;

  /// Whether the panel is on screen or on its way there (not on its way out).
  bool get isPanelOpening => switch (presentation.state.value) {
    PanelVisibility$Showing() || PanelVisibility$Shown() => true,
    PanelVisibility$Hiding() || PanelVisibility$Hidden() => false,
  };

  /// Whether the panel is on screen in any phase.
  bool get isPanelVisible => presentation.state.value.isVisible;

  /// The icon of the page the panel is showing, for the composer's toggle.
  ChromeIconId get pageIcon => shell.selectedPage.tab.icon;

  /// The part of the bottom safe area the keyboard presentation's occupancy
  /// has not covered yet: the composer's bottom pad. A host of a platform
  /// with no keyboard presentation leaves the composer its default pad.
  listen.ValueListenable<double>? get composerSafeInset =>
      presentation.policy is PanelPresentationPolicy$Mobile
      ? keyboardStrategy.composerSafeInset
      : null;

  // --- Environment ----------------------------------------------------------

  /// Tells the set what the view looks like now: the window, the safe top and
  /// the bottom safe area. Called whenever they may have changed.
  void updateEnvironment({
    required Size size,
    required double safeTop,
    required double safeBottom,
  }) {
    if (_disposed) return;
    insets
      ..setSafeTop(safeTop)
      ..setSafeBottom(safeBottom);
    final window = PanelWindow(width: size.width, height: size.height);
    if (_window.value != window) {
      _window.value = window;
      presentation.updateWindow(window);
    }
    if (_safeBottom != safeBottom) {
      _safeBottom = safeBottom;
      _reportIme();
    }
  }

  /// Tells the popup where the composer is, in the coordinates of the box the
  /// presentation view fills.
  void anchorTo(Rect composerRect) {
    if (_disposed) return;
    presentation.anchor(composerRect);
  }

  /// Applies the chrome theme to the text the composer shows.
  void applyTheme(ComposerTokens tokens) {
    if (_disposed) return;
    _text.entityStyles = ComposerEntityStyles.fromTokens(tokens);
  }

  // --- Composer -------------------------------------------------------------

  /// Loads the message [id] with the markdown body [body] into the composer
  /// for editing.
  void beginEdit(int id, String body) {
    if (_disposed) return;
    final text = ChatBodyMarkdown.decode(body);
    composer.restore(
      text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _editing.value = ChatEditTarget(id: id, preview: text.plain);
    composer.requestFocus();
  }

  /// Leaves edit mode and empties the composer.
  void cancelEdit() {
    if (_disposed || _editing.value == null) return;
    _editing.value = null;
    composer.clear();
  }

  /// Sends what the composer holds, or saves the edit; keeps the text when
  /// that fails. Does nothing for a blank composer or while one is in flight.
  Future<void> submit() async {
    if (_disposed || _busy.value) return;
    final rich = composer.richText;
    if (rich.plain.trim().isEmpty) return;
    final body = ChatBodyMarkdown.encode(rich);
    final target = _editing.value;
    _busy.value = true;
    try {
      if (target != null) {
        await _edit(target.id, body);
      } else {
        await _send(body);
      }
      if (_disposed) return;
      composer.clear();
      _editing.value = null;
    } finally {
      if (!_disposed) _busy.value = false;
    }
  }

  // --- Panel ----------------------------------------------------------------

  /// The composer's panel button.
  void togglePanel() {
    if (_disposed) return;
    final state = presentation.state.value;
    switch (state) {
      case PanelVisibility$Showing() || PanelVisibility$Shown():
        if (state.kind is KeyboardReplacement) {
          handOffToKeyboard();
        } else {
          presentation.hide();
        }
      case PanelVisibility$Hiding(:final kind):
        // The press that reached this button was outside the popup and has
        // just closed it; the same click must not open it again.
        if (kind is! AnchoredPopup) presentation.show();
      case PanelVisibility$Hidden():
        presentation.show();
    }
  }

  /// A tap on the composer's field: back to the keyboard while a panel
  /// replaces it.
  void onFieldTap() {
    if (_disposed) return;
    final state = presentation.state.value;
    if (state.kind is KeyboardReplacement && isPanelOpening) {
      handOffToKeyboard();
    }
  }

  /// Gives the slot back to the soft keyboard: focus stays in the composer,
  /// search closes, and the panel keeps its slot, emptied, until the keyboard
  /// has risen.
  void handOffToKeyboard() {
    if (_disposed || _handingOff) return;
    _handingOff = true;
    shell.closeSearch();
    presentation.hide(waitForIme: true);
    // Hiding lifts the suppression; the keyboard is asked for here and only
    // here, so a panel closed any other way (back) leaves it down. The field
    // answers after the frame, focusing or attaching again as it needs to.
    composer.requestKeyboard();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handingOff = false);
  }

  /// Back: with search focused over a raised keyboard, the keyboard goes
  /// first; then search closes; then the panel. True when it consumed the
  /// press.
  Future<bool> handleBack() async {
    if (_disposed) return false;
    if (shell.search.value.isOpen && ime.samples.value.height > 1) {
      await _keyboardPort.hide();
      return true;
    }
    return presentation.handleBack();
  }

  // --- Wiring ---------------------------------------------------------------

  void _onPanelEvent(PanelEvent event) {
    switch (event) {
      case ContentPicked(:final key, :final kind, :final source):
        unawaited(HapticFeedback.selectionClick());
        if (key is ContentKey$Unicode && kind == SemanticKind.unicodeEmoji) {
          composer.insertContent(
            InlineContentRef(key: key, alternativeText: key.sequence),
          );
        }
        unawaited(services.recents.record(key, kind: kind, source: source));
      case BackspaceRequested():
        unawaited(HapticFeedback.selectionClick());
        composer.backspace();
      case ClearRecentsRequested(:final kind):
        unawaited(HapticFeedback.mediumImpact());
        unawaited(_clearRecents(kind));
      case SearchClosed():
        // What was picked while searching is listed once search is over.
        services.recentsShown.commit();
        // The search field's keyboard goes with its focus; the composer takes
        // it back, still with no keyboard of its own while the panel is up.
        if (isPanelVisible) composer.requestFocus();
      case ActionInvoked() || PageChanged() || SearchOpened():
        break;
    }
  }

  Future<void> _clearRecents(SemanticKind kind) async {
    if (!await _confirmClearRecents(kind) || _disposed) return;
    await services.recents.clear(kind: kind);
  }

  void _onPresentationState() {
    final state = presentation.state.value;
    // The panel shows the recents as of the moment it opens: what was picked
    // in the last session is listed now, not while the user picks.
    final opened = !_wasVisible && state.isVisible;
    if (opened) services.recentsShown.commit();
    _wasVisible = state.isVisible;
    if (opened && state.kind is KeyboardReplacement) _dismissKeyboardForPanel();
    // The panel stands in for the keyboard only while it is coming or on
    // screen; once it is leaving, the field is a field again.
    composer.setSoftKeyboard(
      isPanelOpening && state.kind is KeyboardReplacement
          ? SoftKeyboardMode.suppressed
          : SoftKeyboardMode.auto,
    );
    if (state.isVisible) {
      _backClaim ??= ChatPreImeBackClaim.push(handleBack);
    } else {
      _backClaim?.pop();
      _backClaim = null;
    }
  }

  // A keyboard that is up when the panel takes its place goes down, and focus
  // stays in the field, caret and hardware keys included. Declaring no soft
  // keyboard (`SoftKeyboardMode.suppressed`) keeps the next focus from raising
  // one; it does not lower the one that is showing, which needs the command.
  void _dismissKeyboardForPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !isPanelOpening) return;
      unawaited(_keyboardPort.hide());
    });
  }

  void _onImeHeight(double height) {
    _lastImeHeight = height;
    _reportIme();
  }

  // The slot measures the keyboard with the bottom safe area in it. A
  // platform that reports it without that band gets the band added back
  // while the keyboard shows any height at all: an inset of nothing means
  // no keyboard, and the band is the safe area's own.
  double get _imeHeightWithSafeArea {
    final height = math.max<double>(0, _lastImeHeight);
    if (_keyboardPort.heightsIncludeSafeArea || height <= 0) return height;
    return height + _safeBottom;
  }

  void _reportIme() {
    if (_disposed) return;
    ime.report(
      ImeSample(
        height: _imeHeightWithSafeArea,
        animating: _keyboardPort.isAnimating,
        safeAreaBottom: _safeBottom,
      ),
    );
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Frees everything this set created, in the reverse of the order it made
  /// it. Idempotent. [AppServices] is left as it was.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _backClaim?.pop();
    _backClaim = null;
    unawaited(_imeHeights.cancel());
    unawaited(_panelEvents.cancel());
    presentation.state.removeListener(_onPresentationState);
    insets.dispose();
    presentation.dispose();
    keyboardStrategy.dispose();
    popup.dispose();
    docked.dispose();
    shell.dispose();
    ime.dispose();
    _window.dispose();
    _frames.dispose();
    composer.dispose();
    _text.dispose();
    _editing.dispose();
    _busy.dispose();
  }
}
