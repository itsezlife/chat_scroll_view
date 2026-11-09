import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// What a surface placed in an `Overlay` takes with it from the page that
/// opened it.
///
/// An overlay entry is built under the overlay, not under the page, so the
/// scopes the page was given do not reach it. Capturing them where the surface
/// is opened and wrapping the entry's content with them is how the picker
/// draws in the same theme, language, motion and reading direction as the
/// grid it came from.
///
/// An overlay is above the host's `Material`, so its inherited text style is
/// the framework's debug one; the entry's text is given the chrome face
/// ([ChromeTypography]) in the palette's `onSurface` instead.
final class ChromeOverlayScopes {
  /// Reads the scopes visible from [context].
  ChromeOverlayScopes.capture(BuildContext context)
    : _direction = Directionality.of(context),
      _theme = ChromeThemeScope.of(context),
      _strings = ChromeStringsScope.of(context),
      _motion = ChromeMotionScope.of(context),
      _text = ChromeTypography.of(context);

  final TextDirection _direction;
  final ChromeThemeData _theme;
  final ChromeStrings _strings;
  final ChromeMotionData _motion;
  final TextStyle _text;

  /// The motion a captured surface plays at, speed included.
  ChromeMotionData get motion => _motion;

  /// [child] under the captured scopes.
  Widget wrap(Widget child) => Directionality(
    textDirection: _direction,
    child: ChromeThemeScope.data(
      data: _theme,
      child: ChromeStringsScope(
        strings: _strings,
        child: ChromeMotionScope(
          motion: _motion.motion,
          speed: _motion.speed,
          child: DefaultTextStyle(
            style: _text.copyWith(color: _theme.palette.onSurface),
            child: child,
          ),
        ),
      ),
    ),
  );
}
