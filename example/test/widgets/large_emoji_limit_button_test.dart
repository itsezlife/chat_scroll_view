/// The desktop cap on enlarged emoji, as the user reaches it: a menu next to
/// the large-emoji toggle, shown only where the family has a cap.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/large_emoji_setting.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/large_emoji_limit_button.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LargeEmojiSetting setting;

  setUp(() async {
    setting = await LargeEmojiSetting.load(FakeKeyValueStore());
  });
  tearDown(() => setting.dispose());

  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void platformTest(
    String name,
    TargetPlatform platform,
    Future<void> Function(WidgetTester) body,
  ) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: LargeEmojiLimitButton(setting: setting)),
    ),
  );

  platformTest('is shown on desktop, saying the cap', TargetPlatform.macOS, (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(PopupMenuButton<int>), findsOneWidget);
    expect(
      find.byTooltip('Large emoji: up to 3 regular emoji'),
      findsOneWidget,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    platformTest(
      'is not shown where the family has no cap ($platform)',
      platform,
      (tester) async {
        await pump(tester);

        expect(find.byType(PopupMenuButton<int>), findsNothing);
      },
    );
  }

  platformTest(
    'choosing a step moves the cap and its tooltip',
    TargetPlatform.windows,
    (tester) async {
      await pump(tester);

      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.pumpAndSettle();

      expect(setting.desktopLimit.value, 10);
      expect(
        find.byTooltip('Large emoji: up to 10 regular emoji'),
        findsOneWidget,
      );
    },
  );

  platformTest(
    'offers every step of the setting and marks the current one',
    TargetPlatform.linux,
    (tester) async {
      await pump(tester);

      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();

      for (final step in LargeEmojiSetting.desktopLimitChoices) {
        expect(find.text('$step'), findsOneWidget, reason: 'step $step');
      }
      expect(
        tester
            .widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>))
            .initialValue,
        3,
      );
    },
  );
}
