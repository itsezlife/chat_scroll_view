import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  RichClipboardContract.run(() {
    final clipboard = FakeRichClipboard();
    return RichClipboardHarness(
      clipboard: clipboard,
      putPlainText: (text) async => clipboard.putPlainText(text),
      putImage: (png) async =>
          clipboard.putMedia([PastedMedia.bytes(png, mimeType: 'image/png')]),
    );
  });

  group('FakeRichClipboard', () {
    test(
      'fails every call while failure is set, and changes nothing',
      () async {
        final clipboard = FakeRichClipboard();
        await clipboard.write(const RichText.plain('kept'));
        clipboard.failure = Exception('no clipboard');

        await expectLater(
          clipboard.write(const RichText.plain('lost')),
          throwsException,
        );
        await expectLater(clipboard.read(), throwsException);

        clipboard.failure = null;
        expect((await clipboard.read())!.plain, 'kept');
      },
    );

    test('counts the writes', () async {
      final clipboard = FakeRichClipboard();
      await clipboard.write(const RichText.plain('a'));
      await clipboard.write(const RichText.plain('b'));

      expect(clipboard.writeCount, 2);
    });
  });
}
