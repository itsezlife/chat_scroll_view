/// Content keys and descriptors as the media core reads them.
///
/// **Seams:** `ContentKeyMedia`, `MediaKeyContent`, `ContentDescriptorMedia`
/// and `ContentMediaResolver` (also against the core's `MediaResolver`
/// contract).
library;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

const _sticker = ContentDescriptor(
  key: ContentKey.document('5368'),
  semanticKind: SemanticKind.sticker,
  mediaForm: MediaForm.vectorAnimation,
  animated: true,
  size: ContentSize(512, 512),
  thumbnail: ThumbnailRef('thumb-5368'),
);

const _gif = ContentDescriptor(
  key: ContentKey.external('result-9'),
  semanticKind: SemanticKind.gif,
  mediaForm: MediaForm.video,
  animated: true,
);

const _emoji = ContentDescriptor(
  key: ContentKey.unicode('\u{1F44D}'),
  semanticKind: SemanticKind.unicodeEmoji,
  mediaForm: MediaForm.glyph,
);

void main() {
  group('media keys', () {
    test('a document is a remote key with its id', () {
      expect(
        const ContentKey.document('giphy:abc').mediaKey,
        const MediaKey.remote('giphy:abc'),
      );
    });

    test('external content and glyphs are external keys apart', () {
      const external = ContentKey.external('unicode:1F44D');
      const glyph = ContentKey.unicode('\u{1F44D}');

      expect(external.mediaKey, isNot(glyph.mediaKey));
      expect(glyph.mediaKey, const MediaKey.external('unicode:1F44D'));
    });

    test('every content key comes back from its media key', () {
      for (final key in const [
        ContentKey.document('5368'),
        ContentKey.document('giphy:abc'),
        ContentKey.external('https://example.com/a?b=c'),
        ContentKey.unicode('\u{1F469}\u{200D}\u{1F4BB}'),
      ]) {
        expect(key.mediaKey.contentKey, key);
      }
    });

    test('media the chat never names has no content key', () {
      expect(
        MediaKey.local('3f2a1c4e-0b5d-4e6f-8a9b-0c1d2e3f4a5b').contentKey,
        isNull,
      );
      expect(const MediaKey.external('not a content key').contentKey, isNull);
      expect(const MediaKey.external('document:5').contentKey, isNull);
    });
  });

  group('media descriptors', () {
    test('carry the key, kind, motion, size and thumbnail', () {
      expect(
        _sticker.mediaDescriptor,
        const MediaDescriptor(
          key: MediaKey.remote('5368'),
          kind: MediaKind.vectorAnimation,
          animated: true,
          dimensions: MediaDimensions(512, 512),
          thumbnail: MediaThumbnailRef('thumb-5368'),
        ),
      );
    });

    test('a glyph has none: the core never decodes it', () {
      expect(_emoji.mediaDescriptor, isNull);
    });
  });

  MediaResolverContract.run(
    () async => MediaResolverHarness(
      resolver: ContentMediaResolver(FakeContentResolver([_sticker, _gif])),
      known: [_sticker.mediaDescriptor!, _gif.mediaDescriptor!],
      unknownKey: const MediaKey.remote('missing'),
    ),
  );

  group('ContentMediaResolver', () {
    test('asks the chat by content key, once per batch', () async {
      final content = FakeContentResolver([_sticker, _gif]);

      await ContentMediaResolver(
        content,
      ).resolve([_sticker.key.mediaKey, _gif.key.mediaKey]);

      expect(content.requests, [
        [_sticker.key, _gif.key],
      ]);
    });

    test('leaves out glyphs and keys the chat never names', () async {
      final content = FakeContentResolver([_emoji]);

      final result = await ContentMediaResolver(content).resolve([
        _emoji.key.mediaKey,
        const MediaKey.external('not a content key'),
      ]);

      expect(result, isEmpty);
    });
  });
}
