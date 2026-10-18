import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/material_icons.dart';
import '../support/tolerant_golden_comparator.dart';

// Regenerate with `flutter test --update-goldens test/view`; see
// composer_golden_test.dart for what the goldens pin.
const _tolerance = 0.01;

const _bullet = EntityListKind.bullet;
const _ordered = EntityListKind.ordered;

EntityKind _item(EntityListKind kind, int depth) =>
    EntityKind.list(listKind: kind, depth: depth);

// Bullets at depths 0 to 2 and a plain line under them.
RichText _bullets() => RichText('Fruit\nApple\nGreen\nPlain line', [
  Entity(0, 5, _item(_bullet, 0)),
  Entity(6, 5, _item(_bullet, 1)),
  Entity(12, 5, _item(_bullet, 2)),
]);

// Numbers at depths 0 to 2: a nested run restarts and the outer one goes on.
RichText _numbers() => RichText('First\nSecond\nNested\nDeeper\nThird', [
  Entity(0, 5, _item(_ordered, 0)),
  Entity(6, 6, _item(_ordered, 0)),
  Entity(13, 6, _item(_ordered, 1)),
  Entity(20, 6, _item(_ordered, 2)),
  Entity(27, 5, _item(_ordered, 0)),
]);

class _Cell extends StatefulWidget {
  const _Cell({required this.direction, required this.text});

  final TextDirection direction;
  final RichText text;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  late final controller = ComposerController(
    text: ComposerTextController(initial: widget.text, lists: true),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChromePalette.forBrightness(Brightness.light);
    return Directionality(
      textDirection: widget.direction,
      child: ChromeThemeScope(
        palette: palette,
        child: ChromeStringsScope(
          strings: ChromeStringsPresets.english,
          child: GlassQualityScope(
            quality: GlassQuality.flat,
            child: ColoredBox(
              color: palette.surfaceDim,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ComposerView(
                  controller: controller,
                  spec: ComposerSpec(),
                  safeAreaBottom: 0,
                  autofocus: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await loadMaterialIcons();
    goldenFileComparator = TolerantGoldenComparator(
      Uri.file('test/view/composer_list_gutter_golden_test.dart'),
      tolerance: _tolerance,
    );
  });

  testWidgets('bullets and numbers at depths 0 to 2, LTR and RTL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: const ValueKey('golden'),
          child: Column(
            children: [
              for (final direction in TextDirection.values)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Cell(direction: direction, text: _bullets()),
                      ),
                      Expanded(
                        child: _Cell(direction: direction, text: _numbers()),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('../goldens/composer_list_gutter.png'),
    );
  });
}
