import 'package:composer_editable/src/widget/selection_drag_snap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isInterruptedCharacter', () {
    test('letters digits and underscore', () {
      expect(isInterruptedCharacter('a_b1', 0), isTrue);
      expect(isInterruptedCharacter('a_b1', 1), isTrue);
      expect(isInterruptedCharacter('a_b1', 3), isTrue);
    });

    test('whitespace and punctuation are not interrupted', () {
      expect(isInterruptedCharacter('a b.', 1), isFalse);
      expect(isInterruptedCharacter('a b.', 3), isFalse);
    });
  });

  group('interruptedRunStart/End', () {
    test('finds run bounds', () {
      const text = 'xx hello_world yy';
      // 'hello_world' starts at 3
      expect(interruptedRunStart(text, 5), 3);
      expect(interruptedRunEnd(text, 5), 14);
    });
  });

  group('snapExtentForHandleDrag', () {
    const text = 'xx hello_world yy';

    test('snaps rightward expand inside run to run end', () {
      expect(
        snapExtentForHandleDrag(
          text: text,
          fixedBase: 0,
          rawExtent: 8,
          previousExtent: 5,
        ),
        14,
      );
    });

    test('snaps leftward expand inside run to run start', () {
      expect(
        snapExtentForHandleDrag(
          text: text,
          fixedBase: 20,
          rawExtent: 8,
          previousExtent: 12,
        ),
        3,
      );
    });

    test('does not snap while shrinking toward fixedBase', () {
      // Selection [0, 14), shrinking end handle into the word — must stay
      // character-precise (no jump to runStart that fights avoidCollapse).
      expect(
        snapExtentForHandleDrag(
          text: text,
          fixedBase: 0,
          rawExtent: 8,
          previousExtent: 14,
        ),
        8,
      );
    });

    test('does not oscillate when previous was near fixedBase after shrink', () {
      // After a bad snap+nudge left previousExtent at 4 while finger still at 8.
      // Shrinking relative to fixedBase=0 with previous 4 and raw 8 is expanding
      // again — but if previous was 14 and raw 8, shrink path must win.
      expect(
        snapExtentForHandleDrag(
          text: text,
          fixedBase: 3,
          rawExtent: 10,
          previousExtent: 14,
        ),
        10,
      );
    });

    test('leaves whitespace offsets unchanged', () {
      expect(
        snapExtentForHandleDrag(
          text: text,
          fixedBase: 0,
          rawExtent: 2,
          previousExtent: 1,
        ),
        2,
      );
    });

    test('does not move when extent equals fixedBase', () {
      expect(
        snapExtentForHandleDrag(
          text: text,
          fixedBase: 8,
          rawExtent: 8,
          previousExtent: 7,
        ),
        8,
      );
    });
  });
}
