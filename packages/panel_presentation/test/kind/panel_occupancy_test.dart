import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

void main() {
  group('PanelOccupancy', () {
    test('zero takes no space on either axis', () {
      expect(PanelOccupancy.zero.bottom, 0);
      expect(PanelOccupancy.zero.inlineEnd, 0);
      expect(PanelOccupancy.zero.isZero, isTrue);
    });

    test('compares by value', () {
      expect(
        const PanelOccupancy(bottom: 300, inlineEnd: 0),
        const PanelOccupancy(bottom: 300, inlineEnd: 0),
      );
      expect(
        const PanelOccupancy(bottom: 300).hashCode,
        const PanelOccupancy(bottom: 300).hashCode,
      );
      expect(
        const PanelOccupancy(bottom: 300),
        isNot(const PanelOccupancy(bottom: 301)),
      );
      expect(
        const PanelOccupancy(inlineEnd: 320),
        isNot(const PanelOccupancy(bottom: 320)),
      );
    });

    test('rejects a negative extent', () {
      expect(() => PanelOccupancy(bottom: -1), throwsAssertionError);
      expect(() => PanelOccupancy(inlineEnd: -1), throwsAssertionError);
    });

    test('is not zero when either axis is taken', () {
      expect(const PanelOccupancy(bottom: 1).isZero, isFalse);
      expect(const PanelOccupancy(inlineEnd: 1).isZero, isFalse);
    });
  });

  group('PanelPresentation', () {
    test('names are stable, distinct identifiers of the three kinds', () {
      const kinds = <PanelPresentation>[
        KeyboardReplacement(),
        AnchoredPopup(),
        Docked(),
      ];
      expect(kinds.map((k) => k.name), [
        'keyboardReplacement',
        'anchoredPopup',
        'docked',
      ]);
    });

    test('compares by kind', () {
      expect(const Docked(), const Docked());
      expect(const Docked().hashCode, const Docked().hashCode);
      expect(const Docked(), isNot(const AnchoredPopup()));
    });

    test('switches exhaustively', () {
      String describe(PanelPresentation kind) => switch (kind) {
        KeyboardReplacement() => 'bottom slot',
        AnchoredPopup() => 'popup',
        Docked() => 'section',
      };
      expect(describe(const AnchoredPopup()), 'popup');
    });
  });

  group('PanelVisibility', () {
    test('hidden has no kind and is neither visible nor moving', () {
      const state = PanelVisibility.hidden;
      expect(state.kind, isNull);
      expect(state.isVisible, isFalse);
      expect(state.isMoving, isFalse);
    });

    test('showing and hiding are visible and moving', () {
      for (final state in <PanelVisibility>[
        const PanelVisibility.showing(Docked()),
        const PanelVisibility.hiding(Docked()),
      ]) {
        expect(state.kind, const Docked());
        expect(state.isVisible, isTrue);
        expect(state.isMoving, isTrue);
      }
    });

    test('shown is visible and at rest', () {
      const state = PanelVisibility.shown(AnchoredPopup());
      expect(state.isVisible, isTrue);
      expect(state.isMoving, isFalse);
    });

    test('compares by phase, kind and hand-off request', () {
      expect(
        const PanelVisibility.hiding(Docked(), waitForIme: true),
        const PanelVisibility.hiding(Docked(), waitForIme: true),
      );
      expect(
        const PanelVisibility.hiding(Docked(), waitForIme: true),
        isNot(const PanelVisibility.hiding(Docked())),
      );
      expect(
        const PanelVisibility.shown(Docked()),
        isNot(const PanelVisibility.showing(Docked())),
      );
      expect(
        const PanelVisibility.shown(Docked()),
        isNot(const PanelVisibility.shown(AnchoredPopup())),
      );
    });

    test('withKind keeps the phase and swaps the kind', () {
      expect(
        const PanelVisibility.showing(Docked()).withKind(const AnchoredPopup()),
        const PanelVisibility.showing(AnchoredPopup()),
      );
      expect(
        const PanelVisibility.hiding(
          Docked(),
          waitForIme: true,
        ).withKind(const AnchoredPopup()),
        const PanelVisibility.hiding(AnchoredPopup(), waitForIme: true),
      );
      expect(
        PanelVisibility.hidden.withKind(const Docked()),
        PanelVisibility.hidden,
      );
    });

    test('switches exhaustively', () {
      String describe(PanelVisibility state) => switch (state) {
        PanelVisibility$Hidden() => 'hidden',
        PanelVisibility$Showing() => 'showing',
        PanelVisibility$Shown() => 'shown',
        PanelVisibility$Hiding() => 'hiding',
      };
      expect(describe(PanelVisibility.hidden), 'hidden');
      expect(describe(const PanelVisibility.hiding(Docked())), 'hiding');
    });
  });
}
