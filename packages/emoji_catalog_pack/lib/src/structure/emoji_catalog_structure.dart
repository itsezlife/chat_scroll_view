import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The locale-independent shape of the emoji catalog: Unicode groups and
/// subgroups in palette order, each holding [EmojiEntry]s.
///
/// Names and keywords are not here; they are per locale ([EmojiKeywordPack]). The
/// structure is the same for every locale, so a host loads it once.
///
/// ## Asset format
///
/// `structure.tsv` is UTF-8 text, one record per line, fields separated by a
/// tab. Lines starting with `@` are control records; every other line is an
/// entry of the current subgroup.
///
/// | Line | Meaning |
/// | --- | --- |
/// | `@emoji-catalog-structure<TAB>1` | Format marker and version; first line. |
/// | `@emoji<TAB>18.0` | The Unicode Emoji version the catalog was built from. |
/// | `@group<TAB>people-body` | Starts a group. |
/// | `@subgroup<TAB>hand-fingers-open` | Starts a subgroup of the current group. |
/// | `1F44B<TAB>1F44B-1F3FB/1<TAB>...` | An entry: the base key, then its variants. |
///
/// Keys are the `-`-separated upper-case hex code points of
/// [ContentKey.encoded] without its `unicode:` tag. A variant is
/// `key/tones/genders`: `tones` is one digit per person (1 light to 5 dark),
/// `genders` one letter per person (`w` woman, `m` man); either may be empty.
/// `1F469-200D-1F4BB//w` is a woman technologist with no tone.
@immutable
final class EmojiCatalogStructure {
  /// Creates a structure of [groups] built from [emojiVersion].
  EmojiCatalogStructure({
    required this.emojiVersion,
    required List<EmojiCatalogGroup> groups,
  }) : groups = List.unmodifiable(groups);

  /// Reads [source], the text of a `structure.tsv`.
  ///
  /// Throws a [FormatException] on any line it cannot read, so a damaged or
  /// newer-format asset fails loudly instead of yielding a partial catalog.
  factory EmojiCatalogStructure.decode(String source) =>
      _StructureReader(source).read();

  /// The Unicode Emoji version the catalog was built from (`18.0`).
  final String emojiVersion;

  /// The groups in palette order. Unmodifiable.
  final List<EmojiCatalogGroup> groups;

  /// Every entry of every group, in palette order.
  Iterable<EmojiEntry> get entries => [
    for (final group in groups)
      for (final subgroup in group.subgroups) ...subgroup.entries,
  ];

  /// The `structure.tsv` text of this structure; [EmojiCatalogStructure.decode]
  /// reads back an equal one. Deterministic: equal structures encode to equal
  /// text.
  String encode() {
    final out = StringBuffer()
      ..writeln('@$_marker\t$_formatVersion')
      ..writeln('@emoji\t$emojiVersion');
    for (final group in groups) {
      out.writeln('@group\t${group.id}');
      for (final subgroup in group.subgroups) {
        out.writeln('@subgroup\t${subgroup.id}');
        for (final entry in subgroup.entries) {
          out.writeln(
            [
              _hex(entry.base),
              for (final variant in entry.variants) _encodeVariant(variant),
            ].join('\t'),
          );
        }
      }
    }
    return out.toString();
  }

  static const String _marker = 'emoji-catalog-structure';
  static const int _formatVersion = 1;

  static String _hex(ContentKey$Unicode key) =>
      key.encoded.substring(_unicodeTag.length);

  static const String _unicodeTag = 'unicode:';

  static String _encodeVariant(EmojiVariant variant) {
    final modifiers = variant.modifiers;
    final tones = modifiers.tones.map((t) => t.index + 1).join();
    final genders = modifiers.genders.map((g) => g.name[0]).join();
    return '${_hex(variant.key)}/$tones/$genders';
  }
}

/// One Unicode group of the catalog (`people-body`) and its subgroups.
@immutable
final class EmojiCatalogGroup {
  /// Creates a group of [subgroups].
  EmojiCatalogGroup({
    required this.id,
    required List<EmojiCatalogSubgroup> subgroups,
  }) : subgroups = List.unmodifiable(subgroups);

