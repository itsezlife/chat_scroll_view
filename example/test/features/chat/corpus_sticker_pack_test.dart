/// The local corpus of Lottie stickers: found in the asset bundle or in a
/// directory, listed as packs, and read back by the pipeline's fetcher.
///
/// **Seam:** [CorpusStickerPack.load] over a fake asset bundle and a temporary
/// directory, observed through the packs, sources and fetcher it makes. The
/// Lottie files are tiny synthetic JSON written by the tests; no real sticker
/// is read.
library;

import 'dart:convert';
import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/corpus_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// An asset bundle holding [files] and the manifest that lists them.
final class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(Map<String, String> files)
    : _files = {for (final e in files.entries) e.key: utf8.encode(e.value)};

  final Map<String, List<int>> _files;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final manifest = <String, Object>{
        for (final path in _files.keys)
          path: <Object>[
            {'asset': path},
          ],
      };
      return const StandardMessageCodec().encodeMessage(manifest)!;
    }
    final bytes = _files[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

FetchRequest _request(ContentDescriptor descriptor, {FetchPart? part}) =>
    FetchRequest(
      descriptor: descriptor,
      part: part ?? FetchPart.content,
      priority: AssetPriority.visible,
      cancellation: CancellationToken(),
    );

const _dir = 'assets/sticker_corpus';

List<String> _titles(CorpusStickerPack pack) => [
  for (final p in pack.packs) p.title,
];

void main() {
  group('from the asset bundle', () {
    test(
      'makes one pack per prefix, the prefix as its title, in name order',
      () async {
        final pack = await CorpusStickerPack.load(
          bundle: _FakeBundle({
            '$_dir/duck--1.json': '{"a":1}',
            '$_dir/baby_yoda--0.json': '{"a":2}',
            '$_dir/duck--0.json': '{"a":3}',
            '$_dir/duck--10.json': '{"a":4}',
          }),
        );

        expect(_titles(pack), ['baby_yoda', 'duck']);
        expect(
          [for (final s in pack.packs.last.stickers) s.name],
          ['0', '1', '10'],
        );
      },
    );

    test(
      'takes compressed stickers (.tgs) like plain ones, by file name',
      () async {
        final pack = await CorpusStickerPack.load(
          bundle: _FakeBundle({
            '$_dir/utya--1.tgs': 'x',
            '$_dir/utya--0.tgs': 'y',
            '$_dir/duck--0.json': '{}',
          }),
        );

        expect(_titles(pack), ['duck', 'utya']);
        expect([for (final s in pack.packs.last.stickers) s.name], ['0', '1']);
      },
    );

    test(
      'ignores the folder README, the git rules and anything not a pack file',
      () async {
        final pack = await CorpusStickerPack.load(
          bundle: _FakeBundle({
            '$_dir/README.md': 'x',
            '$_dir/.gitignore': 'x',
            '$_dir/loose.json': '{}',
            '$_dir/duck--0.png': 'x',
            'assets/other/duck--0.json': '{}',
            '$_dir/duck--0.json': '{}',
          }),
        );

        expect(_titles(pack), ['duck']);
        expect(pack.packs.single.stickers, hasLength(1));
      },
    );

    test(
      'lists no pack when the bundle holds none, as in a checkout without the files',
      () async {
        final pack = await CorpusStickerPack.load(
          bundle: _FakeBundle({'$_dir/README.md': 'x'}),
        );

        expect(pack.isEmpty, isTrue);
        expect(pack.sources(), isEmpty);
      },
    );

    test('lists no pack when the bundle has no manifest at all', () async {
      final pack = await CorpusStickerPack.load(bundle: _BrokenBundle());

      expect(pack.isEmpty, isTrue);
    });
  });

  group('from a directory', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('corpus_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final (pack, name) in [('fox', '0'), ('fox', '1'), ('owl', '0')]) {
        Directory('${dir.path}/$pack').createSync();
        File(
          '${dir.path}/$pack/$name.json',
        ).writeAsStringSync('{"n":"$pack$name"}');
      }
      File('${dir.path}/fox/notes.txt').writeAsStringSync('x');
      File('${dir.path}/stray.json').writeAsStringSync('{}');
    });

    test('takes compressed stickers (.tgs) in a folder too', () async {
      Directory('${dir.path}/utya').createSync();
      File('${dir.path}/utya/0.tgs').writeAsBytesSync([0x1f, 0x8b]);

      final pack = await CorpusStickerPack.load(
        bundle: _FakeBundle({}),
        directory: dir.path,
      );

      expect(_titles(pack), ['fox', 'owl', 'utya']);
      expect([for (final s in pack.packs.last.stickers) s.name], ['0']);
    });

    test('makes one pack per folder with Lottie files', () async {
      final pack = await CorpusStickerPack.load(
        bundle: _FakeBundle({}),
        directory: dir.path,
      );

      expect(_titles(pack), ['fox', 'owl']);
      expect(pack.packs.first.stickers, hasLength(2));
    });

    test('lists nothing for a directory that is not there', () async {
      final pack = await CorpusStickerPack.load(
        bundle: _FakeBundle({}),
        directory: '${dir.path}/absent',
      );

      expect(pack.isEmpty, isTrue);
    });

    test('lists nothing for an empty define', () async {
      final pack = await CorpusStickerPack.load(
        bundle: _FakeBundle({}),
        directory: '',
      );

      expect(pack.isEmpty, isTrue);
    });

    test(
      'takes the folder over a pack of the same name in the bundle',
      () async {
        final pack = await CorpusStickerPack.load(
          bundle: _FakeBundle({'$_dir/fox--0.json': '{"from":"bundle"}'}),
          directory: dir.path,
        );

        final fetched = await pack
            .fetcher(otherwise: _NoFetcher())
            .fetch(_request(pack.packs.first.stickers.first.descriptor));
        expect(utf8.decode((fetched as FetchedBytes).bytes), '{"n":"fox0"}');
        expect(pack.packs.first.stickers, hasLength(2));
      },
    );
  });

  group('a pack', () {
    late CorpusStickerPack pack;

    setUp(() async {
      pack = await CorpusStickerPack.load(
        bundle: _FakeBundle({
          '$_dir/duck--0.json': '{"v":"duck0"}',
          '$_dir/duck--1.json': '{"v":"duck1"}',
        }),
      );
    });

    test('describes its stickers as vector animations of the sticker kind', () {
      final sticker = pack.packs.single.stickers.first;

      expect(sticker.descriptor.semanticKind, SemanticKind.sticker);
      expect(sticker.descriptor.mediaForm, MediaForm.vectorAnimation);
      expect(sticker.descriptor.animated, isTrue);
      expect(sticker.descriptor.size, const ContentSize(512, 512));
      expect(sticker.key, sticker.descriptor.key);
    });

    test('finds a sticker by its key and no other content', () {
      final sticker = pack.packs.single.stickers.last;

      expect(pack.of(sticker.key), same(sticker));
      expect(pack.of(const ContentKey.document('corpus:nope:0')), isNull);
      expect(pack.of(const ContentKey.document('other')), isNull);
      expect(CorpusStickerPack.isKey(sticker.key), isTrue);
      expect(
        CorpusStickerPack.isKey(const ContentKey.document('other')),
        isFalse,
      );
    });

    test('lists every sticker of every pack for the pipeline', () {
      expect(pack.descriptors.map((d) => d.key), [
        for (final s in pack.packs.single.stickers) s.key,
      ]);
    });

    test('publishes each pack as an installed, loaded collection', () {
      final sources = pack.sources();
      addTearDown(() {
        for (final source in sources) {
          source.dispose();
        }
      });

      final collection = sources.single.collections.value.single;
      expect(collection.id, pack.packs.single.id);
      expect(collection.metadata.title, 'duck');
      expect(collection.metadata.flags, CollectionFlags.installed);
      expect(
        (collection.contents as CollectionContents$Loaded).items,
        hasLength(2),
      );
    });

    test('fetches a sticker from the bundle', () async {
      final sticker = pack.packs.single.stickers.last;

      final fetched = await pack
          .fetcher(otherwise: _NoFetcher())
          .fetch(_request(sticker.descriptor));

      expect(utf8.decode((fetched as FetchedBytes).bytes), '{"v":"duck1"}');
    });

    test('leaves other keys to the fetcher it was given', () async {
      final other = _NoFetcher();
      const descriptor = ContentDescriptor(key: ContentKey.document('x'));

      await pack.fetcher(otherwise: other).fetch(_request(descriptor));

      expect(other.asked, [descriptor.key]);
    });

    test(
      'has no thumbnail, and fails a sticker it does not hold for good',
      () async {
        final sticker = pack.packs.single.stickers.first;
        final fetcher = pack.fetcher(otherwise: _NoFetcher());

        await expectLater(
          fetcher.fetch(
            _request(sticker.descriptor, part: FetchPart.thumbnail),
          ),
          throwsA(isA<FetchFailure>()),
        );
        const ghost = ContentDescriptor(
          key: ContentKey.document('corpus:duck:99'),
        );
        await expectLater(
          fetcher.fetch(_request(ghost)),
          throwsA(
            isA<FetchFailure>().having(
              (failure) => failure.kind,
              'kind',
              AssetFailureKind.permanent,
            ),
          ),
        );
      },
    );
  });
}

final class _NoFetcher implements ContentFetcher {
  final asked = <ContentKey>[];

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    asked.add(request.descriptor.key);
    return FetchedContent.bytes(Uint8List(0));
  }
}

final class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Unable to load asset: $key');
}
