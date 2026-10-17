import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/simulated_input.dart';

const _smile = InlineContentRef(
  key: ContentKey.document('smile'),
  alternativeText: '\u{1F642}',
);

Future<TextSpan> _span(
  WidgetTester tester,
  ComposerTextController controller, {
  bool withComposing = false,
}) async {
  late TextSpan span;
  await tester.pumpWidget(
    Builder(
      builder: (context) {
        span = controller.buildTextSpan(
          context: context,
          style: const TextStyle(fontSize: 16),
          withComposing: withComposing,
        );
        return const SizedBox();
      },
    ),
  );
  return span;
}

List<TextSpan> _leaves(TextSpan span) => [
  for (final child in span.children!) child as TextSpan,
];

void main() {
  late ComposerTextController controller;

  tearDown(() => controller.dispose());

  testWidgets('plain text is one run', (tester) async {
    controller = ComposerTextController(initial: RichText('plain'));

    final span = await _span(tester, controller);

    expect(span.toPlainText(), 'plain');
  });

  testWidgets('styles split the text at the entity edges', (tester) async {
    controller = ComposerTextController(
      initial: RichText('a bold and italic b', const [
        Entity(2, 8, EntityKind.bold),
        Entity(7, 10, EntityKind.italic),
      ]),
    );

    final runs = _leaves(await _span(tester, controller));

    expect(
      [for (final run in runs) run.text],
      ['a ', 'bold ', 'and', ' italic', ' b'],
    );
    expect(runs[1].style!.fontWeight, FontWeight.bold);
    expect(runs[1].style!.fontStyle, isNull);
    expect(runs[2].style!.fontWeight, FontWeight.bold);
    expect(runs[2].style!.fontStyle, FontStyle.italic);
    expect(runs[3].style!.fontWeight, isNull);
    expect(runs[3].style!.fontStyle, FontStyle.italic);
  });

  testWidgets('underline and strike combine', (tester) async {
    controller = ComposerTextController(
      initial: RichText('both', const [
        Entity(0, 4, EntityKind.underline),
        Entity(0, 4, EntityKind.strike),
      ]),
    );

    final run = _leaves(await _span(tester, controller)).single;

    expect(
      run.style!.decoration,
      TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
    );
  });

  testWidgets('a code block reads as code', (tester) async {
    controller = ComposerTextController(
      initial: RichText('a()\nb()', const [
        Entity(0, 7, EntityKind.codeBlock(language: 'dart')),
      ]),
    );

    final run = _leaves(await _span(tester, controller)).single;

    expect(run.style!.fontFamily, 'monospace');
  });

  testWidgets('links and mentions take the host colours', (tester) async {
    const accent = Color(0xFF123456);
    controller = ComposerTextController(
      initial: RichText('link @al', const [
        Entity(0, 4, EntityKind$Link('https://example.com')),
        Entity(5, 3, EntityKind$Mention('al')),
      ]),
      entityStyles: const ComposerEntityStyles(link: accent, mention: accent),
    );

    final runs = _leaves(await _span(tester, controller));

    expect(runs[0].style!.color, accent);
    expect(runs[0].style!.decoration, TextDecoration.underline);
    expect(runs[2].style!.color, accent);
  });

  testWidgets('without host colours a link is still underlined', (
    tester,
  ) async {
    controller = ComposerTextController(
      initial: RichText('link', const [
        Entity(0, 4, EntityKind$Link('https://example.com')),
      ]),
    );

    final run = _leaves(await _span(tester, controller)).single;

    expect(run.style!.color, isNull);
    expect(run.style!.decoration, TextDecoration.underline);
  });

  testWidgets('inline content shows its alternative text by default', (
    tester,
  ) async {
    controller = ComposerTextController()
      ..insertText('a')
      ..insertContent(_smile);

    final span = await _span(tester, controller);

    expect(span.toPlainText(), 'a\u{1F642}');
  });

  testWidgets('inline content goes through the builder with its style', (
    tester,
  ) async {
    final seen = <(InlineContentRef, TextStyle)>[];
    controller = ComposerTextController(
      inlineContentBuilder: (context, reference, style) {
        seen.add((reference, style));
        return TextSpan(
          text: reference.alternativeText,
          style: style.copyWith(color: const Color(0xFF00FF00)),
        );
      },
    )..insertContent(_smile);
    controller.restore(
      RichText('\u{1F642}', [
        Entity(0, 2, EntityKind.inlineContent(_smile.key)),
        const Entity(0, 2, EntityKind.bold),
      ]),
    );

    await _span(tester, controller);

    expect(seen.single.$1, _smile);
    expect(seen.single.$2.fontWeight, FontWeight.bold);
  });

  testWidgets('a builder of the wrong length is a bug in debug mode', (
    tester,
  ) async {
    controller = ComposerTextController(
      inlineContentBuilder: (context, reference, style) =>
          const TextSpan(text: 'x'),
    )..insertContent(_smile);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          controller.buildTextSpan(
            context: context,
            style: const TextStyle(),
            withComposing: false,
          );
          return const SizedBox();
        },
      ),
    );

    expect(tester.takeException(), isA<AssertionError>());
  });

  testWidgets('the composing range is underlined', (tester) async {
    controller = ComposerTextController(initial: RichText('abc'))
      ..compose('abcd', const TextRange(start: 3, end: 4));

    final runs = _leaves(await _span(tester, controller, withComposing: true));

    expect([for (final run in runs) run.text], ['abc', 'd']);
    expect(runs[1].style!.decoration, TextDecoration.underline);
    expect(runs[0].style!.decoration, isNull);
  });
}
