import 'package:meta/meta.dart';

/// One category of the emoji grid: an id, and the catalogue groups it holds
/// one after the other.
///
/// The catalogue's groups are Unicode's (smileys and people apart, flags of
/// their own); the grid a user knows is a chat client's, and the reference
/// client folds them into seven categories. A section is that fold: the host
/// says which groups make a category, and the collection source lists one
/// collection per section that holds a group the catalogue has.
@immutable
final class EmojiSection {
  /// A section named [id] holding the entries of [groupIds], in that order.
  const EmojiSection(this.id, this.groupIds)
    : assert(id != '', 'a section id must not be empty');

  /// The reference client's categories: smileys and people are one, and the
  /// flags close the symbols. A group the list does not name is not lost: the
  /// collection source adds a section of its own for it.
  static const List<EmojiSection> reference = [
    EmojiSection('people', ['smileys-emotion', 'people-body']),
    EmojiSection('nature', ['animals-nature']),
    EmojiSection('food', ['food-drink']),
    EmojiSection('activity', ['activities']),
    EmojiSection('travel', ['travel-places']),
    EmojiSection('objects', ['objects']),
    EmojiSection('symbols', ['symbols', 'flags']),
  ];

  /// The id the section's collection takes (`CollectionId.category`).
  final String id;

  /// The catalogue groups it holds, in order.
  final List<String> groupIds;

  @override
  bool operator ==(Object other) =>
      other is EmojiSection &&
      other.id == id &&
      _sameGroups(other.groupIds, groupIds);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(groupIds));

  @override
  String toString() => 'EmojiSection($id)';

  static bool _sameGroups(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
