/// Goldens of the Android bulletin card: the opaque card with an icon, the
/// glass card over a chat backdrop with the countdown and Undo, and the
/// two-line card with a sticker thumbnail and a button.
///
/// Drawn with the test font (every glyph a square): they check geometry and
/// the token colours. Rounded corners and the blurred glass are
/// anti-aliased, hence the 1% pixel tolerance. Regenerate with
/// `scripts/goldens --update` (baselines are the CI runner's).
library;

import 'package:bulletins/bulletins.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

import 'android_harness.dart';

/// Stripes the glass blurs, standing in for a chat.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < 20; i++)
        Expanded(
          child: ColoredBox(
            color: i.isEven ? const Color(0xFF6FA8DC) : const Color(0xFFF6B26B),
          ),
        ),
    ],
  );
}

void main() {
  useGoldenBaselines(
    'test/android/bulletin_android_golden_test.dart',
    tolerance: 0.01,
  );

  late AndroidHarness h;

  tearDown(() => h.dispose());

  Future<void> expectScene(
    WidgetTester tester,
    String name,
    Bulletin bulletin, {
    bool glass = false,
  }) async {
    h = AndroidHarness(
      surface: const Size(400, 200),
      obstruction: const EdgeInsets.only(bottom: 40),
    );
    await tester.pumpWidget(
      h.app(
        background: const _Backdrop(),
        builders: BulletinBuilders$Android.create(
          glass: glass,
          thumbnail: (context, source, view) => const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFE06666),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
    h.controller.show(bulletin);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(BulletinHost),
      matchesGoldenFile('../goldens/bulletin_android_$name.png'),
    );
    h.controller.dismiss();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the opaque card with an icon', (tester) async {
    await expectScene(
      tester,
      'icon',
      const Bulletin(
        message: 'Link copied',
        leading: BulletinLeading.icon(ChromeIconId.confirm),
      ),
    );
  });

  testWidgets('the glass card with the countdown and Undo', (tester) async {
    await expectScene(
      tester,
      'glass_undo',
      Bulletin(
        message: 'Stickers removed',
        leading: const BulletinLeading.countdown(),
        action: BulletinAction.undo(onUndo: () {}),
      ),
      glass: true,
    );
  });

  testWidgets('the two-line card with a thumbnail and a button', (
    tester,
  ) async {
    await expectScene(
      tester,
      'thumbnail_button',
      Bulletin(
        title: 'Added to favourites',
        message: 'The sticker replaced the oldest one in favourites',
        leading: const BulletinLeading.thumbnail('sticker'),
        action: BulletinAction.button(label: 'View', onPressed: () {}),
      ),
    );
  });
}
