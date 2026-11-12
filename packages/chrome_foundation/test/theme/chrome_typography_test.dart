/// The chrome's text face.
///
/// **Seam:** [ChromeTypography.of] under a host theme and an ambient
/// default text style; observed through the style it returns.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<TextStyle> styleUnder(
    WidgetTester tester, {
    required Widget Function(Widget child) host,
  }) async {
    late TextStyle style;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            style = ChromeTypography.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return style;
  }

  testWidgets("is the host theme's body face, whatever the ambient style", (
    tester,
  ) async {
    final style = await styleUnder(
      tester,
      host: (child) => Theme(
        data: ThemeData(
          textTheme: const TextTheme(
            bodyMedium: TextStyle(
              fontFamily: 'HostFont',
              fontFamilyFallback: ['HostFallback'],
              fontSize: 15,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.25,
              height: 1.43,
            ),
          ),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 48,
            fontWeight: FontWeight.w900,
            decoration: TextDecoration.underline,
          ),
          child: child,
        ),
      ),
    );

    expect(style.inherit, isFalse);
    expect(style.fontFamily, 'HostFont');
    expect(style.fontFamilyFallback, ['HostFallback']);
    expect(style.fontSize, 15);
    // Each text sets its own weight and keeps the platform's spacing.
    expect(style.fontWeight, FontWeight.normal);
    expect(style.letterSpacing, isNull);
    expect(style.height, isNull);
    expect(style.decoration, TextDecoration.none);
  });

  testWidgets('without a host theme is the fallback theme', (tester) async {
    final style = await styleUnder(tester, host: (child) => child);

    expect(
      style.fontFamily,
      ThemeData.fallback().textTheme.bodyMedium?.fontFamily,
    );
    expect(style.fontSize, 14);
  });
}
