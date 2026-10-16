import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';

/// The ancestors a shell needs, for tests and goldens: reading direction,
/// a phone-sized `MediaQuery`, the default key bindings and actions of an
/// app, and the chrome theme, strings and motion.
///
/// Not a host: a real host supplies its own scopes. Defaults are LTR, light
/// palette, the English preset and normal motion speed.
class PanelShellTestScope extends StatelessWidget {
  /// Wraps [child] in the scopes a shell requires.
  const PanelShellTestScope({
    required this.child,
    this.textDirection = TextDirection.ltr,
    this.brightness = Brightness.light,
    this.strings,
    this.speed = ChromeMotionSpeed.normal,
    this.size = const Size(400, 600),
    super.key,
  });

  /// The subtree under test.
  final Widget child;

  /// Reading direction.
  final TextDirection textDirection;

  /// Which palette to derive the theme from.
  final Brightness brightness;

  /// Strings in scope; defaults to `ChromeStringsPresets.english`.
  final ChromeStrings? strings;

  /// Motion speed in scope.
  final ChromeMotionSpeed speed;

  /// The media size.
  final Size size;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: textDirection,
    child: MediaQuery(
      data: MediaQueryData(size: size),
      // What a WidgetsApp provides below the app: the default key bindings
      // and actions, so Tab moves focus and Enter activates.
      child: Shortcuts(
        shortcuts: WidgetsApp.defaultShortcuts,
        child: Actions(
          actions: WidgetsApp.defaultActions,
          // An app's route autofocuses its scope; without one, key events
          // have no focus path to travel along.
          child: Focus(
            autofocus: true,
            child: ChromeThemeScope(
              palette: ChromePalette.forBrightness(brightness),
              child: ChromeStringsScope(
                strings: strings ?? ChromeStringsPresets.english,
                child: ChromeMotionScope(speed: speed, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
