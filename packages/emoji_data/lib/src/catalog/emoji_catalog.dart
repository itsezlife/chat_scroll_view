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
///
/// ## Genders
///
/// The data links the person, the man and the woman of an emoji into one
/// entry with every gender and tone. The reference client lists them as three
/// emoji of the grid, each with its tones, and that is what this catalogue
/// does by default ([flattenGenders]): an entry is split into one entry per
/// gender (the person first, then in the order the data gives them), whose base
/// is that gender's form without a tone and whose variants are its tones. The
/// variants keep their modifiers, gender included. Every key still belongs to
/// exactly one entry.
final class EmojiCatalog {
  /// Indexes [structure], splitting each entry by gender unless
  /// [flattenGenders] is false.
  ///
  /// Throws an [ArgumentError] when one key belongs to two entries (or to two
  /// places of one), since then "the entry of a key" would not be defined.
  EmojiCatalog(this.structure, {this.flattenGenders = true}) {
    for (final group in structure.groups) {
      final inGroup = _entriesByGroup[group.id] = <EmojiEntry>[];
      for (final subgroup in group.subgroups) {
        for (final entry in [
          for (final listed in subgroup.entries)
            ...flattenGenders ? _byGender(listed) : [listed],
        ]) {
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

  /// Whether the person, the man and the woman of an emoji are entries of
  /// their own (see "Genders" above).
  final bool flattenGenders;

  // [entry] split into one entry per gender combination, in the order the
  // combinations first appear (the base's, with no gender, first). An entry
  // with one combination is returned as it is. A combination with no toneless
  // form has none to stand for it and stays in the entry it came with.
  static List<EmojiEntry> _byGender(EmojiEntry entry) {
    final members = <String, List<EmojiVariant>>{'': <EmojiVariant>[]};
    for (final variant in entry.variants) {
      final genders = variant.modifiers.genders.map((g) => g.name).join(',');
      (members[genders] ??= <EmojiVariant>[]).add(variant);
    }
    if (members.length == 1) return [entry];
    final kept = <EmojiVariant>[...members.remove('')!];
    final split = <EmojiEntry>[];
    for (final variants in members.values) {
      final base = variants.where((v) => v.modifiers.tones.isEmpty).firstOrNull;
      if (base == null) {
        kept.addAll(variants);
        continue;
      }
      split.add(
        EmojiEntry(
          base: base.key,
          variants: [
            for (final v in variants)
              if (!identical(v, base)) v,
          ],
        ),
      );
    }
    return [EmojiEntry(base: entry.base, variants: kept), ...split];
  }

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
