/// What the bottom button of a pack sheet offers, and the words it says.
///
/// **Seam:** [PackSheetAction] built from packs and install states, read
/// through its library edits and its label in the English pack sheet
/// strings.
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

Pack _pack(
  String id, {
  PackKind kind = PackKind.stickers,
  int count = 20,
  bool official = false,
}) => Pack(
  id: PackId(id),
  kind: kind,
  title: 'Pack $id',
  official: official,
  items: [
    for (var i = 0; i < count; i++)
      ContentDescriptor(
        key: ContentKey.document('$id-$i'),
        semanticKind: kind.itemKind,
        mediaForm: MediaForm.still,
        size: const ContentSize(512, 512),
      ),
  ],
);

PackInstallState _none(PackId _) => PackInstallState.notInstalled;
PackInstallState _all(PackId _) => PackInstallState.installed;

void main() {
  final strings = ChromeStringsPresets.english.packSheet;

  group('one pack', () {
    test('a pack not installed is added', () {
      final pack = _pack('a');
      final action = PackSheetAction.of([pack], _none);

      expect(action!.requests, [
        (edit: LibraryEdit.installPack(pack.id, PackKind.stickers), pack: pack),
      ]);
      expect(action.labelIn(strings), 'Add 20 stickers');
      expect(action.removes, isFalse);
    });

    test('an archived pack is added again', () {
      final action = PackSheetAction.of([
        _pack('a'),
      ], (_) => PackInstallState.archived);

      expect(action!.requests.single.edit, isA<LibraryEdit$InstallPack>());
    });

    test('an installed pack is removed', () {
      final pack = _pack('a', count: 1);
      final action = PackSheetAction.of([pack], _all);

      expect(
        action!.requests.single.edit,
        LibraryEdit.removePack(pack.id, PackKind.stickers),
      );
      expect(action.labelIn(strings), 'Remove sticker');
      expect(action.removes, isTrue);
    });

    test('an installed official pack is archived, under the same words', () {
      final pack = _pack('a', official: true);
      final action = PackSheetAction.of([pack], _all);

      expect(
        action!.requests.single.edit,
        LibraryEdit.archivePack(pack.id, PackKind.stickers),
      );
      expect(action.labelIn(strings), 'Remove 20 stickers');
    });

    test('masks and emoji say their own kind', () {
      final masks = _pack('m', kind: PackKind.masks, count: 3);
      final emoji = _pack('e', kind: PackKind.emoji, count: 32);

      expect(
        PackSheetAction.of([masks], _none)!.labelIn(strings),
        'Add 3 masks',
      );
      expect(
        PackSheetAction.of([emoji], _none)!.labelIn(strings),
        'Add 32 emoji',
      );
      expect(
        PackSheetAction.of([emoji], _all)!.labelIn(strings),
        'Remove 32 emoji',
      );
    });
  });

  group('several packs', () {
    final a = _pack('a', kind: PackKind.emoji, count: 8);
    final b = _pack('b', kind: PackKind.emoji, count: 9);
    final c = _pack('c', kind: PackKind.emoji, count: 10);
    PackInstallState onlyB(PackId id) =>
        id == b.id ? PackInstallState.installed : PackInstallState.notInstalled;

    test('the packs not installed are added, in their order', () {
      final action = PackSheetAction.of([a, b, c], onlyB);

      expect([for (final r in action!.requests) r.pack], [a, c]);
      expect(action.labelIn(strings), 'Add 2 emoji packs');
    });

    test('one pack left to add says its emoji', () {
      final action = PackSheetAction.of([a, b], onlyB);

      expect(action!.labelIn(strings), 'Add 8 emoji');
    });

    test('with every pack installed, all are removed', () {
      final action = PackSheetAction.of([a, b], _all);

      expect(
        [for (final r in action!.requests) r.edit],
        [
          LibraryEdit.removePack(a.id, PackKind.emoji),
          LibraryEdit.removePack(b.id, PackKind.emoji),
        ],
      );
      expect(action.labelIn(strings), 'Remove 2 emoji packs');
    });
  });

  test('no pack, no button', () {
    expect(PackSheetAction.of(const [], _none), isNull);
  });
}
