import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts [child] bottom-anchored the way a chat screen does, inside every
/// scope the composer requires; [anchoredTop] pins it to the top instead, for
/// a test of what opens below it.
Widget composerHarness(
  Widget child, {
  Brightness brightness = Brightness.light,
  TextDirection textDirection = TextDirection.ltr,
  ChromeStrings? strings,
  EdgeInsets viewPadding = EdgeInsets.zero,
  ChromeMotionSpeed? motionSpeed,
  bool anchoredTop = false,
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
            child: ChromeMotionScope(
              speed: motionSpeed,
              child: GlassQualityScope(quality: GlassQuality.flat, child: app!),
            ),
          ),
        ),
      ),
    ),
    home: Scaffold(
      backgroundColor: palette.surfaceDim,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: anchoredTop ? 0 : null,
            bottom: anchoredTop ? null : 0,
            child: child,
          ),
        ],
      ),
    ),
  );
}

/// Types [text] into the composer's field as the platform keyboard does.
///
/// `WidgetTester.enterText` looks for Flutter's own `EditableText`, which the
/// composer's field is not (it is an `ExtendedEditableText`).
Future<void> enterFieldText(WidgetTester tester, String text) async {
  tester
      .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
      .requestKeyboard();
  await tester.pump();
  tester.testTextInput.enterText(text);
  await tester.pump();
}
