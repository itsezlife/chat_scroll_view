import 'package:meta/meta.dart';

/// One fully-qualified emoji line of `emoji-test.txt`.
@immutable
final class EmojiTestEntry {
  /// Creates an entry; see the field docs.
  const EmojiTestEntry({
    required this.codePoints,
    required this.group,
    required this.subgroup,
    required this.since,
    required this.name,
  });

  /// The sequence exactly as the file spells it, FE0F and ZWJ included.
  final List<int> codePoints;

  /// The id of the Unicode group (`people-body`).
  final String group;

  /// The id of the Unicode subgroup (`hand-fingers-open`).
  final String subgroup;

  /// The Emoji version that introduced it (`13.1`).
  final String since;

  /// The English name Unicode gives the sequence.
  final String name;

  @override
  String toString() => 'EmojiTestEntry($name)';
}

/// The fully-qualified emoji of one `emoji-test.txt`, in CLDR order.
///
/// The file lists every sequence in up to three spellings (fully-qualified,
/// minimally-qualified, unqualified) plus components. Only the fully-qualified
/// spelling is a catalog entry: the other spellings differ by missing FE0F
/// and are the same emoji, and components are not emoji on their own. The
/// order of the file is the order of a keyboard palette and is preserved.
@immutable
final class EmojiTestFile {
  const EmojiTestFile._(this.emojiVersion, this.entries);

  /// Reads [source], the text of an `emoji-test.txt`.
  ///
  /// Throws a [FormatException] when the version header is missing or a data
  /// line appears before any group, so a changed file layout stops the
  /// generator instead of producing a wrong catalog.
  factory EmojiTestFile.parse(String source) {
    String? version;
    String? group;
    String? subgroup;
    final entries = <EmojiTestEntry>[];
    for (final line in source.split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        version ??= _version.firstMatch(line)?.group(1);
        group = _groupId(line, 'group') ?? group;
        subgroup = _groupId(line, 'subgroup') ?? subgroup;
        continue;
      }
      final data = _data.firstMatch(line);
      if (data == null) {
        throw FormatException('Unreadable emoji-test line.', line);
      }
      if (data.group(2) != 'fully-qualified') continue;
      if (group == null || subgroup == null) {
        throw FormatException('Emoji line before any group.', line);
      }
      entries.add(
        EmojiTestEntry(
          codePoints: [
            for (final hex in data.group(1)!.split(' '))
              int.parse(hex, radix: 16),
          ],
          group: group,
          subgroup: subgroup,
          since: data.group(3)!,
          name: data.group(4)!.trim(),
        ),
      );
    }
    if (version == null) {
      throw const FormatException('emoji-test.txt has no "# Version:" line.');
    }
    return EmojiTestFile._(version, List.unmodifiable(entries));
  }

  /// The Emoji version the file describes (`18.0`).
  final String emojiVersion;

  /// The fully-qualified entries in file order. Unmodifiable.
  final List<EmojiTestEntry> entries;

  static final RegExp _version = RegExp(r'^#\s*Version:\s*(\d+\.\d+)');
  static final RegExp _data = RegExp(
    r'^([0-9A-F ]+?)\s*;\s*([a-z-]+)\s*#\s*\S+\s+E(\d+\.\d+)\s+(.*)$',
  );

  static final RegExp _nonAlphanumeric = RegExp('[^a-z0-9]+');

  static String? _groupId(String line, String kind) {
    final match = RegExp('^#\\s*$kind:\\s*(.+)\$').firstMatch(line);
    if (match == null) return null;
    return match
        .group(1)!
        .toLowerCase()
        .split(_nonAlphanumeric)
        .where((word) => word.isNotEmpty)
        .join('-');
  }
}
