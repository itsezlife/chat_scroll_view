import 'dart:collection';

import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';

/// A lookup over an [EmojiCatalogStructure]: from any key the catalogue
/// knows, base or variant, to its [EmojiEntry] and its place in palette
/// order.
///
/// This is the one place that says which keys belong together, so the grid,
/// the variant picker and search cannot disagree about whether an emoji has
/// variants: all of them ask [entryOf].
final class EmojiCatalog {
  /// Indexes [structure].
  ///
  /// Throws an [ArgumentError] when one key belongs to two entries (or to two
  /// places of one), since then "the entry of a key" would not be defined.
  EmojiCatalog(this.structure) {
    for (final group in structure.groups) {
      final inGroup = _entriesByGroup[group.id] = <EmojiEntry>[];
      for (final subgroup in group.subgroups) {
        for (final entry in subgroup.entries) {
          final position = _entries.length;
          _entries.add(entry);
          inGroup.add(entry);
          for (final key in [
            entry.base,
            for (final variant in entry.variants) variant.key,
          ]) {
            if (_index.containsKey(key)) {
              throw ArgumentError.value(
                structure,
                'structure',
                '$key belongs to more than one entry.',
              );
            }
            _index[key] = (entry: entry, position: position);
          }
        }
      }
    }
  }

  /// The structure this catalogue indexes.
  final EmojiCatalogStructure structure;

  final List<EmojiEntry> _entries = <EmojiEntry>[];

  final Map<ContentKey, ({EmojiEntry entry, int position})> _index = {};
  final Map<String, List<EmojiEntry>> _entriesByGroup = {};

  /// Every entry in palette order. Unmodifiable.
  List<EmojiEntry> get entries => UnmodifiableListView(_entries);

  /// The entry [key] is the base or a variant of, or null when the
  /// catalogue holds no such key.
  EmojiEntry? entryOf(ContentKey key) => _index[key]?.entry;

  /// The palette position of the entry of [key] (a variant has its entry's),
  /// or null when the catalogue holds no such key.
  int? positionOf(ContentKey key) => _index[key]?.position;

  /// The entries of the group [groupId] in palette order; empty for an id
  /// the structure does not hold.
  List<EmojiEntry> entriesOf(String groupId) =>
      _entriesByGroup[groupId] ?? const <EmojiEntry>[];
}
