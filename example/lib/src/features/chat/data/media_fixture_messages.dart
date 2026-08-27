import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:message_media/message_media.dart';

/// Demo fixture catalog: text, single photo/video, and multi-id albums.
///
/// Ids are dense `0..length-1`. Album members share a `groupId` and remain
/// distinct Message IDs. Placeholders only — no network.
const int kMediaFixtureAlbumGroupId = 9001;

/// Second album (square members → side-by-side mosaic at typical widths).
const int kMediaFixtureSideBySideGroupId = 9002;

/// Ordered fixture messages for the media-layout demo chat.
///
/// [baseTime] anchors id `0`; each subsequent id adds one minute.
List<UserChatMessage> buildMediaFixtureMessages({DateTime? baseTime}) {
  final t0 = baseTime ?? DateTime(2026, 8, 1, 12);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  return [
    UserChatMessage(
      id: 0,
      sender: 'Alice',
      createdAt: at(0),
      updatedAt: at(0),
      content: 'Media layout fixtures — singles and albums.',
    ),
    UserChatMessage(
      id: 1,
      sender: 'Alice',
      createdAt: at(1),
      updatedAt: at(1),
      content: '',
      aspectRatio: 16 / 9,
      mediaKind: MediaKind.photo,
      caption: 'Single photo 16∶9',
    ),
    UserChatMessage(
      id: 2,
      sender: 'Bob',
      createdAt: at(2),
      updatedAt: at(2),
      content: '',
      aspectRatio: 9 / 16,
      mediaKind: MediaKind.video,
      caption: 'Single video 9∶16',
    ),
    // N=2 wide → stacked mosaic (full-width cells).
    UserChatMessage(
      id: 3,
      sender: 'Hixie',
      createdAt: at(3),
      updatedAt: at(3),
      content: '',
      groupId: kMediaFixtureAlbumGroupId,
      aspectRatio: 2,
      mediaKind: MediaKind.photo,
    ),
    UserChatMessage(
      id: 4,
      sender: 'Hixie',
      createdAt: at(4),
      updatedAt: at(4),
      content: '',
      groupId: kMediaFixtureAlbumGroupId,
      aspectRatio: 2,
      mediaKind: MediaKind.photo,
      caption: 'Stacked album caption',
    ),
    UserChatMessage(
      id: 5,
      sender: 'Alice',
      createdAt: at(5),
      updatedAt: at(5),
      content: 'Selection still targets one Message ID per group row.',
    ),
    // N=2 square → side-by-side mosaic (half-width cells).
    UserChatMessage(
      id: 6,
      sender: 'Bob',
      createdAt: at(6),
      updatedAt: at(6),
      content: '',
      groupId: kMediaFixtureSideBySideGroupId,
      aspectRatio: 1,
      mediaKind: MediaKind.photo,
    ),
    UserChatMessage(
      id: 7,
      sender: 'Bob',
      createdAt: at(7),
      updatedAt: at(7),
      content: '',
      groupId: kMediaFixtureSideBySideGroupId,
      aspectRatio: 1,
      mediaKind: MediaKind.video,
    ),
  ];
}
