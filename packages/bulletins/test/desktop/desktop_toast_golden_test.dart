import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

// Regenerate with `scripts/goldens --update` (baselines are the CI runner's).
// Drawn with the test font (every glyph a square), so it checks the toast's
// geometry (width between 160 and 360, padding, the icon slot, the title
// line) and the toast colours; rounded corners are anti-aliased, hence the
// 1% pixel tolerance.
const _cell = Size(420, 120);

final _bulletins = <(String, Bulletin)>[
  ('plain', const Bulletin(message: 'Copied')),
  (
    'icon',
    const Bulletin(
      message: 'Link copied to clipboard',
      leading: BulletinLeading.icon(ChromeIconId.confirm),
    ),
  ),
  (
    'title_link',
    Bulletin(
      title: 'Favourites full',
      message: 'An older sticker was replaced. More',
      links: [BulletinLink(start: 31, end: 35, onTap: () {})],
    ),
  ),
  (
    'action',
    Bulletin(
      message: 'Premium sticker',
      action: BulletinAction.button(label: 'View', onPressed: () {}),
    ),
  ),
];

void main() {
  useGoldenBaselines(
    'test/desktop/desktop_toast_golden_test.dart',
    tolerance: 0.01,
  );

  for (final (name, bulletin) in _bulletins) {
    testWidgets('desktop toast: $name', (tester) async {
      tester.view
        ..physicalSize = _cell
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = BulletinController(
        policy: const BulletinPolicy.desktop(),
        clock: ManualBulletinClock(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: _cell),
            child: ChromeThemeScope(
              palette: const ChromePalette.light(),
              bulletin: BulletinTokens.referenceDesktop,
              child: ChromeStringsScope(
                strings: ChromeStringsPresets.english,
                child: ChromeMotionScope(
                  speed: ChromeMotionSpeed.instant,
                  child: ColoredBox(
                    color: const Color(0xFFFFFFFF),
                    child: BulletinHost(
                      controller: controller,
                      builders: DesktopBulletinBuilders.create(),
                      announce: (_, _) {},
                      child: const SizedBox.expand(),
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
        find.byType(BulletinHost),
        matchesGoldenFile('goldens/desktop_toast_$name.png'),
      );
    });
  }
}
