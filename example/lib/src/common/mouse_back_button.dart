import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The mouse's back button as the platform's back, on desktop: a press
/// closes what back closes (an open menu, the panel, a selection) or pops
/// the page, as a desktop chat client does.
///
/// The press goes the way the platform's back goes, as the `popRoute`
/// message of the navigation channel, so every back listener, pop scope and
/// navigator answers it in the same order. It acts on the press, not the
/// release. Android turns the button into the system back itself, and a
/// browser into its history back, so neither is handled here.
class MouseBackButton extends StatelessWidget {
  /// Handles the back button of a mouse pressed anywhere over [child].
  const MouseBackButton({required this.child, super.key});

  /// The app.
  final Widget child;

  static bool get _handled =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };

  static void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons & kBackMouseButton == 0 ||
        !_handled) {
      return;
    }
    ui.channelBuffers.push(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        const MethodCall('popRoute'),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Over the whole window, whatever the press lands on.
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onPointerDown,
    child: child,
  );
}
