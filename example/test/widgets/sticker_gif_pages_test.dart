/// The stickers and GIF pages in the chat's panel: what each lists and what a
/// tap on each does. They list real content only: the local sticker corpus
/// and Giphy, never the bundled demo packs.
///
/// **Seam:** the chat's `ChatInputSet` under the input harness with the app's
/// services, the panel opened and a page selected by the shell, a cell
/// tapped through its semantics; observed through what the chat is told to
/// send, the recents and the panel.
library;

import 'dart:io';

import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/corpus_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_message_body.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:panel_presentation/panel_presentation.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<InputRig> _openOn(
  WidgetTester tester,
  String pageId, {
  Future<AppServices> Function()? create,
}) async {
  final services = (await tester.runAsync(create ?? createTestServices))!;
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

// A corpus of one pack, `fox`, with one sticker, in a folder of its own.
Future<CorpusStickerPack> _foxCorpus() async {
  final dir = Directory.systemTemp.createTempSync('corpus_pages');
  addTearDown(() => dir.deleteSync(recursive: true));
  Directory('${dir.path}/fox').createSync();
  File('${dir.path}/fox/0.json').writeAsStringSync('{}');
  return CorpusStickerPack.load(bundle: rootBundle, directory: dir.path);
}

bool _has(String label) => find.semantics.byLabel(label).evaluate().isNotEmpty;

// Every name of the bundled demo stickers, clips and GIFs.
final _demoLabels = [
  LottieStickerPack.title,
  StaticStickerPack.title,
  VideoStickerPack.title,
  VideoStickerPack.gifsTitle,
  for (final item in [
    ...LottieStickerPack.stickers,
    ...StaticStickerPack.stickers,
    ...VideoStickerPack.items,
  ])
    item.descriptor.spokenName!,
];

void main() {
  testWidgets('a tap on a corpus sticker of the stickers page sends it and '
      'the panel stays open', (tester) async {
    final semantics = tester.ensureSemantics();
    final corpus = (await tester.runAsync(_foxCorpus))!;
    final rig = await _openOn(
      tester,
      'stickers',
      create: () => createTestServices(corpus: corpus),
    );
    // Picked by folder: a developer may have linked corpus files into the
    // (gitignored) bundled assets folder, which add packs.
    final sticker = corpus.packs
        .singleWhere((pack) => pack.folder == 'fox')
        .stickers
        .single;

    expect(_has('fox'), isTrue, reason: 'the strip names the pack');
    // Its tab brings the pack into view, wherever linked packs put it. With
    // the fox pack alone (no linked corpus) its section header is on screen
    // too and carries the same label, so tap the first match: either one
    // leaves the pack in view.
    tester.semantics.tap(find.semantics.byLabel('fox').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.semantics.tap(find.semantics.byLabel('fox 0'));
    await tester.pump();

    expect(rig.sent, [StickerMessageBody.of(sticker)]);
    expect(rig.set.presentation.state.value, isA<PanelVisibility$Shown>());
    semantics.dispose();
  });

  testWidgets('without a corpus the stickers page lists no demo pack and '
      'says it has no sticker', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openOn(tester, 'stickers');

    for (final label in _demoLabels) {
      expect(_has(label), isFalse, reason: label);
    }
    expect(find.text(demoChromeStrings.panel.stickersEmpty), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a recent sticker is listed and sent from the stickers page '
      'without a corpus', (tester) async {
    final semantics = tester.ensureSemantics();
    final sticker = LottieStickerPack.stickers.first;
    final rig = await _openOn(
      tester,
      'stickers',
      create: () async {
        final services = await createTestServices();
        services.library.apply(LibraryEdit.addRecentSticker(sticker.key));
        return services;
      },
    );

    tester.semantics.tap(find.semantics.byLabel(sticker.spokenName));
    await tester.pump();

    expect(rig.sent, [StickerMessageBody.of(sticker)]);
    expect(find.text(demoChromeStrings.panel.stickersEmpty), findsNothing);
    semantics.dispose();
  });

  testWidgets('a favourite sticker is listed under its own title and tab, '
      'and sent from there', (tester) async {
    final semantics = tester.ensureSemantics();
    final favourite = StaticStickerPack.stickers.first;
    final recent = LottieStickerPack.stickers.first;
    final rig = await _openOn(
      tester,
      'stickers',
      create: () async {
        final services = await createTestServices();
        services.library
          ..apply(LibraryEdit.addRecentSticker(recent.key))
          ..apply(LibraryEdit.favouriteSticker(favourite.key));
        return services;
      },
    );
    final panel = demoChromeStrings.panel;

    // A tab and a section header each.
    expect(
      find.semantics.byLabel(panel.favouriteStickersTitle).evaluate(),
      hasLength(2),
    );
    tester.semantics.tap(find.semantics.byLabel(favourite.spokenName));
    await tester.pump();

    expect(rig.sent, [StickerMessageBody.of(favourite)]);
    expect(rig.services.library.recentStickers.value, [
      favourite.key,
      recent.key,
    ]);
    semantics.dispose();
  });

  group('with Giphy', () {
    // A hand-written answer in the shape of the documentation: one trending
    // clip, and nothing for the downloads, which nobody plays here.
    http.Client giphy() => MockClient((request) async {
      if (request.url.host != 'api.giphy.com') {
        return http.Response('', 404);
      }
      return http.Response(
        '{"data":[{"id":"abc123","title":"happy cat","images": '
        '{"fixed_width":{"mp4":"https://media.example/abc123.mp4",'
        '"width":"200","height":"150"}}}],'
        '"pagination":{"total_count":1,"count":1,"offset":0}}',
        200,
      );
    });

    Future<InputRig> openGif(WidgetTester tester, {http.Client? client}) =>
        _openOn(
          tester,
          'gif',
          create: () => createTestServices(
            giphyApiKey: 'test-key',
            giphyHttpClient: client ?? giphy(),
          ),
        );

    testWidgets('a tap on a trending clip sends it as a lone document that '
        'names the Giphy clip, saves it, and the page '
        'credits Giphy', (tester) async {
      final semantics = tester.ensureSemantics();
      final rig = await openGif(tester);

      expect(find.text(AppServices.giphyAttribution), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('happy cat'));
      await tester.pump();

      expect(rig.sent, ['![happy cat](document:giphy:abc123)']);
      expect(rig.services.library.savedGifs.value, [
        const ContentKey.document('giphy:abc123'),
      ]);
      for (final label in _demoLabels) {
        expect(_has(label), isFalse, reason: label);
      }
      semantics.dispose();
    });

    testWidgets('offline the page says the load failed, with a retry, and '
        'no demo clip beneath', (tester) async {
      final semantics = tester.ensureSemantics();
      await openGif(
        tester,
        client: MockClient((_) async => throw const SocketException('offline')),
      );

      expect(find.text(demoChromeStrings.panel.gifsFailed), findsOneWidget);
      expect(find.text(demoChromeStrings.panel.retryAction), findsOneWidget);
      for (final label in _demoLabels) {
        expect(_has(label), isFalse, reason: label);
      }
      semantics.dispose();
    });

    testWidgets('the page declares search', (tester) async {
      final rig = await openGif(tester);

      final page = rig.set.shell.pages.firstWhere((p) => p.id == 'gif');
      expect(page.capabilities.search, isTrue);
    });
  });

  testWidgets('without a key the GIF page lists no demo clip, says it has '
      'none, credits nobody and does not search', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await _openOn(tester, 'gif');

    expect(find.text(AppServices.giphyAttribution), findsNothing);
    for (final label in _demoLabels) {
      expect(_has(label), isFalse, reason: label);
    }
    expect(find.text(demoChromeStrings.panel.gifsEmpty), findsOneWidget);
    final page = rig.set.shell.pages.firstWhere((p) => p.id == 'gif');
    expect(page.capabilities.search, isFalse);
    semantics.dispose();
  });
}
