import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:keyboard_insets/keyboard_insets.dart';

/// What the host knows of the on-screen keyboard and can ask of it: the one
/// seam between the platform and the chat's input set.
///
/// The presentation package never touches a platform channel (ADR 031), so the
/// raw readings and the command live here, in the host.
abstract interface class SoftKeyboardPort {
  /// The keyboard's height as the system reports it, frame by frame while it
  /// moves; zero when it is hidden.
  Stream<double> get heights;

  /// Whether the system is moving the keyboard now. A height read while this
  /// is true is not a settled size.
  bool get isAnimating;

  /// The height of a keyboard that is up and at rest, or zero.
  double get restingHeight;

  /// Whether [heights] count the bottom safe area (the home indicator, the
  /// navigation bar) as part of the keyboard.
  ///
  /// The panel's slot measures the keyboard as the space it takes at the
  /// bottom of the window, safe area included. A platform that reports the
  /// keyboard without that band must say so, so the host can add it back
  /// before the reading reaches the presentation.
  bool get heightsIncludeSafeArea;

  /// Hides the on-screen keyboard, leaving focus where it is.
  Future<void> hide();
}

/// The [SoftKeyboardPort] over the `keyboard_insets` plugin and the text-input
/// channel. Desktop and tests have no keyboard: readings stay zero and the
/// commands are no-ops.
final class PlatformSoftKeyboard implements SoftKeyboardPort {
  /// The platform keyboard.
  const PlatformSoftKeyboard();

  @override
  Stream<double> get heights => KeyboardInsets.insets;

  // iOS reports the distance from the keyboard's top edge to the bottom of
  // the screen, home indicator included. The Android plugin subtracts the
  // system bars from the IME inset, so its readings stop at the navigation
  // bar.
  @override
  bool get heightsIncludeSafeArea =>
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get isAnimating => KeyboardInsets.isAnimating;

  @override
  double get restingHeight {
    final height = KeyboardInsets.keyboardHeight;
    return KeyboardInsets.isVisible && !isAnimating && height.isFinite
        ? height
        : 0;
  }

  @override
  Future<void> hide() => _invoke('TextInput.hide');

  Future<void> _invoke(String method) async {
    try {
      await SystemChannels.textInput.invokeMethod<void>(method);
    } on MissingPluginException {
      // Desktop and tests: no platform keyboard to command.
    }
  }
}
