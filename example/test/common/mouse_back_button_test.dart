import 'dart:async';

import 'package:chat_scroll_view_example/src/common/mouse_back_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void backTest(
    String name,
    Future<void> Function(WidgetTester) body, {
    TargetPlatform platform = TargetPlatform.macOS,
  }) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  final navigator = GlobalKey<NavigatorState>();

  /// The app with a second page pushed over its first, [second] its body.
  Future<void> pumpTwoPages(WidgetTester tester, {Widget? second}) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MouseBackButton(child: child!),
        home: const Text('first'),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => second ?? const Text('second')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, int buttons) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await gesture.down(const Offset(10, 10));
    await gesture.up();
    // The navigation channel's handler was registered outside the test's
    // clock: a pushed message is handled on the real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  backTest('the back button pops the page', (tester) async {
    await pumpTwoPages(tester);
    await press(tester, kBackMouseButton);
    expect(find.text('second'), findsNothing);
    expect(find.text('first'), findsOneWidget);
  });

  backTest('a pop scope answers it first', (tester) async {
    var asked = 0;
    await pumpTwoPages(
      tester,
      second: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => asked++,
        child: const Text('second'),
      ),
    );
    await press(tester, kBackMouseButton);
    expect(asked, 1);
    expect(find.text('second'), findsOneWidget);
  });

  backTest('a primary click pops nothing', (tester) async {
    await pumpTwoPages(tester);
    await press(tester, kPrimaryMouseButton);
    expect(find.text('second'), findsOneWidget);
  });

  backTest('on Android the system handles it', (tester) async {
    await pumpTwoPages(tester);
    await press(tester, kBackMouseButton);
    expect(find.text('second'), findsOneWidget);
  }, platform: TargetPlatform.android);
}
