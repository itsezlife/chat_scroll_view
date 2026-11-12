import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

/// The face the chrome draws its text in: the host's body face.
///
/// Typography is not a token group: the face is the host's, named once in its
/// Material text theme (`bodyMedium`), and each chrome text sets the size and
/// weight it needs. Chrome text reads the face from here rather
/// than inheriting a `DefaultTextStyle`, because chrome often draws where no
/// `Material` is above it: in an overlay entry, a popup route, or a page the
/// host builds outside its scaffold. There the inherited style is the
/// framework's debug style (a monospace face, 48 px, weight 900, underlined),
/// not the host's.
abstract final class ChromeTypography {
  /// The base style of chrome text under [context]: the family, fallback and
  /// size of the host theme's body text, at the regular weight, undecorated.
  ///
  /// Not inheriting ([TextStyle.inherit] false), so nothing of an ambient
  /// style leaks in. The theme's letter spacing and line height are left out:
  /// the platform's own spacing is used.
  static TextStyle of(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    return TextStyle(
      inherit: false,
      fontFamily: body?.fontFamily,
      fontFamilyFallback: body?.fontFamilyFallback,
      fontSize: body?.fontSize ?? defaultFontSize,
      fontWeight: FontWeight.normal,
      decoration: TextDecoration.none,
    );
  }

  /// The size when the host's body text names none: the framework's.
  static const double defaultFontSize = 14;
}
