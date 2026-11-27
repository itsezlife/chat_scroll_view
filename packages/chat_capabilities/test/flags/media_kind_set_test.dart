import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  const photo = MediaKind.photo;
  const voice = MediaKind.voice;

  group('bit order (the serialised form)', () {
    test('pins each kind to its bit', () {
      expect(
        {
          for (final kind in MediaKind.values)
            kind.name: MediaKindSet.of([kind]).bits,
        },
        {
          'photo': 1 << 0,
          'video': 1 << 1,
          'animation': 1 << 2,
          'file': 1 << 3,
          'audio': 1 << 4,
          'voice': 1 << 5,
          'roundVideo': 1 << 6,
        },
      );
    });

    test('all holds every kind and nothing else', () {
      expect(MediaKindSet.all.bits, (1 << 7) - 1);
      expect(MediaKindSet.all, MediaKindSet.of(MediaKind.values));
      expect(MediaKindSet.none.bits, 0);
    });

    test('stays within 31 flags, a JavaScript small integer', () {
      expect(MediaKind.values.length, lessThanOrEqualTo(31));
      expect(MediaKindSet.all.bits, lessThan(1 << 31));
    });
  });

  group('set operations', () {
    final photoVideo = MediaKindSet.of([photo, MediaKind.video]);

    test('contains, isEmpty', () {
      expect(photoVideo.contains(photo), isTrue);
      expect(photoVideo.contains(voice), isFalse);
      expect(MediaKindSet.none.isEmpty, isTrue);
      expect(photoVideo.isEmpty, isFalse);
    });

    test('union, intersection and without', () {
      final voiceSet = MediaKindSet.of([voice]);
      expect((photoVideo | voiceSet).kinds, [photo, MediaKind.video, voice]);
      expect(
        photoVideo & MediaKindSet.of([photo, voice]),
        MediaKindSet.of([photo]),
      );
      final rest = MediaKindSet.all.without(photoVideo);
      expect(rest.contains(photo), isFalse);
      expect(rest.kinds, hasLength(MediaKind.values.length - 2));
    });

    test('iterates in bit order whatever the build order', () {
      expect(MediaKindSet.of([MediaKind.roundVideo, voice, photo]).kinds, [
        photo,
        voice,
        MediaKind.roundVideo,
      ]);
      expect(MediaKindSet.all.kinds, MediaKind.values);
    });

    test('is value-equal', () {
      expect(MediaKindSet.of([photo, voice]), MediaKindSet.of([voice, photo]));
      expect(
        MediaKindSet.of([photo]).hashCode,
        MediaKindSet.of([photo]).hashCode,
      );
    });
  });

  group('fromBits', () {
    test('round-trips the serialised form', () {
      final set = MediaKindSet.of([MediaKind.file, voice]);
      expect(MediaKindSet.fromBits(set.bits), set);
    });

    test('ignores unknown bits and keeps the known ones', () {
      final decoded = MediaKindSet.fromBits((1 << 0) | (1 << 5) | (1 << 20));
      expect(decoded.kinds, [photo, voice]);
      expect(decoded.bits, (1 << 0) | (1 << 5));
    });
  });
}
