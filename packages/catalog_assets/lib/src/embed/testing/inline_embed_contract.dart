import 'dart:ui';

import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contract every [InlineEmbed] meets; see its documentation.
///
/// [create] builds a fresh, live embed for each test.
void runInlineEmbedContract(InlineEmbed Function() create) {
  group('InlineEmbed contract', () {
    late InlineEmbed embed;
    final canvas = Canvas(PictureRecorder());
    const rect = Rect.fromLTWH(0, 0, 10, 10);
    const paintContext = InlineEmbedPaintContext();

    setUp(() => embed = create());
    tearDown(() => embed.dispose());

    test('reserves a positive size', () {
      expect(embed.sizeHint.width, greaterThan(0));
      expect(embed.sizeHint.height, greaterThan(0));
    });

    test('is visible on creation', () {
      expect(embed.visible, isTrue);
    });

    test('remembers whether it is visible', () {
      embed.visible = false;

      expect(embed.visible, isFalse);
    });

    test('paints without throwing, also with a rectangle of another size', () {
      embed.paint(canvas, rect, paintContext);
      embed.paint(canvas, const Rect.fromLTWH(3, 3, 40, 40), paintContext);
    });

    test('disposes more than once without throwing', () {
      embed
        ..dispose()
        ..dispose();
    });

    test('paints nothing and signals nothing after dispose', () {
      embed.dispose();

      embed.paint(canvas, rect, paintContext);
      embed.addListener(() => fail('signalled after dispose'));
    });

    test('ignores removing a listener it never had', () {
      embed.removeListener(() {});
    });
  });
}
