import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

// Regenerate with `scripts/goldens --update` (baselines are the CI runner's).
// The card sits over stripes so the blur shows; the test font draws the text,
// so the scenes check layout, colours and the blur, not the glyphs. Rounded
// anti-aliased edges and the blur get a 1% pixel tolerance.
const _tolerance = 0.01;
const _surface = Size(390, 220);

class _Stripes extends StatelessWidget {
  const _Stripes();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < 11; i++)
        Expanded(
          child: ColoredBox(
            color: i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFF3A7BD5),
          ),
        ),
    ],
  );
}

void main() {
  useGoldenBaselines(
    'test/ios/bulletin_ios_golden_test.dart',
    tolerance: _tolerance,
  );

  final scenes = <String, Bulletin>{
    'plain': const Bulletin(
      message: 'Link copied to clipboard',
      leading: BulletinLeading.icon(ChromeIconId.send),
    ),
    'undo_countdown': Bulletin(
      title: 'Pack removed',
      message: 'The pack is no longer in your stickers.',
      leading: const BulletinLeading.countdown(),
      action: BulletinAction.undo(onUndo: () {}),
    ),
    'thumbnail_multiline': Bulletin(
      message: List.filled(14, 'sticker').join(' '),
      leading: const BulletinLeading.thumbnail('sticker'),
      action: BulletinAction.button(label: 'View', onPressed: () {}),
    ),
  };

  for (final MapEntry(key: name, value: bulletin) in scenes.entries) {
    testWidgets('ios $name', (tester) async {
      final controller = BulletinController(
        policy: const BulletinPolicy.ios(),
        clock: ManualBulletinClock(),
      );
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(_surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: _surface),
            child: ChromeThemeScope(
              palette: const ChromePalette.light(),
              child: ChromeStringsScope(
                strings: ChromeStringsPresets.english,
                child: ChromeMotionScope(
                  speed: ChromeMotionSpeed.instant,
                  child: RepaintBoundary(
                    key: const ValueKey('golden'),
                    child: BulletinHost(
                      controller: controller,
                      builders: BulletinIOS.builders(
                        thumbnail: (_, _, _) =>
                            const ColoredBox(color: Color(0xFFFFB300)),
                      ),
                      announce: (_, _) {},
                      child: const _Stripes(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      controller.show(bulletin);
      await tester.pump();
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('../goldens/ios_$name.png'),
      );
    });
  }
}
