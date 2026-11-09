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
    final source = FakePackSource([_cats]);
    return PackSourceHarness(
      source: source,
      known: _cats,
      missingId: const PackId('dogs'),
      failLookups: ({required failing}) =>
          source.failure = failing ? Exception('offline') : null,
      publish: source.publish,
      fetches: source.fetches,
    );
  });

  group('FakePackSource', () {
    test('holds a lookup at its gate until resumed', () async {
      final source = FakePackSource([_cats])..gate.pause();
      PackLookup? answer;
      final pending = source.lookup(_cats.id).then((a) => answer = a);
      await Future<void>.delayed(Duration.zero);

      expect(answer, isNull);
      expect(source.peek(_cats.id), PackLookup.loading);

      source.gate.resume();
      await pending;
      expect(answer, PackLookup.found(_cats));
      source.dispose();
    });
  });
}
