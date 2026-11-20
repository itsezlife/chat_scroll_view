import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:attach_sheet/attach_sheet.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/ime_sample_feed.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/common/widgets/listen_value_builder.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/composer_panel_field.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/emoji_panel_page.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart' hide RichText;
import 'package:glyph_atlas/glyph_atlas.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

/// The attach caption's dock: the chat's own keyboard-replacement stack
/// (the presentation, its keyboard slot and occupancy, the swap in
/// [KeyboardPanelDock], the panel's glass surface), with the chat's emoji
/// page alone, typing into the caption.
///
/// The caption bar stands on [buildPlace] as the chat's composer stands on
/// its panel's place: the place is the raised keyboard or the panel,
/// whichever stands, the bottom safe area in it; the bar pads the part of
/// the safe area the place does not cover ([fieldBottomPad]).
final class ChatCaptionDock implements AttachCaptionDock {
  /// The dock of [caption] over [services], in [view]; [keyboard] is the
  /// platform's soft keyboard; [onDispose] runs as the dock is disposed.
  factory ChatCaptionDock({
    required AppServices services,
    required FlutterView view,
    required ComposerController caption,
    SoftKeyboardPort keyboard = const PlatformSoftKeyboard(),
    VoidCallback? onDispose,
  }) {
    final ime = ImeInput();
    final window = listen.ValueNotifier<PanelWindow>(
      const PanelWindow(width: 0, height: 0),
    );
    final slot = KeyboardReplacementStrategy(
      ime: ime,
      heights: services.keyboardHeights,
      window: window,
    );
    final frames = SchedulerBakeFrameSource(view: view);
    final shell = PanelShellController(
      pages: [
        EmojiPanelPage.of(
          services: services,
          frames: frames,
          // Over a raised keyboard the panel is on screen at once; rising
          // into a free place it mounts while nothing else moves.
          deferChrome: () => !slot.keyboardIsUp,
        ),
      ],
      preferences: services.preferences,
    );
    final presentation = PanelPresentationController(
      shell: shell,
      policy: const PanelPresentationPolicy.mobile(),
      strategies: [slot],
    );
    return ChatCaptionDock._(
      services: services,
      caption: caption,
      keyboard: keyboard,
      ime: ime,
      window: window,
      slot: slot,
      frames: frames,
      shell: shell,
      presentation: presentation,
      onDispose: onDispose,
    );
  }

  ChatCaptionDock._({
    required this.services,
    required this.caption,
    required SoftKeyboardPort keyboard,
    required this.ime,
    required listen.ValueNotifier<PanelWindow> window,
    required this.slot,
    required SchedulerBakeFrameSource frames,
    required this.shell,
    required this.presentation,
    VoidCallback? onDispose,
  }) : _onDispose = onDispose,
       _keyboard = keyboard,
       _window = window,
       _frames = frames {
    _feed = ImeSampleFeed(keyboard: keyboard, ime: ime);
    swap = KeyboardPanelDock(
      presentation: presentation,
      keyboard: slot,
      field: ComposerPanelField(caption),
      hideKeyboard: _hideKeyboard,
    );
    _events = shell.events.listen(_onEvent);
    slot.composerSafeInset.addListener(_onPad);
    presentation.state.addListener(_onState);
    _onPad();
  }

  /// The app's services: the emoji sources, the recents, the previews.
  final AppServices services;

  /// The caption the panel types into.
  final ComposerController caption;

  /// The keyboard samples the slot follows.
  final ImeInput ime;

  /// The strategy that puts the panel in the keyboard's place.
  final KeyboardReplacementStrategy slot;

  /// The panel's shell: the emoji page alone.
  final PanelShellController shell;

  /// The panel's presentation.
  final PanelPresentationController presentation;

  /// The swap between the caption's keyboard and the panel.
  late final KeyboardPanelDock swap;

  final VoidCallback? _onDispose;
  final SoftKeyboardPort _keyboard;
  final listen.ValueNotifier<PanelWindow> _window;
  final SchedulerBakeFrameSource _frames;
  late final ImeSampleFeed _feed;
  late final StreamSubscription<PanelEvent> _events;
  final _changes = ValueNotifier<bool>(false);
  final _pad = ValueNotifier<double>(0);
  var _disposed = false;

