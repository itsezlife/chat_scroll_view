/// Goldens of the web's draft options menu at the strip: the touch style
/// (solid surface, 48 rows) in light and dark, and the mouse style (menu
/// glass, compact rows) in light.
///
/// Regenerate with `scripts/goldens --update` (baselines are the CI
/// runner's). The harness draws glass on its flat path, so the images check
/// layout, placement and colours.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
const _photo = ContentDescriptor(key: ContentKey.external('p'));

void main() {
  useGoldenBaselines(
    'test/draft_options/draft_options_web_menu_golden_test.dart',
    tolerance: 0.01,
  );

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    ChromeInputClass inputClass = ChromeInputClass.touch,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(480, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = DraftOptionsWebMenuController(
      policy: const DraftOptionsPolicy$Web(),
      host: RecordingDraftOptionsHost(),
      input: () => DraftOptionsInput(
        value: DraftLinkPart(options: LinkPreviewOptions(url: _url)),
        page: LinkPreviewState.loaded(
          LinkPreview(url: _url, title: 'A story', photo: _photo),
        ),
        text: const model.RichText.plain('Read this'),
        links: [_url],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      composerHarness(
        brightness: brightness,
        ChromeInputClassScope(
          initial: inputClass,
          child: Builder(
            builder: (context) => ComposerHeaderStrip(
              header: ComposerHeader.linkPreview(
                url: _url,
                page: LinkPreview(url: _url, title: 'A story'),
                onOpen: (rect) => controller.open(context, rect),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byType(ComposerHeaderStrip),
      kind: switch (inputClass) {
        ChromeInputClass.touch => PointerDeviceKind.touch,
        ChromeInputClass.mouse => PointerDeviceKind.mouse,
      },
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/draft_options_web_menu_$name.png'),
    );
  }

  testWidgets('touch, light', (tester) async {
    await shoot(tester, 'touch_light');
  });

  testWidgets('touch, dark', (tester) async {
    await shoot(tester, 'touch_dark', brightness: Brightness.dark);
  });

  testWidgets('mouse, light', (tester) async {
    await shoot(tester, 'mouse_light', inputClass: ChromeInputClass.mouse);
  });
}
