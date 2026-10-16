import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  group('PanelTab', () {
    test('rejects an empty label key', () {
      expect(
        () => PanelTab(icon: ChromeIconId.emoji, labelKey: ''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('compares by icon and label key', () {
      const a = PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji');
      const b = PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji');
      const c = PanelTab(icon: ChromeIconId.gif, labelKey: 'emoji');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('PageAction', () {
    test('the backspace action repeats and resolves its spoken label', () {
      const action = PageAction.backspace();

      expect(action.id, PageAction.backspaceId);
      expect(action.icon, ChromeIconId.backspace);
      expect(action.repeatOnHold, isTrue);
      expect(action.semanticLabel(ChromeStringsPresets.english), 'Delete');
      expect(action.semanticLabel(ChromeStringsPresets.russian), isNotEmpty);
    });

    test('the search action names the search field', () {
      const action = PageAction.search();

      expect(action.id, PageAction.searchId);
      expect(action.semanticLabel(ChromeStringsPresets.english), 'Search');
    });

    test('rejects an empty id', () {
      expect(
        () => PageAction(
          id: '',
          icon: ChromeIconId.search,
          semanticLabel: (_) => 'x',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('two backspace actions are equal', () {
      expect(const PageAction.backspace(), const PageAction.backspace());
    });
  });

  group('PanelPage', () {
    test('rejects an empty id', () {
      expect(
        () => PanelPage(
          id: '',
          tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
          builder: (context, host) => const SizedBox(),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('declares nothing unless told to', () {
      final page = PanelPage(
        id: 'emoji',
        tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
        builder: (context, host) => const SizedBox(),
      );

      expect(page.capabilities.search, isFalse);
      expect(page.capabilities.topStrip, isFalse);
      expect(page.capabilities.actions, isEmpty);
    });
  });
}