  Future<void> _hideKeyboard(String why) async {
    AttachLog.log(AttachLog.ime, 'caption keyboard hide: $why');
    await _keyboard.hide();
  }

  void _onPad() => _pad.value = slot.composerSafeInset.value;

  void _onState() {
    final up = swap.panelInKeyboardPlace;
    if (up == _changes.value) return;
    AttachLog.log(AttachLog.panel, 'caption panel ${up ? 'up' : 'down'}');
    _changes.value = up;
  }

  void _onEvent(PanelEvent event) {
    switch (event) {
      case ContentPicked(:final key, :final recentsKind, :final source):
        final text = switch (key) {
          ContentKey$Unicode(:final sequence) => sequence,
          _ => AnimatedEmojiPack.of(key)?.sequence,
        };
        if (text == null) return;
        unawaited(HapticFeedback.selectionClick());
        caption.insertContent(
          InlineContentRef(key: key, alternativeText: text),
        );
        unawaited(
          services.recents.record(key, kind: recentsKind, source: source),
        );
      case BackspaceRequested():
        unawaited(HapticFeedback.selectionClick());
        caption.backspace();
      default:
        break;
    }
  }

  @override
  Listenable get changes => _changes;

  @override
  bool get panelUp => swap.panelInKeyboardPlace;

  @override
  void togglePanel() => swap.toggle();

  @override
  void onFieldTap() => swap.onFieldTap();

  @override
  void onFieldPointerDown() => swap.onFieldPointerDown();

  @override
  void onFieldPointerEnd() => swap.onFieldPointerEnd();

  @override
  ValueListenable<double> get fieldBottomPad => _pad;

  @override
  Widget buildPlace(BuildContext context) => _DockPlace(dock: this);

  /// Back, in the chat's order: a content preview over the panel first; a
  /// hand-off under way ends with both going down; with search open over a
  /// raised keyboard the keyboard goes; then the panel.
  @override
  bool handleBack() {
    if (_disposed) return false;
    if (services.previews.dismiss()) return true;
    if (swap.backDuringHandOff()) return true;
    if (shell.search.value.isOpen && _feed.height > 1) {
      unawaited(_hideKeyboard('back with search open'));
      return true;
    }
    return presentation.handleBack();
  }

  @override
  void closePanel() {
    if (presentation.state.value.isVisible) presentation.hide();
  }

  // The screen the place stands in: its size and its bottom safe area.
  void _environment({required Size size, required double safeBottom}) {
    if (_disposed) return;
    final window = PanelWindow(width: size.width, height: size.height);
    if (_window.value != window) {
      _window.value = window;
      presentation.updateWindow(window);
    }
    _feed.safeBottom = safeBottom;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose?.call();
    presentation.state.removeListener(_onState);
    slot.composerSafeInset.removeListener(_onPad);
    unawaited(_events.cancel());
    swap.dispose();
    _feed.dispose();
    presentation.dispose();
    slot.dispose();
    shell.dispose();
    _frames.dispose();
    ime.dispose();
    _window.dispose();
    _changes.dispose();
    _pad.dispose();
  }
}

// The place under the caption bar: the chat's panel view at the height of
// the occupancy, as the chat's bottom chrome lays it out.
class _DockPlace extends StatefulWidget {
  const _DockPlace({required this.dock});

  final ChatCaptionDock dock;

  @override
  State<_DockPlace> createState() => _DockPlaceState();
}

class _DockPlaceState extends State<_DockPlace> {
  // Built once: the strategy keeps the shell mounted, and a frame of the
  // slot's motion rebuilds only the box around it.
  late final Widget _view = RepaintBoundary(
    child: PanelPresentationView(controller: widget.dock.presentation),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _report();
  }

  void _report() => widget.dock._environment(
    size: MediaQuery.sizeOf(context),
    safeBottom: MediaQuery.viewPaddingOf(context).bottom,
  );

  @override
  Widget build(BuildContext context) => ListenValueBuilder<PanelOccupancy>(
    listenable: widget.dock.presentation.occupancy,
    builder: (context, occupancy) =>
        SizedBox(height: occupancy.bottom, child: _view),
  );
}
