import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

void main() {
  group('AnchoredPopupStyle.hoverGutter', () {
    test('defaults to the room a shadow is drawn in', () {
      expect(const AnchoredPopupStyle(width: 300).hoverGutter, 10);
    });

    test('takes part in equality', () {
      expect(
        const AnchoredPopupStyle(width: 300, hoverGutter: 4),
        const AnchoredPopupStyle(width: 300, hoverGutter: 4),
      );
      expect(
        const AnchoredPopupStyle(width: 300, hoverGutter: 4),
        isNot(const AnchoredPopupStyle(width: 300)),
      );
    });

    test('is never negative', () {
      expect(
        () => AnchoredPopupStyle(width: 300, hoverGutter: -1),
        throwsAssertionError,
      );
    });
  });

  group('AnchoredPopupStyle.edgeGap', () {
    test('is nothing unless the host asks for one', () {
      expect(const AnchoredPopupStyle(width: 300).edgeGap, 0);
    });

    test('takes part in equality', () {
      expect(
        const AnchoredPopupStyle(width: 300, edgeGap: 10),
        const AnchoredPopupStyle(width: 300, edgeGap: 10),
      );
      expect(
        const AnchoredPopupStyle(width: 300, edgeGap: 10),
        isNot(const AnchoredPopupStyle(width: 300)),
      );
    });

    test('is never negative', () {
      expect(
        () => AnchoredPopupStyle(width: 300, edgeGap: -1),
        throwsAssertionError,
      );
    });
  });
}
