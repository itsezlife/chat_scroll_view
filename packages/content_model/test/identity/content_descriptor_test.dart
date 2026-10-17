import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  const key = ContentKey.document('1');

  group('SemanticKind', () {
    test('decodes every written value back to itself', () {
      for (final kind in SemanticKind.values) {
        expect(SemanticKind.fromValue(kind.value), kind);
      }
    });

    test('falls back to unknown for a missing or unrecognised host value', () {
      expect(SemanticKind.fromValue(null), SemanticKind.unknown);
      expect(SemanticKind.fromValue(''), SemanticKind.unknown);
      expect(SemanticKind.fromValue('hologram'), SemanticKind.unknown);
      expect(SemanticKind.fromValue('Sticker'), SemanticKind.unknown);
    });

    test('has stable written values independent of the Dart names', () {
      expect(SemanticKind.unicodeEmoji.value, 'unicode_emoji');
      expect(SemanticKind.customEmoji.value, 'custom_emoji');
      expect(SemanticKind.sticker.value, 'sticker');
      expect(SemanticKind.mask.value, 'mask');
      expect(SemanticKind.gif.value, 'gif');
      expect(SemanticKind.unknown.value, 'unknown');
    });

    test('has distinct written values', () {
      final values = SemanticKind.values.map((kind) => kind.value);

      expect(values.toSet(), hasLength(SemanticKind.values.length));
    });
  });

  group('MediaForm', () {
    test('decodes every written value back to itself', () {
      for (final form in MediaForm.values) {
        expect(MediaForm.fromValue(form.value), form);
      }
    });

    test('falls back to unknown for a missing or unrecognised host value', () {
      expect(MediaForm.fromValue(null), MediaForm.unknown);
      expect(MediaForm.fromValue('holographic'), MediaForm.unknown);
    });

    test('has stable written values independent of the Dart names', () {
      expect(MediaForm.glyph.value, 'glyph');
      expect(MediaForm.still.value, 'still');
      expect(MediaForm.vectorAnimation.value, 'vector_animation');
      expect(MediaForm.animatedImage.value, 'animated_image');
      expect(MediaForm.video.value, 'video');
      expect(MediaForm.unknown.value, 'unknown');
    });

    test('has distinct written values', () {
      final values = MediaForm.values.map((form) => form.value);

      expect(values.toSet(), hasLength(MediaForm.values.length));
    });
  });

  group('ThumbnailRef', () {
    test('is equal by its opaque value', () {
      expect(const ThumbnailRef('t'), const ThumbnailRef('t'));
      expect(
        const ThumbnailRef('t').hashCode,
        const ThumbnailRef('t').hashCode,
      );
      expect(const ThumbnailRef('t'), isNot(const ThumbnailRef('u')));
    });
  });

  group('ContentSize', () {
    test('is a value of its width and height', () {
      expect(const ContentSize(512, 256), const ContentSize(512, 256));
      expect(
        const ContentSize(512, 256).hashCode,
        const ContentSize(512, 256).hashCode,
      );
      expect(const ContentSize(512, 256), isNot(const ContentSize(256, 512)));
      expect(const ContentSize(512, 256).width, 512);
      expect(const ContentSize(512, 256).height, 256);
    });

    test('rejects a non-positive dimension', () {
      final zero = int.parse('0');

      expect(() => ContentSize(zero, 1), throwsA(isA<AssertionError>()));
      expect(() => ContentSize(1, -zero - 1), throwsA(isA<AssertionError>()));
    });
  });

  group('ContentDescriptor', () {
    test('defaults every fact to the safe, unknown, plain value', () {
      const descriptor = ContentDescriptor(key: key);

      expect(descriptor.key, key);
      expect(descriptor.semanticKind, SemanticKind.unknown);
      expect(descriptor.mediaForm, MediaForm.unknown);
      expect(descriptor.animated, isFalse);
      expect(descriptor.tintable, isFalse);
      expect(descriptor.locked, isFalse);
      expect(descriptor.size, isNull);
      expect(descriptor.thumbnail, isNull);
      expect(descriptor.spokenName, isNull);
      expect(descriptor.shortcode, isNull);
    });

    test('is a value of all its fields', () {
      const full = ContentDescriptor(
        key: key,
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.vectorAnimation,
        animated: true,
        tintable: true,
        locked: true,
        size: ContentSize(512, 512),
        thumbnail: ThumbnailRef('thumb-1'),
        spokenName: 'waving hand',
        shortcode: ':wave:',
      );
      const same = ContentDescriptor(
        key: key,
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.vectorAnimation,
        animated: true,
        tintable: true,
        locked: true,
        size: ContentSize(512, 512),
        thumbnail: ThumbnailRef('thumb-1'),
        spokenName: 'waving hand',
        shortcode: ':wave:',
      );

      expect(full, same);
      expect(full.hashCode, same.hashCode);
    });

    test('differs when any single field differs', () {
      const base = ContentDescriptor(
        key: key,
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.still,
        size: ContentSize(1, 1),
        thumbnail: ThumbnailRef('t'),
        spokenName: 'n',
      );
      const variants = <ContentDescriptor>[
        ContentDescriptor(
          key: ContentKey.document('2'),
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.mask,
          mediaForm: MediaForm.still,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.video,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          animated: true,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          tintable: true,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          locked: true,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          size: ContentSize(2, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('u'),
          spokenName: 'n',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'm',
        ),
        ContentDescriptor(
          key: key,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          size: ContentSize(1, 1),
          thumbnail: ThumbnailRef('t'),
          spokenName: 'n',
          shortcode: ':n:',
        ),
      ];

      for (final variant in variants) {
        expect(variant, isNot(base));
      }
    });

    test('an unspecified fact is not equal to a specified one', () {
      expect(
        const ContentDescriptor(key: key),
        isNot(const ContentDescriptor(key: key, spokenName: 'x')),
      );
    });

    test('keeps a unicode emoji and a sticker distinguishable by kind, '
        'not by key', () {
      const unicode = ContentKey.unicode('\u{1F44B}');
      const asEmoji = ContentDescriptor(
        key: unicode,
        semanticKind: SemanticKind.unicodeEmoji,
        mediaForm: MediaForm.glyph,
      );
      const asSticker = ContentDescriptor(
        key: unicode,
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.still,
      );

      expect(asEmoji.key, asSticker.key);
      expect(asEmoji, isNot(asSticker));
    });

    test('toString names the key and the two axes', () {
      const descriptor = ContentDescriptor(
        key: key,
        semanticKind: SemanticKind.gif,
        mediaForm: MediaForm.video,
      );

      expect(
        descriptor.toString(),
        'ContentDescriptor(ContentKey.document(1), gif, video)',
      );
    });
  });
}
