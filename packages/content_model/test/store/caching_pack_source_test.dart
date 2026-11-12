import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

final _cats = Pack(
  id: const PackId('cats'),
  kind: PackKind.stickers,
  title: 'Cats',
  items: const [
    ContentDescriptor(
      key: ContentKey.document('cat'),
      semanticKind: SemanticKind.sticker,
      pack: PackId('cats'),
    ),
  ],
);

void main() {
  PackSourceContract.run(() async {
    final served = {_cats.id: _cats};
    final counts = <PackId, int>{};
    Exception? failure;
    final source = CachingPackSource((id) async {
      counts[id] = (counts[id] ?? 0) + 1;
      await Future<void>.delayed(Duration.zero);
      if (failure case final failure?) throw failure;
      return served[id];
    });
    return PackSourceHarness(
      source: source,
      known: _cats,
      missingId: const PackId('dogs'),
      failLookups: ({required failing}) =>
          failure = failing ? Exception('offline') : null,
      publish: (pack) => served[pack.id] = pack,
      fetches: (id) => counts[id] ?? 0,
    );
  });

  group('CachingPackSource', () {
    test('answers failed when the fetch serves another pack', () async {
      final source = CachingPackSource((id) async => _cats);

      final answer = await source.lookup(const PackId('dogs'));

      expect(answer, isA<PackLookup$Failed>());
      source.dispose();
    });
  });
}
