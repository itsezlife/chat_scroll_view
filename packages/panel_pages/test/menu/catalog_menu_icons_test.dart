/// The menus' icons.
///
/// **Seam:** [CatalogMenuIcons] and [ContentPreviewAction.icon], observed
/// through the bundle and the registry a [CatalogMenuIconScope] provides.
library;

import 'dart:ui' show ImmutableBuffer, instantiateImageCodecFromBuffer;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

void main() {
  // The art cache lives for the process, and other files' widget tests may
  // have left decodes in it that never complete.
  setUpAll(EmojiTabIcons.clearCache);

  test("every preview item leads with the reference's icon", () {
    expect(
      {
        for (final action in ContentPreviewAction.values)
          action: CatalogMenuIcons.art[action.icon]?.split('/').last,
      },
      {
        ContentPreviewAction.send: 'msg_send.webp',
        ContentPreviewAction.sendWithoutSound: 'input_notify_off.webp',
        ContentPreviewAction.favourite: 'msg_fave.webp',
        ContentPreviewAction.unfavourite: 'msg_unfave.webp',
        ContentPreviewAction.viewPack: 'msg_media.webp',
        ContentPreviewAction.removeRecent: 'msg_delete.webp',
        ContentPreviewAction.saveGif: 'msg_gif_add.webp',
        ContentPreviewAction.unsaveGif: 'msg_delete.webp',
        ContentPreviewAction.copy: 'msg_copy.webp',
      },
    );
  });

  testWidgets('every picture is bundled and decodes at its size at 3x', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final key in CatalogMenuIcons.art.values) {
        final codec = await instantiateImageCodecFromBuffer(
          await ImmutableBuffer.fromUint8List(
            (await rootBundle.load(key)).buffer.asUint8List(),
          ),
        );
        final frame = await codec.getNextFrame();
        final size = CatalogMenuIcons.sizeOf(
          CatalogMenuIcons.art.entries.firstWhere((e) => e.value == key).key,
        );
        expect(frame.image.width, size * 3, reason: key);
        expect(frame.image.height, size * 3, reason: key);
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('the scope paints the art once decoded', (tester) async {
    late ChromeIconRegistry seen;
    await tester.runAsync(() async {
      for (final key in CatalogMenuIcons.art.values) {
        await EmojiTabIcons.imageFor(key);
      }
    });

    await tester.pumpWidget(
      CatalogMenuIconScope(
        child: Builder(
          builder: (context) {
            seen = ChromeIconScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    for (final id in CatalogMenuIcons.art.keys) {
      expect(
        seen.painterFor(id),
        isA<ChromeIconPainter$Paint>(),
        reason: '$id',
      );
    }
  });
}
