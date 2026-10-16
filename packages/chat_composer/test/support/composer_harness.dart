import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';

/// Hosts [child] bottom-anchored the way a chat screen does, inside every
/// scope the composer requires.
Widget composerHarness(
  Widget child, {
  Brightness brightness = Brightness.light,
  TextDirection textDirection = TextDirection.ltr,
  ChromeStrings? strings,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) {
  final palette = ChromePalette.forBrightness(brightness);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, app) => Directionality(
      textDirection: textDirection,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewPadding: viewPadding),
        child: ChromeThemeScope(
          palette: palette,
          child: ChromeStringsScope(
            strings: strings ?? ChromeStringsPresets.english,
            child: GlassQualityScope(quality: GlassQuality.flat, child: app!),
          ),
        ),
      ),
    ),
    home: Scaffold(
      backgroundColor: palette.surfaceDim,
      body: Stack(
        children: [Positioned(left: 0, right: 0, bottom: 0, child: child)],
      ),
    ),
  );
}
