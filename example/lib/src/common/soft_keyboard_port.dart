import 'package:flutter/services.dart';
import 'package:keyboard_insets/keyboard_insets.dart';

/// What the host knows of the on-screen keyboard and can ask of it: the one
/// seam between the platform and the chat's input set.
///
/// The presentation package never touches a platform channel (ADR 031), so the
/// raw readings and the two commands live here, in the host.
abstract interface class SoftKeyboardPort {
  /// The keyboard's height as the system reports it, frame by frame while it
  /// moves; zero when it is hidden.
  Stream<double> get heights;

  /// Whether the system is moving the keyboard now. A height read while this
  /// is true is not a settled size.
  bool get isAnimating;

  /// The height of a keyboard that is up and at rest, or zero.
  double get restingHeight;

  /// Hides the on-screen keyboard, leaving focus where it is.
  Future<void> hide();

  /// Shows the on-screen keyboard for the focused field.
  Future<void> show();
}

/// The [SoftKeyboardPort] over the `keyboard_insets` plugin and the text-input
/// channel. Desktop and tests have no keyboard: readings stay zero and the
/// commands are no-ops.
final class PlatformSoftKeyboard implements SoftKeyboardPort {
  /// The platform keyboard.
  const PlatformSoftKeyboard();

  @override
  Stream<double> get heights => KeyboardInsets.insets;

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

  @override
  Future<void> show() => _invoke('TextInput.show');

  Future<void> _invoke(String method) async {
    try {
      await SystemChannels.textInput.invokeMethod<void>(method);
    } on MissingPluginException {
      // Desktop and tests: no platform keyboard to command.
    }
  }
}
