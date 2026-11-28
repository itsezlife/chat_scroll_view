/// Goldens of the Android draft options overlay, open and settled, in the
/// light and the dark theme: the card with its header and the preview, the
/// glass menu with the link page's rows under it, over the Android scrim.
///
/// Drawn with the test font (every glyph a square); the rounded card and
/// the shadow are anti-aliased, hence the 1% pixel tolerance. Regenerate
/// with `scripts/goldens --update` (baselines are the CI runner's).
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');

void main() {
  useGoldenBaselines(
    'test/draft_options/draft_options_card_golden_test.dart',
    tolerance: 0.01,
  );

  for (final brightness in Brightness.values) {
    testWidgets('the open Android overlay, ${brightness.name}', (tester) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = DraftOptionsController(
        policy: const DraftOptionsPolicy.android(),
        host: RecordingDraftOptionsHost(),
        bubbleBuilder: FakeDraftBubbleBuilder().call,
        clock: ManualComposerClock(DateTime(2026, 11, 28)),
      );
      addTearDown(controller.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        composerHarness(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox(height: 48);
            },
          ),
          brightness: brightness,
        ),
      );
      controller.open(
        context,
        value: DraftLinkPart(options: LinkPreviewOptions(url: _url)),
        page: LinkPreviewState.loaded(
          LinkPreview(url: _url, siteName: 'Example News', title: 'A story'),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../goldens/draft_options_card_android_${brightness.name}.png',
        ),
      );
    });
  }
}
