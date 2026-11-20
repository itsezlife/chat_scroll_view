/// The app's chrome puts a text root above the navigator: a route a package
/// pushes without one of its own reads the chrome face, not the framework's
/// underlined debug style.
///
/// **Seam:** [AppChrome] as the app's builder, a bare route pushed over it,
/// read with `expectChromeText`.
library;

import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_services.dart';

void main() {
  testWidgets('a bare route over the app reads the chrome face', (
    tester,
  ) async {
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: const SizedBox.expand(),
      ),
    );
    navigator.currentState!
        .push(
          PageRouteBuilder<void>(
            opaque: false,
            pageBuilder: (context, _, _) =>
                const Center(child: Text('a popup', key: ValueKey('popup'))),
          ),
        )
        .ignore();
    await tester.pumpAndSettle();

    expectChromeText(tester, within: find.byKey(const ValueKey('popup')));
  });
}
