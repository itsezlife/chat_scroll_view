import 'dart:async';

import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets.dart';
import 'package:flutter/widgets.dart';
import 'package:keyboard_insets/keyboard_insets.dart';

/// Pushes [MediaQuery] safe-top and arbitered bottom inset into [insets].
///
/// **IME vs emoji panel.** Live [KeyboardInsets.insets] drive the soft
/// keyboard slot. Panel sizing uses
/// [KeyboardInsets.keyboardHeight] (native persistent peak / `max_inset`),
/// not collapsing animation frames.
///
/// This mixin creates and disposes [insets] and [bottomInsetController]. The
/// host [State] must invoke `super` from [initState], [didChangeDependencies],
/// and [dispose].
///
/// Override [createKeyboardHeightStore] to inject a store already [KeyboardHeightStore.load]ed
/// at app start (composer last-tab icon, panel initial page).
mixin ChatViewportInsetsBinding<T extends StatefulWidget> on State<T> {
  /// Aggregator that receives safe-top and keyboard-slot updates.
  final ChatViewportInsets insets = ChatViewportInsets();

  /// Prefs backup + last emoji type tab.
  ///
  /// Assigned in [initState] from [createKeyboardHeightStore].
  late final KeyboardHeightStore keyboardHeightStore;

  /// IME ↔ panel arbiter; single writer of the keyboard inset term.
  late final ChatBottomInsetController bottomInsetController;

  StreamSubscription<double>? _keyboardSubscription;
  VoidCallback? _forwardInset;
  var _landscape = false;

  /// Host may return a preloaded [KeyboardHeightStore] (e.g. from `main`).
  @protected
  KeyboardHeightStore createKeyboardHeightStore() => KeyboardHeightStore();

  /// Native persistent IME peak (`keyboard_insets` `max_inset`).
  static double? _readOsKeyboardHeight() {
    final h = KeyboardInsets.keyboardHeight;
    if (!h.isFinite || h < KeyboardHeightStore.minSaneKeyboardHeight) {
      return null;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    keyboardHeightStore = createKeyboardHeightStore();
    bottomInsetController = ChatBottomInsetController(
      store: keyboardHeightStore,
      osKeyboardHeight: _readOsKeyboardHeight,
    );
    _forwardInset = () {
      final h = bottomInsetController.height;
      chatChromeLog(
        'forward inset→ChatViewportInsets h=$h '
        'owner=${bottomInsetController.owner} '
        'panel=${bottomInsetController.isPanelOpen} '
        'osKbd=${KeyboardInsets.keyboardHeight}',
      );
      insets.setKeyboard(h);
    };
    bottomInsetController.heightListenable.addListener(_forwardInset!);
    _keyboardSubscription = KeyboardInsets.insets.listen(_onImeHeight);
    unawaited(
      keyboardHeightStore.load().then((_) {
        final os = KeyboardInsets.keyboardHeight;
        chatChromeLog(
          'KeyboardHeightStore loaded '
          'portrait=${keyboardHeightStore.heightFor(landscape: false)} '
          'selectedPage=${keyboardHeightStore.selectedPage} '
          'osPersistent=$os',
        );
        if (os.isFinite && os >= KeyboardHeightStore.minSaneKeyboardHeight) {
          unawaited(keyboardHeightStore.record(os, landscape: false));
        }
        onKeyboardHeightStoreReady();
      }),
    );
    _seedKeyboard();
  }

  /// Called after [keyboardHeightStore] finishes [KeyboardHeightStore.load].
  ///
  /// No-op by default — hosts seed composer last-tab chrome here.
  @protected
  void onKeyboardHeightStoreReady() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    insets.setSafeTop(MediaQuery.viewPaddingOf(context).top);
    _landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  @override
  void dispose() {
    _keyboardSubscription?.cancel();
    final forward = _forwardInset;
    if (forward != null) {
      bottomInsetController.heightListenable.removeListener(forward);
    }
    bottomInsetController.dispose();
    insets.dispose();
    super.dispose();
  }

  void _onImeHeight(double height) {
    bottomInsetController.onImeHeight(
      height,
      landscape: _landscape,
      record: !KeyboardInsets.isAnimating,
    );
  }

  void _seedKeyboard() {
    final isVisible = KeyboardInsets.isVisible;
    final isAnimating = KeyboardInsets.isAnimating;
    final persistent = KeyboardInsets.keyboardHeight;
    final height = isVisible && !isAnimating
        ? KeyboardInsets.keyboardHeight
        : 0.0;
    chatChromeLog(
      'seedKeyboard visible=$isVisible animating=$isAnimating '
      'liveOrZero=$height osPersistent=$persistent',
    );
    bottomInsetController.onImeHeight(
      height,
      landscape: _landscape,
      record:
          !isAnimating && height >= KeyboardHeightStore.minSaneKeyboardHeight,
    );
    insets.setKeyboard(bottomInsetController.height);
  }
}
