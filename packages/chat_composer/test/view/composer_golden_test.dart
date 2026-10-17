import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/material_icons.dart';
import '../support/tolerant_golden_comparator.dart';

// Regenerate with `flutter test --update-goldens test/view`. The goldens use
// the flat glass path (fill, strokes, shadow) on the pinned platform (macOS)
// and the test font, so they check layout, mirroring and colours; rounded
// anti-aliased edges get a 1% pixel tolerance. The sampled and filtered glass
// paths depend on the device and are covered by the device checklist.
const _tolerance = 0.01;
const _restricted = ComposerPanelId('restricted');

// One image per state: light and dark in columns, left-to-right and
// right-to-left in rows.
class _Variants extends StatelessWidget {
  const _Variants(this.makeSpec);

  final ComposerSpec Function() makeSpec;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final direction in TextDirection.values)
        Expanded(
          child: Row(
            children: [
              for (final brightness in Brightness.values)
                Expanded(
                  child: _Cell(
                    brightness: brightness,
                    direction: direction,
                    spec: makeSpec(),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

class _Cell extends StatefulWidget {
  const _Cell({
    required this.brightness,
    required this.direction,
    required this.spec,
  });

  final Brightness brightness;
  final TextDirection direction;
  final ComposerSpec spec;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  final controller = ComposerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChromePalette.forBrightness(widget.brightness);
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
                  spec: widget.spec,
                  safeAreaBottom: 0,
                  panelResolver: (context, panel) => Center(
                    child: Text(
                      'Join channel',
                      style: TextStyle(
                        color: ChromeThemeScope.composerOf(context).text,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<ActionDescriptor> _actions({bool hasText = false}) => [
  ActionDescriptor(
    id: 'panel',
    icon: ChromeIconId.emoji,
    semanticLabel: 'Show emoji panel',
    placement: ActionPlacement.leading,
    onTap: () {},
  ),
  ActionDescriptor(
    id: 'attach',
    icon: ChromeIconId.attach,
    semanticLabel: 'Attach',
    onTap: () {},
  ),
  ActionDescriptor(
    id: 'primary',
    icon: hasText ? ChromeIconId.send : ChromeIconId.voice,
    semanticLabel: hasText ? 'Send' : 'Record voice message',
    primary: hasText,
    onTap: () {},
  ),
];

void main() {
  setUpAll(() async {
    await loadMaterialIcons();
    // Goldens sit next to this file, also when test/unit_test.dart runs it.
    goldenFileComparator = TolerantGoldenComparator(
      Uri.file('test/view/composer_golden_test.dart'),
      tolerance: _tolerance,
    );
  });

  final states = <String, ComposerSpec Function()>{
    'idle': () => ComposerSpec(actions: _actions()),
    'reply': () => ComposerSpec(
      header: ComposerHeader.reply(
        name: 'Ada',
        preview: 'See you at noon',
        onDismiss: () {},
      ),
      actions: _actions(hasText: true),
    ),
    'edit': () => ComposerSpec(
      header: ComposerHeader.edit(preview: 'See you at noon', onDismiss: () {}),
      actions: _actions(hasText: true),
    ),
    'restricted': () => ComposerSpec(panel: _restricted),
  };

  for (final MapEntry(key: name, value: spec) in states.entries) {
    testWidgets('$name island, light and dark, LTR and RTL', (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: const ValueKey('golden'),
            child: _Variants(spec),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('../goldens/composer_$name.png'),
      );
    });
  }
}
