import 'dart:async';
import 'dart:typed_data';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [RichClipboard] under test, with what the contract cannot do through the
/// seam.
final class RichClipboardHarness {
  /// Creates a harness around [clipboard].
  const RichClipboardHarness({
    required this.clipboard,
    required this.putPlainText,
    this.putImage,
  });

  /// The clipboard under test.
  final RichClipboard clipboard;

  /// Puts plain text on the same clipboard the way an app with no rich form
  /// does (for a platform adapter, through the platform's plain text API).
  final Future<void> Function(String text) putPlainText;

  /// Puts a PNG image on the same clipboard as another app copying one does,
  /// or null when the test cannot (a platform adapter whose test has no way
  /// to place an image); the media tests are then skipped.
  final Future<void> Function(Uint8List png)? putImage;
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

      test('reads the text with no media after text was written', () async {
        const text = RichText.plain('words');
        await clipboard.write(text);

        final contents = await clipboard.readWithMedia();

        expect(contents.text!.richOrPlain, text);
        expect(contents.media, isEmpty);
      });

      test('reads an image another app copied as media', () async {
        final putImage = harness.putImage;
        if (putImage == null) {
          markTestSkipped('The harness cannot put an image on the clipboard.');
          return;
        }
        await putImage(_onePixelPng);

        final media = (await clipboard.readWithMedia()).media;

        // Data, or a file the adapter saved it to: what a mobile adapter does
        // rather than send the data whole through the platform channel.
        expect(media, hasLength(1));
        expect(
          media.single,
          anyOf(
            isA<PastedMedia$Bytes>()
                .having((m) => m.mimeType, 'mimeType', startsWith('image/'))
                .having((m) => m.bytes, 'bytes', isNotEmpty),
            isA<PastedMedia$File>()
                .having((m) => m.mimeType, 'mimeType', startsWith('image/'))
                .having((m) => m.path, 'path', isNotEmpty),
          ),
        );
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

/// A one-pixel PNG, for harnesses that put an image on the clipboard.
final Uint8List _onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
