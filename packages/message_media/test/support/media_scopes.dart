import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/message_media.dart';

/// What every message media test needs from its host: the chrome strings
/// and theme scopes the cells read, and the text a pure layout test
/// measures with.
abstract final class MediaScopes {
  /// The English media strings of the chrome presets.
  static final MediaStrings strings = ChromeStringsPresets.english.media;

  /// The text the layout measures with outside a widget: the framework's
  /// default style, no scaling, the English strings. Under a test font it
  /// measures as the cells' chrome typography paints.
  static final MediaLayoutText text = MediaLayoutText(
    style: const TextStyle(),
    scaler: TextScaler.noScaling,
    strings: strings,
  );

  /// [child] under the chrome [strings] (English by default) and a
  /// [palette] chrome theme.
  static Widget wrap(
    Widget child, {
    ChromeStrings? strings,
    ChromePalette palette = const ChromePalette.light(),
  }) => ChromeStringsScope(
    strings: strings ?? ChromeStringsPresets.english,
    child: ChromeThemeScope(palette: palette, child: child),
  );
}
