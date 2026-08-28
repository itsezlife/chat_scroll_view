import 'dart:async';

import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/ios_keyboard_safe_peel.dart';
import 'package:flutter/widgets.dart';
import 'package:keyboard_insets/keyboard_insets.dart';

/// Pushes [MediaQuery] safe-top and arbitered bottom inset into [insets].
///
/// **IME vs keyboard panel.** Live [KeyboardInsets.insets] drive the soft
/// keyboard slot. Panel sizing uses
/// [KeyboardInsets.keyboardHeight] (native persistent peak / `max_inset`),
/// not collapsing animation frames.
///
/// This mixin creates and disposes [insets] and [bottomInsetController]. The
/// host [State] must invoke `super` from [initState], [didChangeDependencies],
/// and [dispose].
///
/// Override [createKeyboardPanelStore] to inject a store already [KeyboardPanelStore.load]ed
/// at app start (composer last-tab icon, panel initial page).
mixin ChatViewportInsetsBinding<T extends StatefulWidget> on State<T> {
  /// Aggregator that receives safe-top and keyboard-slot updates.
  final ChatViewportInsets insets = ChatViewportInsets();

  /// Prefs backup + last keyboard-panel type tab.
  ///
  /// Assigned in [initState] from [createKeyboardPanelStore].
  late final KeyboardPanelStore keyboardPanelStore;

  /// IME ↔ panel arbiter; single writer of the keyboard inset term.
  late final ChatBottomInsetController bottomInsetController;

  StreamSubscription<double>? _keyboardSubscription;
  VoidCallback? _forwardInset;
  late final WidgetsBindingObserver _metricsObserver;
  var _landscape = false;

  /// Cached [MediaQuery] landscape flag for keyboard-panel store lookups.
  @protected
  bool get isLandscape => _landscape;

  void _syncLandscapeFromMediaQuery() {
    final next = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (next == _landscape) return;
    _landscape = next;
  }

  /// Host may return a preloaded [KeyboardPanelStore] (e.g. from `main`).
  @protected
  KeyboardPanelStore createKeyboardPanelStore() => KeyboardPanelStore();

  /// Native persistent IME peak (`keyboard_insets` `max_inset`).
  static double? _readOsKeyboardHeight() {
    final h = KeyboardInsets.keyboardHeight;
    if (!h.isFinite || h < KeyboardPanelStore.minSaneKeyboardHeight) {
      return null;
    }
    return h;
  }

  @override
  void initState() {
    super.initState();
    _metricsObserver = _ChatViewportMetricsObserver(() {
      if (!mounted) return;
      _syncLandscapeFromMediaQuery();
    });
    WidgetsBinding.instance.addObserver(_metricsObserver);
    keyboardPanelStore = createKeyboardPanelStore();
    bottomInsetController = ChatBottomInsetController(
      store: keyboardPanelStore,
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
      _publishKeyboardInset(h);
    };
    bottomInsetController.heightListenable.addListener(_forwardInset!);
    _keyboardSubscription = KeyboardInsets.insets.listen(_onImeHeight);
    unawaited(
      keyboardPanelStore.load().then((_) {
        final os = KeyboardInsets.keyboardHeight;
        chatChromeLog(
          'KeyboardPanelStore loaded '
          'portrait=${keyboardPanelStore.heightFor(landscape: false)} '
          'selectedPage=${keyboardPanelStore.selectedPage} '
          'osPersistent=$os',
        );
        if (os.isFinite && os >= KeyboardPanelStore.minSaneKeyboardHeight) {
          unawaited(keyboardPanelStore.record(os, landscape: false));
        }
        onKeyboardPanelStoreReady();
      }),
    );
    _seedKeyboard();
  }

  /// Called after [keyboardPanelStore] finishes [KeyboardPanelStore.load].
  ///
  /// No-op by default — hosts seed composer last-tab chrome here.
  @protected
  void onKeyboardPanelStoreReady() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    insets.setSafeTop(MediaQuery.viewPaddingOf(context).top);
    insets.setSafeBottom(MediaQuery.viewPaddingOf(context).bottom);
    _syncLandscapeFromMediaQuery();
  }

  void _publishKeyboardInset(double keyboard) {
    final target = iosKeyboardOpenTarget(
      keyboard: keyboard,
      panelTarget: bottomInsetController.panelTarget,
      storedKeyboardHeight: keyboardPanelStore.heightFor(landscape: isLandscape),
    );
    insets.setKeyboardTarget(target);
    insets.setKeyboard(keyboard);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_metricsObserver);
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
          !isAnimating && height >= KeyboardPanelStore.minSaneKeyboardHeight,
    );
    _publishKeyboardInset(bottomInsetController.height);
  }
}

/// Forwards [WidgetsBindingObserver.didChangeMetrics] without bloating host
/// [State] with the full observer surface.
final class _ChatViewportMetricsObserver with WidgetsBindingObserver {
  _ChatViewportMetricsObserver(this._onMetrics);

  final VoidCallback _onMetrics;

  @override
  void didChangeMetrics() => _onMetrics();
}
