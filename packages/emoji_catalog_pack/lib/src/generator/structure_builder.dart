import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/src/generator/emoji_test_file.dart';
import 'package:emoji_catalog_pack/src/structure/emoji_catalog_structure.dart';

const int _fe0f = 0xFE0F;
const int _zwj = 0x200D;
const int _lightTone = 0x1F3FB;
const int _darkTone = 0x1F3FF;
const int _femaleSign = 0x2640;
const int _maleSign = 0x2642;
const int _woman = 0x1F469;
const int _man = 0x1F468;
const int _person = 0x1F9D1;

/// Shapes the entries of `emoji-test.txt` into the catalog structure.
abstract final class StructureBuilder {
  /// Builds the catalog structure from the fully-qualified entries of [file].
  ///
  /// Every fully-qualified sequence ends up exactly once, either as an entry's
  /// base or as one of its variants. A sequence is a variant when removing its
  /// skin tones and normalising its gender gives another sequence of the file:
  ///
  /// - Tone modifiers (U+1F3FB..1F3FF) are read off in sequence order.
  /// - A gender is either a ZWJ + female/male sign suffix (`1F3C3 200D 2640`)
  ///   or a woman/man code point standing for the person code point
  ///   (`1F469 200D 1F4BB` for `1F9D1 200D 1F4BB`), one per person, in order.
  ///
  /// Sequences are compared by their skeleton, the code points without FE0F and
  /// tones, because a tone replaces the FE0F of its base (`270C FE0F`, `270C
  /// 1F3FD`). A variant keeps its own spelling: the data states every
  /// sequence, none is computed.
  ///
  /// A toned sequence whose toneless skeleton is no emoji (a handshake of two
  /// different tones is a pair of hands, not a handshake of a pair of hands)
  /// belongs to the entry named like it before the colon.
  ///
  /// Throws a [FormatException] when a toned sequence has no toneless form or
  /// two sequences share a skeleton: a new Emoji version whose structure these
  /// rules no longer describe must stop the generator, not shape the catalog.
  static EmojiCatalogStructure build(EmojiTestFile file) {
    final items = [for (final entry in file.entries) _Sequence(entry)];

    // The toneless sequences by skeleton: the only candidates for a parent.
    final bySkeleton = <String, _Sequence>{};
    for (final item in items.where((i) => i.tones.isEmpty)) {
      if (bySkeleton[item.skeleton] case final previous?) {
        throw FormatException(
          'Two sequences share the skeleton ${item.skeleton}: '
          '${previous.entry.name} and ${item.entry.name}.',
        );
      }
      bySkeleton[item.skeleton] = item;
    }

    final byName = <String, _Sequence>{};
    for (final item in bySkeleton.values) {
      byName.putIfAbsent(item.entry.name, () => item);
    }

    final links = <_Sequence, _Link>{};
    for (final item in items) {
      if (_linkOf(item, bySkeleton, byName) case final link?) {
        links[item] = link;
      } else if (item.tones.isNotEmpty) {
        throw FormatException(
          'No toneless form for ${item.entry.name} (${item.skeleton}).',
        );
      }
    }

    final variantsOf = <_Sequence, List<EmojiVariant>>{};
    final roots = <_Sequence>[];
    for (final item in items) {
      if (!links.containsKey(item)) {
        roots.add(item);
        continue;
      }
      // A parent found by name can itself be a gendered variant of a root; the
      // variant then belongs to that root with the gendered parent's genders.
      var link = links[item]!;
      for (var up = links[link.parent]; up != null; up = links[link.parent]) {
        link = (parent: up.parent, genders: [...up.genders, ...link.genders]);
      }
      variantsOf
          .putIfAbsent(link.parent, () => [])
          .add(
            EmojiVariant(
              item.key,
              EmojiModifiers(tones: item.tones, genders: link.genders),
            ),
          );
    }

    // Maps keep insertion order: groups and subgroups come out in file order,
    // and one that only held variants never appears.
    final tree = <String, Map<String, List<EmojiEntry>>>{};
    for (final root in roots) {
      tree
          .putIfAbsent(root.entry.group, () => {})
          .putIfAbsent(root.entry.subgroup, () => [])
          .add(EmojiEntry(base: root.key, variants: variantsOf[root] ?? []));
    }
    return EmojiCatalogStructure(
      emojiVersion: file.emojiVersion,
      groups: [
        for (final group in tree.entries)
          EmojiCatalogGroup(
            id: group.key,
            subgroups: [
              for (final subgroup in group.value.entries)
                EmojiCatalogSubgroup(id: subgroup.key, entries: subgroup.value),
            ],
          ),
      ],
    );
  }
}

typedef _Link = ({_Sequence parent, List<EmojiGender> genders});

_Link? _linkOf(
  _Sequence item,
  Map<String, _Sequence> bySkeleton,
  Map<String, _Sequence> byName,
) {
  if (item.neutral case final neutral?) {
    if (bySkeleton[neutral.skeleton] case final parent?) {
      return (parent: parent, genders: neutral.genders);
    }
  }
  if (item.tones.isEmpty) return null;
  final parent =
      bySkeleton[item.skeleton] ?? byName[item.entry.name.split(':').first];
  return switch (parent) {
    final parent? => (parent: parent, genders: const []),
    null => null,
  };
}

// One fully-qualified sequence with the facts the grouping rules read.
class _Sequence {
  _Sequence(this.entry)
    : key = ContentKey$Unicode(String.fromCharCodes(entry.codePoints)),
      tones = [
        for (final cp in entry.codePoints)
          if (cp >= _lightTone && cp <= _darkTone)
            SkinTone.values[cp - _lightTone],
      ],
      _skeleton = [
        for (final cp in entry.codePoints)
          if (cp != _fe0f && (cp < _lightTone || cp > _darkTone)) cp,
      ];

  final EmojiTestEntry entry;
  final ContentKey$Unicode key;
  final List<SkinTone> tones;
  final List<int> _skeleton;

  String get skeleton => _skeleton.join('-');

  /// This sequence with its gender removed, or null when it has none.
  ({String skeleton, List<EmojiGender> genders})? get neutral {
    final genders = <EmojiGender>[];
    final neutral = <int>[];
    for (var i = 0; i < _skeleton.length; i++) {
      final cp = _skeleton[i];
      final isSuffix =
          cp == _zwj &&
          i + 1 < _skeleton.length &&
          (_skeleton[i + 1] == _femaleSign || _skeleton[i + 1] == _maleSign);
      if (isSuffix) {
        genders.add(
          _skeleton[i + 1] == _femaleSign ? EmojiGender.woman : EmojiGender.man,
        );
        i++;
      } else if (cp == _woman || cp == _man) {
        genders.add(cp == _woman ? EmojiGender.woman : EmojiGender.man);
        neutral.add(_person);
      } else {
        neutral.add(cp);
      }
    }
    if (genders.isEmpty) return null;
    return (skeleton: neutral.join('-'), genders: genders);
  }
}
