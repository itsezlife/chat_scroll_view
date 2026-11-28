/// Goldens of the draft options overlay's iOS presentation, open and at
/// rest: the rounded content rect with the preview and the action list
/// right-aligned under it, over the iOS scrim, by day and at night, and the
/// iPad form centred on the strip.
///
/// Drawn with the test font (every glyph a square): they check geometry,
/// the corner radii and the token colours. Rounded edges are anti-aliased,
/// hence the 1 % pixel tolerance. Regenerate with `scripts/goldens --update`
/// (baselines are the CI runner's).
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

import '../support/composer_harness.dart';

const _tolerance = 0.01;

final _url = Uri.parse('https://news.example/story?id=7');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));

// A bubble at the end of a previewing chat, in the chrome's colours, so the
// content's frame reads against it.
Widget _bubble(BuildContext context, DraftOptionsPreview preview) {
  final palette = ChromeThemeScope.of(context).palette;
  return Padding(
    padding: const EdgeInsets.all(8),
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        width: 240,
        height: 140,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.surfaceSelected,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          preview.part.options.url.host,
          style: ChromeTypography.of(
            context,
          ).copyWith(color: palette.onSurface),
        ),
      ),
    ),
  );
}

void main() {
  useGoldenBaselines(
    'test/draft_options/draft_options_ios_golden_test.dart',
    tolerance: _tolerance,
  );

  Future<void> shoot(
    WidgetTester tester, {
    required String name,
    required DraftOptionsOverlayPolicy policy,
    required Size window,
    required Rect strip,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = DraftOptionsController(
      policy: policy,
      host: RecordingDraftOptionsHost(),
      bubbleBuilder: _bubble,
      clock: ManualComposerClock(DateTime(2026, 11, 28)),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      composerHarness(
        brightness: brightness,
        viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => controller.open(
              context,
              value: _initial,
              page: LinkPreviewState.pending,
              stripRect: strip,
            ),
            child: const SizedBox(height: 40),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/draft_options_ios_$name.png'),
    );
  }

  testWidgets('phone, light', (tester) async {
    await shoot(
      tester,
      name: 'phone_light',
      policy: const DraftOptionsPolicy$IOS(),
      window: const Size(390, 844),
      strip: const Rect.fromLTWH(0, 760, 390, 44),
    );
  });

  testWidgets('phone, dark', (tester) async {
    await shoot(
      tester,
      name: 'phone_dark',
      policy: const DraftOptionsPolicy$IOS(),
      window: const Size(390, 844),
      strip: const Rect.fromLTWH(0, 760, 390, 44),
      brightness: Brightness.dark,
    );
  });

  testWidgets('iPad, light', (tester) async {
    await shoot(
      tester,
      name: 'ipad_light',
      policy: const DraftOptionsPolicy$IOS(iPad: true),
      window: const Size(1024, 768),
      strip: const Rect.fromLTWH(600, 690, 300, 44),
    );
  });
}
