import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [RichClipboard] under test, with what the contract cannot do through the
/// seam.
final class RichClipboardHarness {
  /// Creates a harness around [clipboard].
  const RichClipboardHarness({
    required this.clipboard,
    required this.putPlainText,
  });

  /// The clipboard under test.
  final RichClipboard clipboard;

  /// Puts plain text on the same clipboard the way an app with no rich form
  /// does (for a platform adapter, through the platform's plain text API).
  final Future<void> Function(String text) putPlainText;
}

/// The behaviour every [RichClipboard] must have, as a test suite to run
/// against an implementation.
abstract final class RichClipboardContract {
  /// Runs the [RichClipboard] contract against the harnesses [create]
  /// returns, one per test.
  ///
  /// Nothing assumes the clipboard starts empty, so a platform adapter can
  /// run it against the real clipboard.
  static void run(FutureOr<RichClipboardHarness> Function() create) {
    group('RichClipboard contract', () {
      late RichClipboardHarness harness;
      late RichClipboard clipboard;

      setUp(() async {
        harness = await create();
        clipboard = harness.clipboard;
      });

      test(
        'reads back every entity it was given, over the same text',
        () async {
          final text = _everyEntity();

          await clipboard.write(text);
          final read = await clipboard.read();

          expect(read!.plain, text.plain);
          expect(read.richOrPlain, text);
        },
      );

      test('reads back text with no entities as that text', () async {
        const text = RichText.plain('just words');

        await clipboard.write(text);

        expect((await clipboard.read())!.richOrPlain, text);
      });

      test('keeps characters that markup or encodings could change', () async {
        const text = RichText.plain(
          'a < b && c > "d" \'e\'\n'
          'tabs\there  two  spaces,  nbsp, '
          '\u{1F44D}\u{1F3FB} \u{1F469}‍\u{1F4BB} ф 中',
        );

        await clipboard.write(text);
        final read = await clipboard.read();

        expect(read!.plain, text.plain);
        expect(read.richOrPlain, text);
      });

      test('replaces what it held with the next write', () async {
        await clipboard.write(const RichText.plain('first'));
        await clipboard.write(const RichText.plain('second'));

        expect((await clipboard.read())!.plain, 'second');
      });

      test('reads plain text another app copied as plain text, with no rich '
          'form', () async {
        await clipboard.write(_everyEntity());
        await harness.putPlainText('from elsewhere');

        expect(await clipboard.read(), const ClipboardText('from elsewhere'));
      });
    });
  }

  // One line of styles, one quoted line, one line of atoms and a link.
  static RichText _everyEntity() {
    const styles = 'bold italic under strike hidden code';
    const quoted = 'a quoted line';
    const atoms = 'see docs, @alice and \u{1F680}';
    const plain = '$styles\n$quoted\n$atoms';
    Entity over(String part, EntityKind kind, {int from = 0}) =>
        Entity(plain.indexOf(part, from), part.length, kind);
    final atomsAt = plain.indexOf(atoms);
    return RichText(plain, [
      over('bold', EntityKind.bold),
      over('italic', EntityKind.italic),
      over('under', EntityKind.underline),
      over('strike', EntityKind.strike),
      over('hidden', EntityKind.spoiler),
      over('code', EntityKind.code),
      over(quoted, EntityKind.quote),
      over('docs', const EntityKind.link('https://example.com/docs')),
      over('@alice', const EntityKind.mention('alice'), from: atomsAt),
      over(
        '\u{1F680}',
        const EntityKind.inlineContent(ContentKey.document('rocket')),
        from: atomsAt,
      ),
    ]);
  }
}
