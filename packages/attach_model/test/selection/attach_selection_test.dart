import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  AttachSelection selectionOf(
    AttachPolicy policy, {
    AttachLimits limits = const AttachLimits(),
  }) => AttachSelection(policy: policy, limits: limits);

  final photos = [for (var i = 0; i < 600; i++) AttachItems.photo('p$i')];

  group('order numbers', () {
    test('follow selection order, 1-based', () {
      final selection = selectionOf(const AttachPolicy.android())
        ..toggle(photos[2])
        ..toggle(photos[0])
        ..toggle(photos[1]);

      expect(selection.orderOf(photos[2].id), 1);
      expect(selection.orderOf(photos[0].id), 2);
      expect(selection.orderOf(photos[1].id), 3);
      expect(selection.orderOf(photos[3].id), isNull);
    });

    test('re-index on removal', () {
      final selection = selectionOf(const AttachPolicy.ios())
        ..toggle(photos[0])
        ..toggle(photos[1])
        ..toggle(photos[2]);

      selection.toggle(photos[0]);

      expect(selection.orderOf(photos[0].id), isNull);
      expect(selection.orderOf(photos[1].id), 1);
      expect(selection.orderOf(photos[2].id), 2);

      selection.remove(photos[1].id);
      expect(selection.orderOf(photos[2].id), 1);
    });

    test('the first occurrence wins when a snapshot repeats an item', () {
      final selection = selectionOf(const AttachPolicy.desktop())
        ..restore(
          AttachSelectionSnapshot([
            photos[0],
            photos[1],
            photos[0].copyWith(spoiler: true),
          ]),
        );

      expect(selection.items.map((i) => i.id), [photos[0].id, photos[1].id]);
      expect(selection.orderOf(photos[0].id), 1);
      expect(selection.items.first.spoiler, isFalse);
    });
  });

  group('the cap', () {
    for (final policy in [
      const AttachPolicy.android(),
      const AttachPolicy.ios(),
    ]) {
      test('refuses the 101st toggle on ${policy.runtimeType}', () {
        final selection = selectionOf(policy);
        for (var i = 0; i < 100; i++) {
          expect(selection.toggle(photos[i]), const AttachToggle.selected());
        }

        final refused = selection.toggle(photos[100]);

        expect(refused, const AttachToggle.refused(AttachRefusal.capReached));
        expect(selection.length, 100);
        expect(selection.contains(photos[100].id), isFalse);
      });
    }

    for (final policy in [
      const AttachPolicy.desktop(),
      const AttachPolicy.web(),
    ]) {
      test('takes 500 items on ${policy.runtimeType}', () {
        final selection = selectionOf(policy);
        for (var i = 0; i < 500; i++) {
          expect(selection.toggle(photos[i]), const AttachToggle.selected());
        }
        expect(selection.length, 500);
        expect(selection.orderOf(photos[499].id), 500);
      });
    }

    test('a refused toggle signals nothing', () {
      final selection = selectionOf(const AttachPolicy.android());
      for (var i = 0; i < 100; i++) {
        selection.toggle(photos[i]);
      }
      var signals = 0;
      selection.changes.addListener(() => signals++);

      selection.toggle(photos[100]);

      expect(signals, 0);
    });
  });

  group('gates', () {
    test('a kind the limits forbid is refused and changes nothing', () {
      final selection = selectionOf(
        const AttachPolicy.android(),
        limits: const AttachLimits(allowedKinds: {AttachKind.photo}),
      )..toggle(photos[0]);

      final refused = selection.toggle(AttachItems.video('v'));

      expect(refused, const AttachToggle.refused(AttachRefusal.kindNotAllowed));
      expect(selection.items, [photos[0]]);
    });

    test('a file over the size limit is refused', () {
      final selection = selectionOf(
        const AttachPolicy.desktop(),
        limits: const AttachLimits(fileSizeLimit: 1000),
      );

      expect(
        selection.toggle(AttachItems.file('big', byteSize: 1001)),
        const AttachToggle.refused(AttachRefusal.fileTooLarge),
      );
      expect(
        selection.toggle(AttachItems.file('fits', byteSize: 1000)),
        const AttachToggle.selected(),
      );
      expect(selection.length, 1);
    });

    test('single select replaces the selected item', () {
      final selection = selectionOf(
        const AttachPolicy.ios(),
        limits: const AttachLimits(singleSelect: true),
      )..toggle(photos[0]);

      expect(selection.toggle(photos[1]), const AttachToggle.selected());

      expect(selection.items, [photos[1]]);
      expect(selection.cap, 1);
    });
  });

  group('range toggle', () {
    test('selects every item crossed when the first was not selected', () {
      final selection = selectionOf(const AttachPolicy.ios())
        ..toggle(photos[2]);

      selection.toggleRange(photos.sublist(0, 4));

      expect(selection.items.map((i) => i.id), [
        photos[2].id,
        photos[0].id,
        photos[1].id,
        photos[3].id,
      ]);
    });

    test('deselects every item crossed when the first was selected', () {
      final selection = selectionOf(const AttachPolicy.android())
        ..toggle(photos[0])
        ..toggle(photos[2])
        ..toggle(photos[5]);

      selection.toggleRange(photos.sublist(0, 4));

      expect(selection.items, [photos[5]]);
    });

    test('stops at the cap and reports the refusals', () {
      final selection = selectionOf(const AttachPolicy.android());
      for (var i = 0; i < 98; i++) {
        selection.toggle(photos[i]);
      }

      final results = selection.toggleRange(photos.sublist(98, 102));

      expect(selection.length, 100);
      expect(results, [
        const AttachToggle.selected(),
        const AttachToggle.selected(),
        const AttachToggle.refused(AttachRefusal.capReached),
        const AttachToggle.refused(AttachRefusal.capReached),
      ]);
    });

    test('signals once for the whole range', () {
      final selection = selectionOf(const AttachPolicy.desktop());
      var signals = 0;
      selection.changes.addListener(() => signals++);

      selection.toggleRange(photos.sublist(0, 5));

      expect(signals, 1);
    });
  });

  group('reorder', () {
    test('moves an item and keeps its per-item state', () {
      final edited = photos[0].copyWith(
        spoiler: true,
        timer: const AttachTimer.once(),
        caption: const RichText.plain('first'),
        edits: const ItemEdits(version: 2, recipe: 'crop'),
      );
      final selection = selectionOf(const AttachPolicy.desktop())
        ..toggle(edited)
        ..toggle(photos[1])
        ..toggle(photos[2]);

      selection.reorder(0, 2);

      expect(selection.items.map((i) => i.id), [
        photos[1].id,
        photos[2].id,
        photos[0].id,
      ]);
      final moved = selection.items.last;
      expect(moved.spoiler, isTrue);
      expect(moved.timer, const AttachTimer.once());
      expect(moved.caption, const RichText.plain('first'));
      expect(moved.edits, const ItemEdits(version: 2, recipe: 'crop'));
      expect(selection.orderOf(photos[0].id), 3);
    });

    test('update replaces an item in place', () {
      final selection = selectionOf(const AttachPolicy.android())
        ..toggle(photos[0])
        ..toggle(photos[1]);

      selection.update(photos[0].id, (i) => i.copyWith(spoiler: true));

      expect(selection.items.first.spoiler, isTrue);
      expect(selection.orderOf(photos[0].id), 1);
    });
  });

  group('snapshot', () {
    test('restore brings back the order and the per-item state', () {
      final selection = selectionOf(const AttachPolicy.ios())
        ..toggle(photos[0])
        ..toggle(photos[1].copyWith(spoiler: true));
      final saved = selection.snapshot();

      selection
        ..toggle(photos[0])
        ..toggle(photos[2])
        ..clear();
      expect(selection.isEmpty, isTrue);

      selection.restore(saved);

      expect(selection.items, [photos[0], photos[1].copyWith(spoiler: true)]);
    });

    test('a snapshot does not change with the selection', () {
      final selection = selectionOf(const AttachPolicy.ios())
        ..toggle(photos[0]);
      final saved = selection.snapshot();

      selection.toggle(photos[1]);

      expect(saved.items, [photos[0]]);
    });
  });
}
