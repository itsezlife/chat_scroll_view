import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatBodyPartRole, ChatDiagnosablePart;
import 'package:content_model/content_model.dart' show MediaItemId;
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

const _item = MediaItemId('p1');

// Exhaustive without a default: a new variant breaks this at compile time.
String _describe(MessageMediaHitPart part) => switch (part) {
  MediaHitPart(:final part) => 'media ${part.name}',
  LinkPreviewHitPart(:final zone) => 'card ${zone.name}',
};

void main() {
  group('MediaHitPart', () {
    test('is equal by item and part', () {
      expect(
        const MessageMediaHitPart.media(_item, part: MediaPart.content),
        const MediaHitPart(_item, part: MediaPart.content),
      );
      expect(
        const MediaHitPart(_item, part: MediaPart.content).hashCode,
        const MediaHitPart(_item, part: MediaPart.content).hashCode,
      );
      expect(
        const MediaHitPart(_item, part: MediaPart.content),
        isNot(const MediaHitPart(_item, part: MediaPart.status)),
      );
      expect(
        const MediaHitPart(_item, part: MediaPart.content),
        isNot(const MediaHitPart(MediaItemId('p2'), part: MediaPart.content)),
      );
    });

    test('only the options affordance opens the menu', () {
      expect(
        {
          for (final part in MediaPart.values)
            part: MediaHitPart(_item, part: part).role,
        },
        {
          MediaPart.content: ChatBodyPartRole.activate,
          MediaPart.status: ChatBodyPartRole.activate,
          MediaPart.spoiler: ChatBodyPartRole.activate,
          MediaPart.options: ChatBodyPartRole.menu,
        },
      );
    });

    test('names its part and item for diagnostics, nothing else', () {
      const ChatDiagnosablePart part = MediaHitPart(
        _item,
        part: MediaPart.status,
      );
      expect(part.diagnosticName, 'status');
      expect(part.diagnosticItemId, _item.toString());
    });
  });

  group('LinkPreviewHitPart', () {
    test('is equal by message and zone', () {
      expect(
        const MessageMediaHitPart.linkPreview(7, zone: LinkPreviewZone.body),
        const LinkPreviewHitPart(7, zone: LinkPreviewZone.body),
      );
      expect(
        const LinkPreviewHitPart(7, zone: LinkPreviewZone.body),
        isNot(const LinkPreviewHitPart(7, zone: LinkPreviewZone.button)),
      );
      expect(
        const LinkPreviewHitPart(7, zone: LinkPreviewZone.body),
        isNot(const LinkPreviewHitPart(8, zone: LinkPreviewZone.body)),
      );
    });

    test('every zone is an activate part and names no item', () {
      for (final zone in LinkPreviewZone.values) {
        final part = LinkPreviewHitPart(7, zone: zone);
        expect(part.role, ChatBodyPartRole.activate);
        expect(part.diagnosticName, zone.name);
        expect(part.diagnosticItemId, isNull);
      }
    });
  });

  test('the pair is never equal across variants and is matched '
      'exhaustively', () {
    const media = MediaHitPart(_item, part: MediaPart.content);
    const card = LinkPreviewHitPart(7, zone: LinkPreviewZone.button);
    expect(media, isNot(card));
    expect(_describe(media), 'media content');
    expect(_describe(card), 'card button');
  });
}
