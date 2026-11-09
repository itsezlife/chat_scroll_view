/// The lab's `glass` switch: off, every glass of the app paints flat, so an
/// A/B run measures what the glass capture costs.
///
/// **Seam:** the switch named over `lab.SET`, and the glass policy the app's
/// scopes hand to chrome below them.
library;

import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/scroll_lab.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_services.dart';

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}

void main() {
  test('lab.SET names the glass switch "glass"', () {
    expect(ScrollLab.switchNamed('glass'), same(ScrollLab.glass));
  });

  test('lab.SET names the refraction switch "liquid"', () {
    expect(ScrollLab.switchNamed('liquid'), same(ScrollLab.liquid));
    expect(ScrollLab.liquid.value, isFalse);
  });

  testWidgets('liquid on lets the app glass refract', (tester) async {
    addTearDown(() => ScrollLab.liquid.value = false);
    final services = await _services(tester);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(GlassQualityScope.maybeOf(context)!.quality, GlassQuality.frosted);

    ScrollLab.liquid.value = true;
    await tester.pump();

    expect(
      GlassQualityScope.maybeOf(context)!.quality,
      GlassQuality.fullLiquid,
    );
  });

  testWidgets('glass off puts the app glass in lite mode', (tester) async {
    addTearDown(() => ScrollLab.glass.value = true);
    final services = await _services(tester);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(GlassQualityScope.maybeOf(context)!.liteMode, isFalse);

    ScrollLab.glass.value = false;
    await tester.pump();

    expect(GlassQualityScope.maybeOf(context)!.liteMode, isTrue);
  });
}
