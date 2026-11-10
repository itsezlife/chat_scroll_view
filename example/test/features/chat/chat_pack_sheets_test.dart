/// How the chat answers a pack sheet: the library edit, its bulletin with
/// Undo, and the words of the bulletin.
///
/// **Seam:** [ChatPackSheets.open] over the app's test services under the
/// app's chrome, the sheet driven by its button; observed through the
/// library and the bulletin. [ChatPackSheets.feedbackOf] is read on its own.
library;

import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackBinding, ChatPreImeBackClaim;
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_pack_sheets.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
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

  // The toggle runs as the bulletin's delayed
  // action: whatever takes the bulletin away, but Undo, commits the edit,
  // and the library's own window is only a guard.
  group('a removal behind its bulletin', () {
    final cats = Pack(
      id: const PackId('cats'),
      kind: PackKind.stickers,
      title: 'Cats',
      items: const [],
    );
    late FakeContentLibrary library;
    late BulletinController bulletins;
    setUp(() {
      library = FakeContentLibrary(
        limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
      )..apply(LibraryEdit.installPack(cats.id, cats.kind));
      bulletins = BulletinController(clock: ManualBulletinClock());
    });
    tearDown(() => bulletins.dispose());

    void remove() => ChatPackSheets.apply(
      library,
      [(edit: LibraryEdit$RemovePack(cats.id, cats.kind), pack: cats)],
      strings,
      bulletins,
    );

    test('waits while the bulletin shows its Undo', () async {
      remove();
      await pumpEventQueue();

      expect(
        bulletins.current.value?.bulletin.action,
        isA<BulletinAction$Undo>(),
      );
      expect(library.installStateOf(cats.id), PackInstallState.notInstalled);
      expect(library.committed, hasLength(1));
    });

    test('commits when another bulletin replaces it', () async {
      remove();
      bulletins.show(const Bulletin(message: 'next'));
      await pumpEventQueue();

      expect(
        library.committed.last,
        LibraryEdit$RemovePack(cats.id, cats.kind),
      );
    });

    test('Undo brings the pack back and commits nothing', () async {
      remove();
      bulletins.current.value!.pressAction();
      await pumpEventQueue();

      expect(library.installStateOf(cats.id), PackInstallState.installed);
      expect(library.committed, hasLength(1));
    });
  });

  group('under the desktop policy', () {
    final cats = Pack(
      id: const PackId('cats'),
      kind: PackKind.stickers,
      title: 'Cats',
      items: const [],
    );
    late FakeContentLibrary library;
    late BulletinController bulletins;
    setUp(() {
      library = FakeContentLibrary(
        limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
      )..apply(LibraryEdit.installPack(cats.id, cats.kind));
      bulletins = BulletinController(
        policy: const BulletinPolicy.desktop(),
        clock: ManualBulletinClock(),
      );
    });
    tearDown(() => bulletins.dispose());

    test('says no library edit in a bulletin', () {
      expect(ChatPackSheets.saysLibraryEdits(bulletins), isFalse);
    });

    test('a favourite is said on the web only when the full list replaced '
        'its oldest; a desktop says none', () {
      final added = library.apply(
        const LibraryEdit.favouriteSticker(ContentKey.document('f0')),
      );
      expect(
        ChatPackSheets.libraryEditBulletin(
          added,
          limits: library.limits,
          bulletins: bulletins,
          web: true,
        ),
        isNull,
      );
      for (var i = 1; i < 5; i++) {
        library.apply(LibraryEdit.favouriteSticker(ContentKey.document('f$i')));
      }
      final replaced = library.apply(
        const LibraryEdit.favouriteSticker(ContentKey.document('new')),
      );
      expect(replaced.evicted, isNotNull);
      expect(
        ChatPackSheets.libraryEditBulletin(
          replaced,
          limits: library.limits,
          bulletins: bulletins,
          web: true,
        ),
        isNotNull,
      );
      expect(
        ChatPackSheets.libraryEditBulletin(
          replaced,
          limits: library.limits,
          bulletins: bulletins,
          web: false,
        ),
        isNull,
      );
    });

    test('the web removes a pack at once; a desktop asks first', () {
      expect(
        ChatPackSheets.confirmsRemovalsIn(PanelArrangement.pointer, web: true),
        isFalse,
      );
      expect(
        ChatPackSheets.confirmsRemovalsIn(PanelArrangement.pointer, web: false),
        isTrue,
      );
    });

    test(
      'a removal shows no bulletin and is done at once, with no Undo',
      () async {
        ChatPackSheets.apply(
          library,
          [(edit: LibraryEdit$RemovePack(cats.id, cats.kind), pack: cats)],
          strings,
          bulletins,
        );
        await pumpEventQueue();

        expect(bulletins.current.value, isNull);
        expect(library.installStateOf(cats.id), PackInstallState.notInstalled);
        expect(
          library.committed.last,
          LibraryEdit$RemovePack(cats.id, cats.kind),
        );
      },
    );
  });

  group('a sheet opened by the chat', () {
    late AppServices services;
    late BuildContext home;
    late BulletinController bulletins;

    Future<void> pump(WidgetTester tester) async {
      services = (await tester.runAsync(createTestServices))!;
      addTearDown(services.dispose);
      bulletins = BulletinController(policy: const BulletinPolicy.android());
      addTearDown(bulletins.dispose);
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppChrome(services: services, child: child!),
          home: Scaffold(
            body: BulletinHost(
              controller: bulletins,
              child: Builder(
                builder: (context) {
                  home = context;
                  return const SizedBox.expand();
                },
              ),
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
        bulletins: bulletins,
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

    testWidgets('under a pointer Remove swaps the box for a confirmation, '
        'which removes the pack with no bulletin', (tester) async {
      await pump(tester);
      bulletins = BulletinController(policy: const BulletinPolicy.desktop());
      addTearDown(bulletins.dispose);
      const pack = AnimatedEmojiPack.packId;

      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: pack,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.pointer,
      ).ignore();
      await _settle(tester);
      await tester.tap(find.text('Удалить эмодзи'));
      await _settle(tester);

      // The box is gone and the question stands in its place.
      expect(find.text('Удалить эмодзи'), findsNothing);
      expect(
        find.text('Удалить «${AnimatedEmojiPack.title}»?'),
        findsOneWidget,
      );
      expect(services.library.installStateOf(pack), PackInstallState.installed);

      await tester.tap(find.text('Удалить'));
      await _settle(tester);

      expect(
        services.library.installStateOf(pack),
        PackInstallState.notInstalled,
      );
      expect(bulletins.current.value, isNull);
    });

    // The dim of the layer: one for the box and the confirmation together.
    int dims(WidgetTester tester) => find
        .byWidgetPredicate(
          (widget) =>
              widget is ModalBarrier &&
              widget.dismissible &&
              widget.color == PackSheet.pointerBarrier,
        )
        .evaluate()
        .length;

    testWidgets('under a pointer the confirmation stands on the box\'s layer, '
        'and Cancel brings the box back at once', (tester) async {
      await pump(tester);
      bulletins = BulletinController(policy: const BulletinPolicy.desktop());
      addTearDown(bulletins.dispose);
      const pack = AnimatedEmojiPack.packId;

      var closed = false;
      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: pack,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.pointer,
      ).whenComplete(() => closed = true).ignore();
      await _settle(tester);
      await tester.tap(find.text('Удалить эмодзи'));
      await tester.pump();

      expect(
        find.text('Удалить «${AnimatedEmojiPack.title}»?'),
        findsOneWidget,
      );
      expect(dims(tester), 1, reason: 'one layer, one dim');

      await tester.tap(find.text('Отмена'));
      await tester.pump();

      expect(find.text('Удалить эмодзи'), findsOneWidget, reason: 'box back');
      expect(find.text('Удалить «${AnimatedEmojiPack.title}»?'), findsNothing);
      expect(dims(tester), 1);
      expect(closed, isFalse);
      expect(services.library.installStateOf(pack), PackInstallState.installed);
    });

    testWidgets('under a pointer a confirmed removal brings the box back with '
        'the pack removed; a tap on the dim closes it', (tester) async {
      await pump(tester);
      bulletins = BulletinController(policy: const BulletinPolicy.desktop());
      addTearDown(bulletins.dispose);
      const pack = AnimatedEmojiPack.packId;

      var closed = false;
      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: pack,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.pointer,
      ).whenComplete(() => closed = true).ignore();
      await _settle(tester);
      await tester.tap(find.text('Удалить эмодзи'));
      await tester.pump();
      await tester.tap(find.text('Удалить'));
      await tester.pump();

      expect(
        services.library.installStateOf(pack),
        PackInstallState.notInstalled,
      );
      expect(find.text('Удалить «${AnimatedEmojiPack.title}»?'), findsNothing);
      expect(find.text('Удалить эмодзи'), findsNothing, reason: 'now adds');
      expect(dims(tester), 1, reason: 'the box is back');

      await tester.tapAt(const Offset(4, 4));
      await _settle(tester);
      expect(dims(tester), 0);
      expect(closed, isTrue);
    });

    // The bulletin is up longer than the window it is named after: it
    // slides in first, and its timer runs only once it is in. Undo works as
    // long as the bulletin shows it, and the bulletin hides by itself.
    testWidgets('Undo works while the bulletin shows it, which then hides', (
      tester,
    ) async {
      await pump(tester);
      const pack = AnimatedEmojiPack.packId;
      services.library.apply(
        const LibraryEdit.installPack(PackId('b'), PackKind.emoji),
      );
      services.library.apply(
        const LibraryEdit.installPack(PackId('a'), PackKind.emoji),
      );
      final before = services.library.installedPacks(PackKind.emoji).value;
      expect(before.indexOf(pack), 2);

      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: pack,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);
      await tester.tap(find.textContaining('Удалить'));
      // Past the window, the bulletin still up.
      for (var i = 0; i < 29; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Отменить'), findsOneWidget);

      await tester.tap(find.text('Отменить'));
      await _settle(tester);

      expect(services.library.installedPacks(PackKind.emoji).value, before);
      expect(find.text('Отменить'), findsNothing);
    });

    testWidgets('the bulletin hides by itself and the removal holds', (
      tester,
    ) async {
      await pump(tester);
      const pack = AnimatedEmojiPack.packId;

      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: pack,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);
      await tester.tap(find.textContaining('Удалить'));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Отменить'), findsNothing);
      expect(
        services.library.installStateOf(pack),
        PackInstallState.notInstalled,
      );
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
        bulletins: bulletins,
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

    testWidgets('a pack bulletin leads with the pack, long with Undo', (
      tester,
    ) async {
      await pump(tester);
      const pack = AnimatedEmojiPack.packId;

      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: pack,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);
      await tester.tap(find.textContaining('Удалить'));
      await _settle(tester);

      final bulletin = bulletins.current.value!.bulletin;
      expect(bulletin.leading, isA<BulletinLeading$Thumbnail>());
      expect(bulletin.effectiveDuration, BulletinDuration.long);
    });

    testWidgets('several emoji packs share one sheet', (tester) async {
      await pump(tester);
      const packs = [AnimatedEmojiPack.packId, PackId('other')];

      ChatPackSheets.openEmojiPacks(
        home,
        services: services,
        bulletins: bulletins,
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
        bulletins: bulletins,
        pack: AnimatedEmojiPack.packId,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
        previewEmoji: emoji,
      ).ignore();
      await tester.pump();

      final sheet = find.byType(EmojiPackSheet);
      expect(tester.widget<EmojiPackSheet>(sheet).previewEmoji, emoji);
    });

    testWidgets('back closes the sheet before the panel or keyboard under '
        'it', (tester) async {
      await pump(tester);
      addTearDown(ChatPreImeBackBinding.debugReset);
      // The panel's claim (or a raised keyboard) under the sheet.
      var panelBacks = 0;
      final panel = ChatPreImeBackClaim.push(() async {
        panelBacks++;
        return true;
      });
      addTearDown(panel.pop);

      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: AnimatedEmojiPack.packId,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);
      expect(find.byType(EmojiPackSheet), findsOneWidget);

      expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
      await _settle(tester);
      expect(find.byType(EmojiPackSheet), findsNothing);
      expect(panelBacks, 0);

      expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
      expect(panelBacks, 1);
    });

    testWidgets('a sheet takes back before the keyboard, with no panel', (
      tester,
    ) async {
      await pump(tester);
      addTearDown(ChatPreImeBackBinding.debugReset);

      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: AnimatedEmojiPack.packId,
        kind: PackKind.emoji,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);

      // Claimed pre-IME: the press never reaches the keyboard.
      expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
      await _settle(tester);
      expect(find.byType(EmojiPackSheet), findsNothing);
      expect(await ChatPreImeBackBinding.handleNativeBack(), isFalse);
    });

    testWidgets('a pack that does not exist says so', (tester) async {
      await pump(tester);

      ChatPackSheets.open(
        home,
        services: services,
        bulletins: bulletins,
        pack: const PackId('nope'),
        kind: PackKind.stickers,
        arrangement: PanelArrangement.touch,
      ).ignore();
      await _settle(tester);

      expect(find.text('Стикеры не найдены'), findsOneWidget);
    });
  });
}