  /// The group id: Unicode's group name as a lower-case slug.
  final String id;

  /// The subgroups in palette order. Unmodifiable.
  final List<EmojiCatalogSubgroup> subgroups;
}

/// One Unicode subgroup (`hand-fingers-open`) and its entries.
@immutable
final class EmojiCatalogSubgroup {
  /// Creates a subgroup of [entries].
  EmojiCatalogSubgroup({required this.id, required List<EmojiEntry> entries})
    : entries = List.unmodifiable(entries);

  /// The subgroup id: Unicode's subgroup name as a lower-case slug.
  final String id;

  /// The entries in palette order. Unmodifiable.
  final List<EmojiEntry> entries;
}

class _StructureReader {
  _StructureReader(this._source);

  final String _source;

  EmojiCatalogStructure read() {
    String? version;
    var sawMarker = false;
    final groups = <EmojiCatalogGroup>[];
    String? groupId;
    var subgroups = <EmojiCatalogSubgroup>[];
    String? subgroupId;
    var entries = <EmojiEntry>[];

    void closeSubgroup() {
      if (subgroupId case final id?) {
        subgroups.add(EmojiCatalogSubgroup(id: id, entries: entries));
      }
      subgroupId = null;
      entries = [];
    }

    void closeGroup() {
      closeSubgroup();
      if (groupId case final id?) {
        groups.add(EmojiCatalogGroup(id: id, subgroups: subgroups));
      }
      groupId = null;
      subgroups = [];
    }

    for (final line in _source.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\t');
      switch (fields.first) {
        case '@${EmojiCatalogStructure._marker}':
          if (fields.length != 2 ||
              fields[1] != '${EmojiCatalogStructure._formatVersion}') {
            throw FormatException('Unsupported structure format.', line);
          }
          sawMarker = true;
        case '@emoji':
          version = _single(fields, line);
        case '@group':
          closeGroup();
          groupId = _single(fields, line);
        case '@subgroup':
          if (groupId == null) {
            throw FormatException('Subgroup outside a group.', line);
          }
          closeSubgroup();
          subgroupId = _single(fields, line);
        default:
          if (subgroupId == null) {
            throw FormatException('Entry outside a subgroup.', line);
          }
          entries.add(_entry(fields, line));
      }
    }
    closeGroup();
    if (!sawMarker || version == null) {
      throw const FormatException('Missing structure header.');
    }
    return EmojiCatalogStructure(emojiVersion: version, groups: groups);
  }

  String _single(List<String> fields, String line) {
    if (fields.length != 2 || fields[1].isEmpty) {
      throw FormatException('Expected one value.', line);
    }
    return fields[1];
  }

  EmojiEntry _entry(List<String> fields, String line) => EmojiEntry(
    base: _key(fields.first, line),
    variants: [for (final field in fields.skip(1)) _variant(field, line)],
  );

  ContentKey$Unicode _key(String hex, String line) {
    if (ContentKey.tryParse('unicode:$hex') case final ContentKey$Unicode key) {
      return key;
    }
    throw FormatException('Not a code point sequence: $hex.', line);
  }

  EmojiVariant _variant(String field, String line) {
    final parts = field.split('/');
    if (parts.length != 3) {
      throw FormatException('Not a variant: $field.', line);
    }
    return EmojiVariant(
      _key(parts[0], line),
      EmojiModifiers(
        tones: [for (final unit in parts[1].split('')) _tone(unit, line)],
        genders: [for (final unit in parts[2].split('')) _gender(unit, line)],
      ),
    );
  }

  SkinTone _tone(String unit, String line) {
    final index = int.tryParse(unit);
    if (index == null || index < 1 || index > SkinTone.values.length) {
      throw FormatException('Not a tone: $unit.', line);
    }
    return SkinTone.values[index - 1];
  }

  EmojiGender _gender(String unit, String line) => switch (unit) {
    'w' => EmojiGender.woman,
    'm' => EmojiGender.man,
    _ => throw FormatException('Not a gender: $unit.', line),
  };
}
