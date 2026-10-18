import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// A user the demo's `@` panel offers.
@immutable
final class ChatUser {
  /// A user with the host-resolved [id]; [username] is null for a user the
  /// panel mentions by [name].
  const ChatUser({required this.id, required this.name, this.username});

  /// The id a mention carries (`Mention(id)`).
  final String id;

  /// The display name.
  final String name;

  /// The `@name` handle, without the `@`, or null.
  final String? username;

  /// What a mention of this user reads as in the text: the handle when there
  /// is one, else the name.
  String get mentionText => username == null ? name : '@$username';
}

/// What the demo's suggestion panels draw from: a fixed set of users and
/// hashtags, standing in for the chat's members and a tag index.
///
/// A real host asks its member list and its tag source; the composer knows
/// neither (ADR 026).
abstract final class ChatDirectory {
  /// The users, as the chat's members.
  static const List<ChatUser> users = [
    ChatUser(id: 'u1', name: 'Alice Smith', username: 'alice'),
    ChatUser(id: 'u2', name: 'Alan Turing', username: 'alan'),
    ChatUser(id: 'u3', name: 'Dana Lee'),
    ChatUser(id: 'u4', name: 'Boris Ivanov', username: 'boris'),
  ];

  /// The hashtags in use.
  static const List<String> tags = ['tasks', 'tabletop', 'travel', 'design'];

  /// The most suggestions a panel offers.
  static const int limit = 8;

  /// The users whose handle or name starts with [prefix], ignoring case.
  static List<ChatUser> matchUsers(String prefix) {
    final wanted = prefix.toLowerCase();
    return [
      for (final user in users)
        if ((user.username ?? '').startsWith(wanted) ||
            user.name.toLowerCase().startsWith(wanted))
          user,
    ].take(limit).toList();
  }

  /// The hashtags that start with [prefix], ignoring case.
  static List<String> matchTags(String prefix) {
    final wanted = prefix.toLowerCase();
    return [
      for (final tag in tags)
        if (tag.startsWith(wanted)) tag,
    ].take(limit).toList();
  }

  /// Whether [id] is the id of a user of the chat: what
  /// `ComposerController.confirmMention` answers for a mention a paste brought
  /// in. The clipboard's claim about the id is never the answer (ADR 032).
  static bool knowsUser(String id) => users.any((user) => user.id == id);

  /// The text that replaces a `@` query when [user] is picked: the mention
  /// atom and a space after it.
  static RichText mention(ChatUser user) {
    final text = user.mentionText;
    return RichText('$text ', [
      Entity(0, text.length, EntityKind.mention(user.id)),
    ]);
  }

  /// The text that replaces a `#` query when [tag] is picked: the hashtag and
  /// a space after it.
  static RichText hashtag(String tag) =>
      RichText('#$tag ', [Entity(0, tag.length + 1, EntityKind.hashtag(tag))]);

  /// The query kinds the demo registers, `@` and `#`.
  static const List<ComposerQueryKind> queryKinds = [
    ComposerQueryKind(id: usernameQuery, trigger: '@'),
    ComposerQueryKind(id: hashtagQuery, trigger: '#'),
  ];

  /// The id of the `@` kind.
  static const String usernameQuery = 'username';

  /// The id of the `#` kind.
  static const String hashtagQuery = 'hashtag';
}
