import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

CatalogSection _section(String id, int leaves) => CatalogSection(
  id: id,
  title: id,
  leaves: [for (var i = 0; i < leaves; i++) CatalogLeaf.unicode('$id$i')],
);

void main() {
  group('CatalogSnapshot', () {
    test('freezes the sections it was built from', () {
      final source = [_section('a', 2)];
      final snapshot = CatalogSnapshot(source);

      source.add(_section('b', 1));

      expect(snapshot.sections.map((s) => s.id), ['a']);
      expect(
        () => snapshot.sections.add(_section('c', 1)),
        throwsUnsupportedError,
      );
    });

    test('empty has no sections', () {
      expect(const CatalogSnapshot.empty().sections, isEmpty);
    });
  });

  group('FakeCatalogSnapshotSource', () {
    late FakeCatalogSnapshotSource source;
    setUp(() => source = FakeCatalogSnapshotSource());
    tearDown(() => source.dispose());

    test('starts with the sections it was given and does not notify', () {
      source.dispose();
      source = FakeCatalogSnapshotSource(sections: [_section('a', 1)]);
      var calls = 0;
      source.addListener(() => calls++);

      expect(source.value.sections.single.id, 'a');
      expect(calls, 0);
    });

    test('replaceSections publishes one new snapshot', () {
      final before = source.value;
      var calls = 0;
      source.addListener(() => calls++);

      source.replaceSections([_section('a', 3)]);

      expect(calls, 1);
      expect(identical(source.value, before), isFalse);
      expect(source.value.sections.single.leaves, hasLength(3));
    });

    test('a listener may add and remove listeners while it runs', () {
      final order = <String>[];
      void late() => order.add('late');
      void self() {
        order.add('self');
        source
          ..removeListener(self)
          ..addListener(late);
      }

      source.addListener(self);
      source.replaceSections([_section('a', 1)]);
      source.replaceSections([_section('b', 1)]);

      expect(order, ['self', 'late']);
    });

    test('is silent after dispose and keeps the last snapshot readable', () {
      var calls = 0;
      source.addListener(() => calls++);
      source.replaceSections([_section('a', 1)]);

      source.dispose();
      source.replaceSections([_section('b', 1)]);
      source.dispose();

      expect(calls, 1);
      expect(source.value.sections.single.id, 'a');
    });
  });
}
