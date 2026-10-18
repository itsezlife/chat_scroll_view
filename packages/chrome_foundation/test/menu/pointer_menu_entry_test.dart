import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PointerMenuLabel', () {
    test('a plain label has no mnemonic', () {
      final label = PointerMenuLabel.parse('Delete');
      expect(label.text, 'Delete');
      expect(label.mnemonic, isNull);
    });

    test('the letter after & is the mnemonic and the mark is dropped', () {
      final label = PointerMenuLabel.parse('&Undo');
      expect(label.text, 'Undo');
      expect(label.mnemonic, 0);
    });

    test('a mark inside the label points at its letter', () {
      final label = PointerMenuLabel.parse('Cu&t');
      expect(label.text, 'Cut');
      expect(label.mnemonic, 2);
    });

    test('&& is a literal ampersand and marks nothing', () {
      final label = PointerMenuLabel.parse('Q&&A');
      expect(label.text, 'Q&A');
      expect(label.mnemonic, isNull);
    });

    test('the first mark wins; a later one is dropped without effect', () {
      final label = PointerMenuLabel.parse('&Save &as');
      expect(label.text, 'Save as');
      expect(label.mnemonic, 0);
    });

    test('a trailing & is dropped', () {
      expect(PointerMenuLabel.parse('Edit&').text, 'Edit');
    });
  });

  group('PointerMenuItem', () {
    test('an item with an action can be chosen', () {
      expect(
        PointerMenuItem(id: 'a', label: 'A', onSelected: () {}).isEnabled,
        isTrue,
      );
    });

    test('a disabled item cannot', () {
      expect(
        PointerMenuItem(
          id: 'a',
          label: 'A',
          enabled: false,
          onSelected: () {},
        ).isEnabled,
        isFalse,
      );
    });

    test('an item with neither action nor submenu cannot', () {
      expect(const PointerMenuItem(id: 'a', label: 'A').isEnabled, isFalse);
    });

    test('an item with a submenu can be opened', () {
      expect(
        PointerMenuItem(
          id: 'a',
          label: 'A',
          submenu: [PointerMenuItem(id: 'b', label: 'B', onSelected: () {})],
        ).isEnabled,
        isTrue,
      );
    });
  });

  group('PointerMenuNavigation', () {
    final entries = <PointerMenuEntry>[
      const PointerMenuItem(id: 'off0', label: 'x'), // 0 disabled
      PointerMenuItem(id: 'a', label: 'A', onSelected: () {}), // 1
      const PointerMenuSeparator(), // 2
      PointerMenuItem(id: 'b', label: 'B', onSelected: () {}), // 3
      const PointerMenuItem(id: 'off1', label: 'y'), // 4 disabled
      PointerMenuItem(id: 'c', label: 'C', onSelected: () {}), // 5
      const PointerMenuItem(id: 'off2', label: 'z'), // 6 disabled
    ];

    test('down from nothing selects the first enabled row', () {
      expect(PointerMenuNavigation.step(entries, null, forward: true), 1);
    });

    test('up from nothing selects the last enabled row', () {
      expect(PointerMenuNavigation.step(entries, null, forward: false), 5);
    });

    test('down skips separators and disabled rows', () {
      expect(PointerMenuNavigation.step(entries, 1, forward: true), 3);
      expect(PointerMenuNavigation.step(entries, 3, forward: true), 5);
    });

    test('down from the last wraps to the first', () {
      expect(PointerMenuNavigation.step(entries, 5, forward: true), 1);
    });

    test('up from the first wraps to the last', () {
      expect(PointerMenuNavigation.step(entries, 1, forward: false), 5);
    });

    test('up skips separators and disabled rows', () {
      expect(PointerMenuNavigation.step(entries, 5, forward: false), 3);
      expect(PointerMenuNavigation.step(entries, 3, forward: false), 1);
    });

    test('a menu with nothing enabled selects nothing', () {
      const none = <PointerMenuEntry>[
        PointerMenuItem(id: 'a', label: 'A'),
        PointerMenuSeparator(),
      ];
      expect(PointerMenuNavigation.step(none, null, forward: true), isNull);
      expect(PointerMenuNavigation.step(none, null, forward: false), isNull);
    });

    test('the only enabled row stays selected', () {
      final one = <PointerMenuEntry>[
        const PointerMenuSeparator(),
        PointerMenuItem(id: 'a', label: 'A', onSelected: () {}),
      ];
      expect(PointerMenuNavigation.step(one, 1, forward: true), 1);
      expect(PointerMenuNavigation.step(one, 1, forward: false), 1);
    });

    test('first enabled', () {
      expect(PointerMenuNavigation.firstEnabled(entries), 1);
    });
  });
}
