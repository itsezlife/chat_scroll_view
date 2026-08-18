import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets.dart';
import 'package:flutter/widgets.dart';
import 'package:keyboard_insets/keyboard_insets.dart';

/// Pushes [MediaQuery] safe-top and [KeyboardInsets] into [insets].
///
/// Mix into the [State] that hosts a chat viewport so that [State] owns the
/// subscriptions. Does **not** observe [PersistentSafeAreaBottom]: composer
/// height already includes `viewPadding.bottom` from layout, and wiring the
/// observer into [ChatViewportInsets.bottomPadding] would double-count it.
///
/// This mixin creates and disposes [insets]. The host [State] must invoke
/// `super` from [initState], [didChangeDependencies], and [dispose].
mixin ChatViewportInsetsBinding<T extends StatefulWidget> on State<T> {
  /// Aggregator that receives safe-top and keyboard updates.
  final ChatViewportInsets insets = ChatViewportInsets();

  StreamSubscription<double>? _keyboardSubscription;

  @override
  void initState() {
    super.initState();
    _keyboardSubscription = KeyboardInsets.insets.listen(insets.setKeyboard);
    _seedKeyboard();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    insets.setSafeTop(MediaQuery.viewPaddingOf(context).top);
  }

  @override
  void dispose() {
    _keyboardSubscription?.cancel();
    insets.dispose();
    super.dispose();
  }

  void _seedKeyboard() {
    final isVisible = KeyboardInsets.isVisible;
    final isAnimating = KeyboardInsets.isAnimating;
    insets.setKeyboard(
      isVisible && !isAnimating ? KeyboardInsets.keyboardHeight : 0,
    );
  }
}
