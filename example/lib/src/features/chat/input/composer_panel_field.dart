import 'package:chat_composer/chat_composer.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// A composer as the field a keyboard-replacing panel stands in for.
final class ComposerPanelField implements KeyboardPanelField {
  /// The field of [composer].
  const ComposerPanelField(this.composer);

  /// The composer whose keyboard the panel replaces.
  final ComposerController composer;

  @override
  bool get hasFocus => composer.hasFocus;

  @override
  void holdKeyboardBack({required bool held}) => composer.setSoftKeyboard(
    held ? SoftKeyboardMode.suppressed : SoftKeyboardMode.auto,
  );

  @override
  void requestKeyboard() => composer.requestKeyboard();
}
