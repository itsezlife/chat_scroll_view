/// How the chat answers a pack sheet: the library edit, its bulletin with
/// Undo, and the words of the bulletin.
///
/// **Seam:** [ChatPackSheets.open] over the app's test services under the
/// app's chrome, the sheet driven by its button; observed through the
/// library and the bulletin. [ChatPackSheets.feedbackOf] is read on its own.
library;

import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_pack_sheets.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

import '../../support/test_services.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final strings = ChromeStringsPresets.english.packSheet;

  group('the bulletin says', () {
    final cats = Pack(
      id: const PackId('cats'),
      kind: PackKind.stickers,
      title: 'Cats',
      items: const [],
    );
    final a = Pack(
      id: const PackId('a'),
      kind: PackKind.emoji,
      title: 'A',
      items: const [],
    );

    test('a sticker pack added, by its title', () {
      expect(
        ChatPackSheets.feedbackOf([
          (edit: LibraryEdit$InstallPack(cats.id, cats.kind), pack: cats),
        ], strings),
        (
          title: 'Stickers added.',
          info: 'Cats has been added to your stickers.',
        ),
      );
    });

    test('a sticker pack removed or archived', () {
      expect(
        ChatPackSheets.feedbackOf([
          (edit: LibraryEdit$RemovePack(cats.id, cats.kind), pack: cats),
        ], strings).info,
        'Cats is no longer in your stickers.',
      );
      expect(
        ChatPackSheets.feedbackOf([
          (edit: LibraryEdit$ArchivePack(cats.id, cats.kind), pack: cats),
        ], strings).title,
        'Stickers archived.',
      );
    });

    test('several emoji packs, by their count', () {
      expect(
        ChatPackSheets.feedbackOf([
          (edit: LibraryEdit$InstallPack(a.id, a.kind), pack: a),
          (edit: LibraryEdit$InstallPack(cats.id, PackKind.emoji), pack: a),
        ], strings).info,
        '2 emoji packs have been added to your emoji.',
      );
    });
  });

  group('a sheet opened by the chat', () {
    late AppServices services;
    late BuildContext home;

    Future<void> pump(WidgetTester tester) async {
      services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppChrome(services: services, child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                home = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
    }

    testWidgets('removes an installed pack behind Undo, which brings it back', (
      tester,
    ) async {
      await pump(tester);
      const pack = AnimatedEmojiPack.packId;
      expect(services.library.installStateOf(pack), PackInstallState.installed);

      ChatPackSheets.open(
        home,
        services: services,
        pack: pack,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);
      final remove = find.textContaining('Удалить');
      expect(remove, findsOneWidget);

      await tester.tap(remove);
      await _settle(tester);

      expect(
        services.library.installStateOf(pack),
        PackInstallState.notInstalled,
      );
      expect(find.textContaining(AnimatedEmojiPack.title), findsOneWidget);

      await tester.tap(find.text('Отменить'));
      await _settle(tester);

      expect(services.library.installStateOf(pack), PackInstallState.installed);
    });

    testWidgets('adds a pack not installed, with no Undo', (tester) async {
      await pump(tester);
      final pack = LottieStickerPack.pack.id;
      // The demo packs are installed on the first run: removed, it is one
      // not installed.
      services.library.apply(LibraryEdit.removePack(pack, PackKind.stickers));

      ChatPackSheets.open(
        home,
        services: services,
        pack: pack,
        kind: PackKind.stickers,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);
      await tester.tap(find.textContaining('Добавить'));
      await _settle(tester);

      expect(services.library.installStateOf(pack), PackInstallState.installed);
      expect(find.text('Стикеры добавлены.'), findsOneWidget);
      expect(find.text('Отменить'), findsNothing);
    });

    testWidgets('several emoji packs share one sheet', (tester) async {
      await pump(tester);
      const packs = [AnimatedEmojiPack.packId, PackId('other')];

      ChatPackSheets.openEmojiPacks(
        home,
        services: services,
        packs: packs,
        arrangement: PanelArrangement.touch,
      ).ignore();
      // Read as it opens: the demo has one emoji pack, and a sheet with a
      // pack that is not there closes once its lookup answers.
      await tester.pump();

      final sheet = find.byType(EmojiPackSheet);
      expect(sheet, findsOneWidget);
      expect(tester.widget<EmojiPackSheet>(sheet).packIds, packs);
    });

    testWidgets('an emoji sheet shows the emoji it was opened for', (
      tester,
    ) async {
      await pump(tester);
      const emoji = ContentKey.document('tapped');

      ChatPackSheets.open(
        home,
        services: services,
        pack: AnimatedEmojiPack.packId,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
        previewEmoji: emoji,
      ).ignore();
      await tester.pump();

      final sheet = find.byType(EmojiPackSheet);
      expect(tester.widget<EmojiPackSheet>(sheet).previewEmoji, emoji);
    });

    testWidgets('a pack that does not exist says so', (tester) async {
      await pump(tester);

      ChatPackSheets.open(
        home,
        services: services,
        pack: const PackId('nope'),
        kind: PackKind.stickers,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);

      expect(find.text('Стикеры не найдены'), findsOneWidget);
    });
  });
}
