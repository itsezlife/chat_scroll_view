import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

// Regenerate with `scripts/goldens --update` (baselines are the CI runner's).
// Each preset all the way up, in a light and a dark theme, over a striped
// window with a surface on top. The still is the CPU stack blur, the same on
// every backend, so the images need no tolerance beyond a little for the
// stretched still's sampling.
const _tolerance = 0.01;

class _Stripes extends StatelessWidget {
  const _Stripes();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: ColoredBox(color: Color(0xFFE53935))),
      Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
      Expanded(child: ColoredBox(color: Color(0xFF1E88E5))),
    ],
  );
}

void main() {
  useGoldenBaselines(
    'test/backdrop/chrome_scrim_golden_test.dart',
    tolerance: _tolerance,
  );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view
      ..physicalSize = const Size(300, 200)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  const presets = [
    ChromeScrimPreset.android,
    ChromeScrimPreset.ios,
    ChromeScrimPreset.ipad,
    ChromeScrimPreset.desktop,
    ChromeScrimPreset.web,
    ChromeScrimPreset.contentPreview,
  ];
  const palettes = {
    'light': ChromePalette.light(),
    'dark': ChromePalette.dark(),
  };
  for (final preset in presets) {
    for (final MapEntry(key: theme, value: palette) in palettes.entries) {
      testWidgets('${preset.name} scrim, $theme', (tester) async {
        late BuildContext context;
        ChromeScrimController? scrim;
        late StateSetter setState;
        await tester.pumpWidget(
          ChromeThemeScope(
            palette: palette,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: const ValueKey('window'),
                child: BackdropSnapshotSource(
                  child: StatefulBuilder(
                    builder: (c, set) {
                      context = c;
                      setState = set;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          const _Stripes(),
                          if (scrim case final scrim?)
                            ChromeScrim(
                              controller: scrim,
                              child: const Center(
                                child: SizedBox(
                                  width: 80,
                                  height: 48,
                                  child: ColoredBox(color: Color(0xFF43A047)),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        final opened = ChromeScrimController(context, preset: preset);
        addTearDown(opened.cancel);
        setState(() => scrim = opened);
        await tester.pump();
        if (opened.still case final still?) {
          var done = false;
          unawaited(still.ready.then((_) => done = true));
          for (var turn = 0; !done && turn < 200; turn++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
        }
        await tester.pump(const Duration(seconds: 1));
        await expectLater(
          find.byKey(const ValueKey('window')),
          matchesGoldenFile('../goldens/scrim_${preset.name}_$theme.png'),
        );
      });
    }
  }
}
