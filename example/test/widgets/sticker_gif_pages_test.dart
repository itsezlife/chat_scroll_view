/// The stickers and GIF pages in the chat's panel: what a tap on each does.
///
/// **Seam:** the chat's `ChatInputSet` under the input harness with the app's
/// services, the panel opened and a page selected by the shell, a cell
/// tapped through its semantics; observed through what the chat is told to
/// send, the recents and the panel.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<InputRig> _openOn(WidgetTester tester, String pageId) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  final rig = await InputRig.pump(
    tester,
    services: services,
    policy: const PanelPresentationPolicy$Mobile(),
  );
  await rig.tapAction(tester, ChatComposerActions.panel);
  await rig.settle(tester);
  rig.set.shell.selectPage(pageId);
  // The stand-ins of content nobody decodes shimmer for good: run the clock
  // for a while rather than until it stops.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return rig;
}

void main() {
  testWidgets('a tap on a sticker of the stickers page sends it and the panel '
      'stays open', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await _openOn(tester, 'stickers');
    final sticker = LottieStickerPack.stickers.first;

    tester.semantics.tap(find.semantics.byLabel(sticker.spokenName));
    await tester.pump();

    expect(rig.sent, [StickerMessageBody.of(sticker)]);
    expect(rig.set.presentation.state.value, isA<PanelVisibility$Shown>());
    semantics.dispose();
  });

  testWidgets('lists the packs of stickers in the stickers page\'s strip, '
      'not the GIFs, and the GIFs only on the GIF page', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await _openOn(tester, 'stickers');

    bool has(String label) =>
        find.semantics.byLabel(label).evaluate().isNotEmpty;
    expect(has(VideoStickerPack.title), isTrue);
    expect(has(LottieStickerPack.title), isTrue);
    expect(has(VideoStickerPack.gifsTitle), isFalse);

    rig.set.shell.selectPage('gif');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(has(VideoStickerPack.clips.first.spokenName), isTrue);
    expect(has(VideoStickerPack.stickers.first.spokenName), isFalse);
    semantics.dispose();
  });

  testWidgets('a tap on a clip of the GIF page sends it and files it among '
      'the recent GIFs, which the panel lists once it opens again', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final rig = await _openOn(tester, 'gif');
    final clip = VideoStickerPack.clips.first;

    tester.semantics.tap(find.semantics.byLabel(clip.spokenName));
    await tester.pump();

    expect(rig.sent, [StickerMessageBody.of(clip)]);
    expect(rig.services.recents.recents(SemanticKind.gif), [clip.key]);
    semantics.dispose();
  });
}
