/// Opt-in test and demo support for `chrome_foundation`: English and Russian
/// [ChromeStrings] presets and a snapshot helper for completeness checks.
///
/// Production code never imports this library; the packages ship no
/// translation, so a host fills `ChromeStrings` from its own localisation.
library;

export 'src/testing/chrome_strings_presets.dart';
export 'src/testing/chrome_strings_snapshot.dart';
