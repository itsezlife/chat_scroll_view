import 'package:chat_composer/chat_composer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? hint(TargetPlatform platform, ComposerMenuAction action) =>
      ComposerMenuHints.forPlatform(platform).of(action);

  group('Windows and Linux spell keys with Ctrl', () {
    test('the standard edit rows', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        expect(hint(platform, ComposerMenuAction.undo), 'Ctrl+Z');
        expect(hint(platform, ComposerMenuAction.cut), 'Ctrl+X');
        expect(hint(platform, ComposerMenuAction.copy), 'Ctrl+C');
        expect(hint(platform, ComposerMenuAction.paste), 'Ctrl+V');
        expect(hint(platform, ComposerMenuAction.selectAll), 'Ctrl+A');
      }
    });

    test('redo is Ctrl+Y on Windows and Ctrl+Shift+Z on Linux', () {
      expect(hint(TargetPlatform.windows, ComposerMenuAction.redo), 'Ctrl+Y');
      expect(
        hint(TargetPlatform.linux, ComposerMenuAction.redo),
        'Ctrl+Shift+Z',
      );
    });

    test('the formatting rows carry the reference client\'s keys', () {
      const expected = {
        ComposerMenuAction.bold: 'Ctrl+B',
        ComposerMenuAction.italic: 'Ctrl+I',
        ComposerMenuAction.underline: 'Ctrl+U',
        ComposerMenuAction.strikethrough: 'Ctrl+Shift+X',
        ComposerMenuAction.quote: 'Ctrl+Shift+.',
        ComposerMenuAction.monospace: 'Ctrl+Shift+M',
        ComposerMenuAction.spoiler: 'Ctrl+Shift+P',
        ComposerMenuAction.createLink: 'Ctrl+K',
        ComposerMenuAction.editLink: 'Ctrl+K',
        ComposerMenuAction.clearFormatting: 'Ctrl+Shift+N',
      };
      for (final entry in expected.entries) {
        expect(
          hint(TargetPlatform.windows, entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });
  });

  group('macOS draws the native glyph form', () {
    test('Command alone and with Shift', () {
      expect(hint(TargetPlatform.macOS, ComposerMenuAction.undo), '⌘Z');
      expect(hint(TargetPlatform.macOS, ComposerMenuAction.redo), '⇧⌘Z');
      expect(hint(TargetPlatform.macOS, ComposerMenuAction.bold), '⌘B');
      expect(hint(TargetPlatform.macOS, ComposerMenuAction.quote), '⇧⌘.');
      expect(
        hint(TargetPlatform.macOS, ComposerMenuAction.clearFormatting),
        '⇧⌘N',
      );
      expect(hint(TargetPlatform.macOS, ComposerMenuAction.createLink), '⌘K');
    });
  });

  group('rows without a key', () {
    test('Delete has none, and neither has anything the client lacks', () {
      for (final platform in TargetPlatform.values) {
        for (final action in [
          ComposerMenuAction.delete,
          ComposerMenuAction.formatting,
          ComposerMenuAction.codeBlock,
          ComposerMenuAction.removeLink,
          ComposerMenuAction.bulletList,
          ComposerMenuAction.numberedList,
        ]) {
          expect(hint(platform, action), isNull, reason: '$platform $action');
        }
      }
    });

    test('Paste as plain text has the paste key with Shift', () {
      expect(
        hint(TargetPlatform.windows, ComposerMenuAction.pastePlain),
        'Ctrl+Shift+V',
      );
      expect(hint(TargetPlatform.macOS, ComposerMenuAction.pastePlain), '⇧⌘V');
    });
  });
}
