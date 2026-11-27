import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  group('MediaItemId', () {
    // Built at run time, so equality is by value, not const canonicalisation.
    String runtime(String value) => [value].join();

    test('host ids are equal by value', () {
      expect(MediaItemId(runtime('a1')), const MediaItemId('a1'));
      expect(
        MediaItemId(runtime('a1')).hashCode,
        const MediaItemId('a1').hashCode,
      );
      expect(const MediaItemId('a1'), isNot(const MediaItemId('a2')));
    });

    test('linkPreviewOf is stable across calls', () {
      const first = MediaItemId.linkPreviewOf(
        'm1',
        slot: LinkPreviewMediaSlot.photo,
      );
      final second = MediaItemId.linkPreviewOf(
        runtime('m1'),
        slot: LinkPreviewMediaSlot.photo,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.toString(), second.toString());
    });

    test('linkPreviewOf differs by slot and by message', () {
      const photo = MediaItemId.linkPreviewOf(
        'm1',
        slot: LinkPreviewMediaSlot.photo,
      );
      const media = MediaItemId.linkPreviewOf(
        'm1',
        slot: LinkPreviewMediaSlot.media,
      );
      const otherMessage = MediaItemId.linkPreviewOf(
        'm2',
        slot: LinkPreviewMediaSlot.photo,
      );

      expect(photo, isNot(media));
      expect(photo, isNot(otherMessage));
      expect(photo.toString(), isNot(media.toString()));
      expect(photo.toString(), isNot(otherMessage.toString()));
    });

    test('a link preview id is never a host id, whatever the host issues', () {
      const preview = MediaItemId.linkPreviewOf(
        'm1',
        slot: LinkPreviewMediaSlot.photo,
      );
      // A host id spelled as the preview's string form, or as its message id.
      final lookalike = MediaItemId(preview.toString());

      expect(lookalike, isNot(preview));
      expect(lookalike.toString(), isNot(preview.toString()));
      expect(const MediaItemId('m1'), isNot(preview));
    });

    final ids = <MediaItemId>[
      const MediaItemId('a1'),
      const MediaItemId('with:colons:inside'),
      const MediaItemId('preview:photo:m1'),
      const MediaItemId(' spaces and ünïcödé 👍 '),
      const MediaItemId.linkPreviewOf('m1', slot: LinkPreviewMediaSlot.photo),
      const MediaItemId.linkPreviewOf('m1', slot: LinkPreviewMediaSlot.media),
      const MediaItemId.linkPreviewOf(
        'chat:7:msg',
        slot: LinkPreviewMediaSlot.media,
      ),
    ];

    test('the string form round-trips host and link preview ids', () {
      for (final id in ids) {
        expect(MediaItemId.parse(id.toString()), id, reason: '$id');
        expect(MediaItemId.tryParse(id.toString()), id, reason: '$id');
      }
    });

    test('distinct ids give distinct strings', () {
      final strings = {for (final id in ids) id.toString()};

      expect(strings, hasLength(ids.length));
    });

    test('a string that is no id does not parse', () {
      for (final source in [
        '',
        'a1',
        'item:',
        'preview:photo:',
        'preview:poster:m1',
        'preview:photo',
        'other:a1',
      ]) {
        expect(MediaItemId.tryParse(source), isNull, reason: source);
        expect(
          () => MediaItemId.parse(source),
          throwsFormatException,
          reason: source,
        );
      }
      expect(MediaItemId.tryParse(null), isNull);
    });

    test('the slot has a stable value', () {
      expect(LinkPreviewMediaSlot.photo.value, 'photo');
      expect(LinkPreviewMediaSlot.media.value, 'media');
    });
  });

  group('MediaItemKind', () {
    test('the built-in kinds have stable values', () {
      expect(MediaItemKind.photo.value, 'photo');
      expect(MediaItemKind.video.value, 'video');
      expect(MediaItemKind.animation.value, 'animation');
      expect(MediaItemKind.file.value, 'file');
    });

    test('fromValue reads every built-in kind back', () {
      for (final kind in MediaItemKind.builtIns) {
        expect(MediaItemKind.fromValue(kind.value), same(kind));
        expect(kind.isCustom, isFalse);
      }
    });

    test('an unknown value round-trips as custom with its tag', () {
      final kind = MediaItemKind.fromValue('voice_note');

      expect(kind.isCustom, isTrue);
      expect(kind.value, 'voice_note');
      expect(kind, const MediaItemKind.custom('voice_note'));
      expect(kind.hashCode, const MediaItemKind.custom('voice_note').hashCode);
      expect(MediaItemKind.fromValue(kind.value), kind);
      expect(kind, isNot(const MediaItemKind.custom('round_video')));
    });

    test('a missing value is a file', () {
      expect(MediaItemKind.fromValue(null), MediaItemKind.file);
      expect(MediaItemKind.fromValue(''), MediaItemKind.file);
    });

    group('fromDescriptor', () {
      const key = ContentKey.document('d1');

      MediaItemKind kindOf({
        MediaForm form = MediaForm.unknown,
        SemanticKind semantic = SemanticKind.unknown,
        String? mime,
      }) => MediaItemKind.fromDescriptor(
        ContentDescriptor(
          key: key,
          mediaForm: form,
          semanticKind: semantic,
          mimeType: mime,
        ),
      );

      final table = <(String, MediaItemKind, MediaItemKind)>[
        ('still image', kindOf(form: MediaForm.still), MediaItemKind.photo),
        (
          'vector image',
          kindOf(form: MediaForm.vectorImage),
          MediaItemKind.photo,
        ),
        ('video', kindOf(form: MediaForm.video), MediaItemKind.video),
        (
          'animated image',
          kindOf(form: MediaForm.animatedImage),
          MediaItemKind.animation,
        ),
        (
          'GIF sent as a video clip',
          kindOf(form: MediaForm.video, semantic: SemanticKind.gif),
          MediaItemKind.animation,
        ),
        ('image mime', kindOf(mime: 'image/jpeg'), MediaItemKind.photo),
        ('GIF mime', kindOf(mime: 'image/gif'), MediaItemKind.animation),
        (
          'mime in another case, with parameters',
          kindOf(mime: ' Image/GIF; charset=binary'),
          MediaItemKind.animation,
        ),
        ('video mime', kindOf(mime: 'video/mp4'), MediaItemKind.video),
        ('audio mime', kindOf(mime: 'audio/ogg'), MediaItemKind.file),
        (
          'application mime',
          kindOf(mime: 'application/pdf'),
          MediaItemKind.file,
        ),
        ('text mime', kindOf(mime: 'text/plain'), MediaItemKind.file),
        ('malformed mime', kindOf(mime: 'nonsense'), MediaItemKind.file),
        ('no form and no mime', kindOf(), MediaItemKind.file),
        (
          'a known form wins over the mime',
          kindOf(form: MediaForm.still, mime: 'application/octet-stream'),
          MediaItemKind.photo,
        ),
        (
          'a form with no media default falls back to the mime',
          kindOf(form: MediaForm.vectorAnimation, mime: 'video/webm'),
          MediaItemKind.video,
        ),
      ];

      for (final (name, actual, expected) in table) {
        test(name, () => expect(actual, expected));
      }
    });
  });

  group('MediaItem', () {
    const photo = ContentDescriptor(
      key: ContentKey.document('d1'),
      mediaForm: MediaForm.still,
      mimeType: 'image/png',
    );

    test('the kind defaults from the descriptor', () {
      final item = MediaItem(id: const MediaItemId('a1'), descriptor: photo);

      expect(item.kind, MediaItemKind.photo);
      expect(item.spoiler, isFalse);
    });

    test("the host's kind wins: a photo sent as a file is a file", () {
      final item = MediaItem(
        id: const MediaItemId('a1'),
        descriptor: photo,
        kind: MediaItemKind.file,
      );

      expect(item.kind, MediaItemKind.file);
    });

    test('is equal by value', () {
      MediaItem item({bool spoiler = false, String id = 'a1'}) =>
          MediaItem(id: MediaItemId(id), descriptor: photo, spoiler: spoiler);

      expect(item(), item());
      expect(item().hashCode, item().hashCode);
      expect(item(), isNot(item(spoiler: true)));
      expect(item(), isNot(item(id: 'a2')));
      expect(
        item(),
        isNot(
          MediaItem(
            id: const MediaItemId('a1'),
            descriptor: photo,
            kind: MediaItemKind.file,
          ),
        ),
      );
      expect(
        item(),
        isNot(
          MediaItem(
            id: const MediaItemId('a1'),
            descriptor: photo.copyWith(mimeType: 'image/jpeg'),
          ),
        ),
      );
    });
  });
}
