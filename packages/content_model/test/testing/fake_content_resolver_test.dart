import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

const _thumbs = ContentDescriptor(
  key: ContentKey.unicode('\u{1F44D}'),
  semanticKind: SemanticKind.unicodeEmoji,
  mediaForm: MediaForm.glyph,
);
const _sticker = ContentDescriptor(
  key: ContentKey.document('5368'),
  semanticKind: SemanticKind.sticker,
  mediaForm: MediaForm.vectorAnimation,
  animated: true,
);

void main() {
  runContentResolverContract(
    () async => ContentResolverHarness(
      resolver: FakeContentResolver([_thumbs, _sticker]),
      known: const [_thumbs, _sticker],
      unknownKey: const ContentKey.external('nobody'),
    ),
  );

  group('FakeContentResolver', () {
    test('records each batch, repeats included', () async {
      final resolver = FakeContentResolver([_thumbs]);

      await resolver.resolve([_thumbs.key, _thumbs.key]);
      await resolver.resolve(const []);

      expect(resolver.requests, [
        [_thumbs.key, _thumbs.key],
        <ContentKey>[],
      ]);
    });

    test('fails every call on request', () async {
      final resolver = FakeContentResolver([_thumbs])
        ..failure = Exception('offline');

      await expectLater(resolver.resolve([_thumbs.key]), throwsException);
      expect(resolver.requests, hasLength(1));
    });
  });
}
