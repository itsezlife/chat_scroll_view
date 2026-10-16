/// The strip's pictures as chrome icons.
///
/// **Seam:** [EmojiTabIconScope] over the chrome icon scope, observed through
/// the registry a [ChromeIcon] below it resolves and through what it paints.
library;

import 'dart:ui' as ui;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

void main() {
  const smileys = ChromeIconId('emoji.smileys');

  Widget host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: EmojiTabIconScope(child: child),
  );

  late ChromeIconRegistry seen;

  Widget probe() => Builder(
    builder: (context) {
      seen = ChromeIconScope.of(context);
      return const SizedBox();
    },
  );

  test('names a picture for each category tab, and nothing else', () {
    expect(EmojiTabIcons.assets.keys, [
      for (final tab in EmojiCategories.tabs) tab.icon,
    ]);
    expect(
      EmojiTabIcons.assetKeyOf(smileys),
      'packages/panel_pages/assets/emoji_tabs/msg_emoji_smiles.webp',
    );
    expect(EmojiTabIcons.assetKeyOf(ChromeIconId.search), isNull);
  });

  testWidgets('every picture is bundled and decodes', (tester) async {
    await tester.runAsync(() async {
      for (final id in EmojiTabIcons.assets.keys) {
        final image = await EmojiTabIcons.imageFor(
          EmojiTabIcons.assetKeyOf(id)!,
        );
        expect(image.width, greaterThan(0), reason: '$id');
      }
    });
  });

  testWidgets('shows the fallback until a picture arrives, then paints it', (
    tester,
  ) async {
    await tester.pumpWidget(host(probe()));
    expect(seen.contains(smileys), isFalse);

    await tester.runAsync(() async {
      await EmojiTabIcons.imageFor(EmojiTabIcons.assetKeyOf(smileys)!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(seen.contains(smileys), isTrue);
    expect(seen.painterFor(smileys), isA<ChromeIconPainter$Paint>());
  });

  testWidgets('a loader of its own is decoded per scope and released with it', (
    tester,
  ) async {
    final asked = <String>[];
    final bytes = await rootBundle.load(
      'packages/panel_pages/assets/emoji_tabs/msg_emoji_cat.webp',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: EmojiTabIconScope(
          loader: (key) async {
            asked.add(key);
            return bytes;
          },
          child: probe(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(asked, hasLength(EmojiTabIcons.assets.length));
    expect(seen.contains(smileys), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a picture that cannot load is reported and left to the '
      'fallback', (tester) async {
    final reported = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => reported.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: EmojiTabIconScope(
          loader: (key) => Future<ByteData>.error(StateError('gone')),
          child: probe(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(seen.contains(smileys), isFalse);
    expect(reported, hasLength(EmojiTabIcons.assets.length));
    expect(reported, everyElement(isA<StateError>()));
  });

  testWidgets('a painter draws the picture tinted into the icon box', (
    tester,
  ) async {
    final image = (await tester.runAsync(
      () => createTestImage(width: 4, height: 4),
    ))!;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    (EmojiTabIcons.painterFor(image) as ChromeIconPainter$Paint).paint(
      canvas,
      const Size(24, 24),
      const Color(0xFFFF0000),
    );

    // Drawn without error into a recording; the pixels are the framework's.
    expect(recorder.endRecording(), isNotNull);
    image.dispose();
  });
}
