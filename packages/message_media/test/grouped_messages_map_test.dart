import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

void main() {
  group('GroupedMessagesMap', () {
    test(
      'put two members under one groupId; query by groupId and messageId',
      () {
        final map = GroupedMessagesMap();
        addTearDown(map.dispose);

        map.put(
          groupId: 10,
          member: const GroupedMapMember(messageId: 1, aspectRatio: 1),
        );
        map.put(
          groupId: 10,
          member: const GroupedMapMember(messageId: 2, aspectRatio: 1),
        );

        final group = map.group(10);
        expect(group, isNotNull);
        expect(group!.messages.positions, hasLength(2));
        expect(group.messageIds, [1, 2]);

        expect(map.groupIdFor(1), 10);
        expect(map.groupIdFor(2), 10);
        expect(map.positionFor(1)?.pw, 400);
        expect(map.positionFor(2)?.pw, 400);
        expect(map.positionFor(99), isNull);
        expect(map.group(99), isNull);
      },
    );

    test('dispose clears entries; further puts are no-ops', () {
      final map = GroupedMessagesMap();
      map.put(
        groupId: 1,
        member: const GroupedMapMember(messageId: 1, aspectRatio: 1),
      );
      map.put(
        groupId: 1,
        member: const GroupedMapMember(messageId: 2, aspectRatio: 1),
      );
      map.dispose();

      expect(map.group(1), isNull);
      expect(map.positionFor(1), isNull);

      map.put(
        groupId: 1,
        member: const GroupedMapMember(messageId: 3, aspectRatio: 1),
      );
      expect(map.group(1), isNull);
    });

    test('remove drops mosaic when fewer than two members remain', () {
      final map = GroupedMessagesMap();
      addTearDown(map.dispose);
      map.put(
        groupId: 7,
        member: const GroupedMapMember(messageId: 1, aspectRatio: 1),
      );
      map.put(
        groupId: 7,
        member: const GroupedMapMember(messageId: 2, aspectRatio: 1),
      );
      expect(map.group(7), isNotNull);

      map.remove(2);
      expect(map.group(7), isNull);
      expect(map.groupIdFor(1), 7);
      expect(map.positionFor(1), isNull);
      expect(map.groupIdFor(2), isNull);

      map.remove(1);
      expect(map.groupIdFor(1), isNull);
      expect(map.group(7), isNull);
    });

    test('update aspect recomputes positions', () {
      final map = GroupedMessagesMap();
      addTearDown(map.dispose);
      map.put(
        groupId: 3,
        member: const GroupedMapMember(messageId: 1, aspectRatio: 1),
      );
      map.put(
        groupId: 3,
        member: const GroupedMapMember(messageId: 2, aspectRatio: 1),
      );
      expect(map.positionFor(1)?.pw, 400);

      // Wide stacked layout: both aspect 2 → full-width stacked cells.
      map.update(1, aspectRatio: 2);
      map.update(2, aspectRatio: 2);
      expect(map.positionFor(1)?.pw, 800);
      expect(map.positionFor(2)?.pw, 800);
    });

    test('put to a new groupId moves the member and recalculates both', () {
      final map = GroupedMessagesMap();
      addTearDown(map.dispose);
      map.put(
        groupId: 1,
        member: const GroupedMapMember(messageId: 1, aspectRatio: 1),
      );
      map.put(
        groupId: 1,
        member: const GroupedMapMember(messageId: 2, aspectRatio: 1),
      );
      map.put(
        groupId: 1,
        member: const GroupedMapMember(messageId: 3, aspectRatio: 1),
      );
      expect(map.group(1)!.messageIds, [1, 2, 3]);

      map.put(
        groupId: 2,
        member: const GroupedMapMember(messageId: 3, aspectRatio: 1),
      );
      map.put(
        groupId: 2,
        member: const GroupedMapMember(messageId: 4, aspectRatio: 1),
      );

      expect(map.group(1)!.messageIds, [1, 2]);
      expect(map.group(2)!.messageIds, [3, 4]);
      expect(map.groupIdFor(3), 2);
    });

    test('caption fields flow into entry when sole caption owner', () {
      final map = GroupedMessagesMap();
      addTearDown(map.dispose);
      map.put(
        groupId: 5,
        member: const GroupedMapMember(
          messageId: 1,
          aspectRatio: 1,
          hasCaption: true,
          captionText: 'hello',
          invertMedia: true,
        ),
      );
      map.put(
        groupId: 5,
        member: const GroupedMapMember(messageId: 2, aspectRatio: 1),
      );

      final entry = map.group(5)!;
      expect(entry.messages.hasCaption, isTrue);
      expect(entry.messages.captionAbove, isTrue);
      expect(entry.messages.captionIndex, 0);
      expect(entry.captionText, 'hello');
      expect(entry.captionMessageId, 1);
    });

    test('second caption clears captionIndex and captionText', () {
      final map = GroupedMessagesMap();
      addTearDown(map.dispose);
      map.put(
        groupId: 5,
        member: const GroupedMapMember(
          messageId: 1,
          aspectRatio: 1,
          hasCaption: true,
          captionText: 'a',
        ),
      );
      map.put(
        groupId: 5,
        member: const GroupedMapMember(
          messageId: 2,
          aspectRatio: 1,
          hasCaption: true,
          captionText: 'b',
        ),
      );

      final entry = map.group(5)!;
      expect(entry.messages.hasCaption, isTrue);
      expect(entry.messages.captionIndex, isNull);
      expect(entry.captionText, isNull);
    });
  });
}
