/// The desktop draft options box over its scrim, light and dark: the title,
/// the live preview (the fake bubble), the rows, the link hint and Cancel /
/// Save.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

import '../support/composer_harness.dart';
import '../support/material_icons.dart';

// Regenerate with `scripts/goldens --update` (baselines are the CI runner's).
const _tolerance = 0.002;

final _url = Uri.parse('https://news.example/story?id=7');
final _other = Uri.parse('https://docs.example/guide');

void main() {
  useGoldenBaselines(
    'test/draft_options/draft_options_desktop_golden_test.dart',
    tolerance: _tolerance,
  );
  setUpAll(() async {
    await loadMaterialIcons();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'the desktop box, ${brightness.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(480, 560));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = DraftOptionsController(
          policy: const DraftOptionsPolicy$Desktop(),
          host: RecordingDraftOptionsHost(),
          bubbleBuilder: FakeDraftBubbleBuilder().call,
        );
        addTearDown(controller.dispose);
        late BuildContext context;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('golden'),
            child: composerHarness(
              Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox(height: 40);
                },
              ),
              brightness: brightness,
              motionSpeed: ChromeMotionSpeed.instant,
            ),
          ),
        );
        controller.open(
          context,
          value: DraftLinkPart(options: LinkPreviewOptions(url: _url)),
          page: LinkPreviewState.loaded(
            LinkPreview(url: _url, siteName: 'Example News', title: 'A story'),
          ),
          text: const model.RichText.plain('Read this and that'),
          links: [_url, _other],
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(const ValueKey('golden')),
          matchesGoldenFile(
            '../goldens/draft_options_desktop_${brightness.name}.png',
          ),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
