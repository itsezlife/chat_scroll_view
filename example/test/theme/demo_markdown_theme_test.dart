import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_markdown_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('demoDarkMarkdownTheme link underline', () {
    testWidgets('underlines links on Android', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final theme = demoDarkMarkdownTheme(
          tester.element(find.byType(SizedBox)),
        );
        expect(
          theme.textStyleFor(MD$Style.link).decoration,
          TextDecoration.underline,
        );
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('does not underline links on macOS', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final theme = demoDarkMarkdownTheme(
          tester.element(find.byType(SizedBox)),
        );
        expect(
          theme.textStyleFor(MD$Style.link).decoration,
          isNot(TextDecoration.underline),
        );
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });
  });
}
