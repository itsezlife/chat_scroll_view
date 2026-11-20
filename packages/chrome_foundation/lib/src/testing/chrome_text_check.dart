import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails when any text laid out (under [within], or anywhere) takes the
/// framework's fallback style: the debug style an app puts above its
/// navigator (a monospace face, a yellow double underline), which text
/// shows when a route, overlay or popup has no text root, or a style is
/// built without the chrome face.
void expectChromeText(WidgetTester tester, {Finder? within}) {
  final texts = within == null
      ? find.byType(RichText)
      : find.descendant(of: within, matching: find.byType(RichText));
  final found = texts.evaluate().toList();
  expect(found, isNotEmpty, reason: 'no text to check');
  for (final element in found) {
    final text = (element.widget as RichText).text;
    text.visitChildren((span) {
      if (span case TextSpan(:final style?)) {
        final plain = span.toPlainText();
        expect(
          style.decoration,
          isNot(TextDecoration.underline),
          reason: '"$plain" is underlined (the fallback style)',
        );
        expect(
          style.decorationColor,
          isNot(const Color(0xFFFFFF00)),
          reason: '"$plain" has the fallback underline colour',
        );
        expect(
          style.fontFamily,
          isNot('monospace'),
          reason: '"$plain" is in the fallback monospace face',
        );
      }
      return true;
    });
    expect(
      text.style,
      isNotNull,
      reason: '"${text.toPlainText()}" has no style at its root',
    );
  }
}
