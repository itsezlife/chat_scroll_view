import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

void main() {
  group('CatalogSectionAction', () {
    test('equal by id, label and icon', () {
      const a = CatalogSectionAction(id: 'more', label: 'More');

      expect(a, const CatalogSectionAction(id: 'more', label: 'More'));
      expect(
        a.hashCode,
        const CatalogSectionAction(id: 'more', label: 'More').hashCode,
      );
      expect(a, isNot(const CatalogSectionAction(id: 'less', label: 'More')));
      expect(a, isNot(const CatalogSectionAction(id: 'more', label: 'Less')));
      expect(
        a,
        isNot(
          const CatalogSectionAction(
            id: 'more',
            label: 'More',
            icon: Icons.add,
          ),
        ),
      );
    });

    test('an action nobody can see is a mistake', () {
      expect(() => CatalogSectionAction(id: 'x'), throwsAssertionError);
    });

    test('an action nobody can tell apart is a mistake', () {
      expect(
        () => CatalogSectionAction(id: '', label: 'X'),
        throwsAssertionError,
      );
    });
  });

  group('CatalogSection', () {
    test('is loaded, with no skeletons, message or action, by default', () {
      const section = CatalogSection(id: 'a', title: 'A', leaves: []);

      expect(section.state, CatalogSectionState.loaded);
      expect(section.skeletonCount, isNull);
      expect(section.emptyMessage, isNull);
      expect(section.action, isNull);
    });

    test('cannot ask for a negative count of skeletons', () {
      expect(
        () => CatalogSection(
          id: 'a',
          title: 'A',
          leaves: const [],
          skeletonCount: -1,
        ),
        throwsAssertionError,
      );
    });
  });
}
