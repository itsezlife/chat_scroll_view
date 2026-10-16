import 'package:meta/meta.dart';

/// One downloadable input of the generator: the name it is known by and the
/// versioned URL it is fetched from.
@immutable
final class InputSource {
  /// Creates the source called [name] at [url].
  const InputSource({required this.name, required this.url});

  /// The stable name (`cldr/annotations/de.xml`), also its cache path.
  final String name;

  /// The versioned or tagged URL the input is fetched from.
  final String url;
}

/// The inputs the generator needs for a set of versions, before they are
/// pinned to checksums.
@immutable
final class InputsPlan {
  /// Plans the inputs for the Unicode [emojiVersion], the CLDR release
  /// [cldrTag] and one keyword pack per entry of [locales].
  InputsPlan({
    required this.emojiVersion,
    required this.cldrTag,
    required List<String> locales,
  }) : locales = List.unmodifiable(locales);

  /// The Unicode Emoji version (`18.0`).
  final String emojiVersion;

  /// The CLDR release tag (`release-49-beta4`).
  final String cldrTag;

  /// The locales that get a keyword pack, in pack order. Unmodifiable.
  final List<String> locales;

  /// The CLDR release as a label (`49-beta4`).
  String get cldrVersion => cldrTag.replaceFirst('release-', '');

  /// The inputs: `emoji-test.txt`, the CLDR licence and, per locale, the
  /// annotation file and the derived annotation file.
  List<InputSource> get sources {
    final cldr = 'https://raw.githubusercontent.com/unicode-org/cldr/$cldrTag';
    return [
      InputSource(
        name: 'emoji-test.txt',
        url: 'https://unicode.org/Public/$emojiVersion.0/emoji/emoji-test.txt',
      ),
      InputSource(name: 'cldr/LICENSE', url: '$cldr/LICENSE'),
      for (final locale in locales)
        for (final kind in const ['annotations', 'annotationsDerived'])
          InputSource(
            name: 'cldr/$kind/$locale.xml',
            url: '$cldr/common/$kind/$locale.xml',
          ),
    ];
  }
}

/// `tool/inputs.lock`: the Unicode and CLDR versions the shipped assets are
/// built from, with a SHA-256 per input file.
///
/// Versions alone would not pin the data (a URL can start serving other
/// bytes); the checksums do. A version changed without regenerated assets
/// fails the reproducibility check because the assets carry the versions.
///
/// ## File format
///
/// Text, one record per line, fields separated by a space; `#` starts a
/// comment line.
///
/// | Line | Meaning |
/// | --- | --- |
/// | `emoji-version 18.0` | The Unicode Emoji version. |
/// | `cldr-tag release-49-beta4` | The CLDR release tag. |
/// | `locales en de ...` | The locales that get a keyword pack. |
/// | `input <sha256> <name> <url>` | One pinned input. |
@immutable
final class InputsLock {
  /// Creates a lock of [inputs] for the versions and [locales] of a plan.
  InputsLock({
    required this.emojiVersion,
    required this.cldrTag,
    required List<String> locales,
    required List<LockedInput> inputs,
  }) : locales = List.unmodifiable(locales),
       inputs = List.unmodifiable(inputs);

  /// Pins every source of [plan] to the checksum [checksumOf] returns for it.
  factory InputsLock.pin(
    InputsPlan plan,
    String Function(InputSource source) checksumOf,
  ) => InputsLock(
    emojiVersion: plan.emojiVersion,
    cldrTag: plan.cldrTag,
    locales: plan.locales,
    inputs: [
      for (final source in plan.sources)
        LockedInput(source: source, sha256: checksumOf(source)),
    ],
  );

  /// Reads [text], the contents of an `inputs.lock`.
  ///
  /// Throws a [FormatException] on an unreadable line, a checksum that is not
  /// 64 hex digits, a missing version, or an input the versions and locales
  /// require but the lock does not pin.
  factory InputsLock.parse(String text) {
    String? emoji;
    String? tag;
    List<String>? locales;
    final inputs = <LockedInput>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final fields = trimmed.split(' ');
      switch (fields.first) {
        case 'emoji-version' when fields.length == 2:
          emoji = fields[1];
        case 'cldr-tag' when fields.length == 2:
          tag = fields[1];
        case 'locales' when fields.length > 1:
          locales = fields.sublist(1);
        case 'input' when fields.length == 4:
          if (fields[1].length != 64 || _notHex.hasMatch(fields[1])) {
            throw FormatException('Not a SHA-256: ${fields[1]}.', line);
          }
          inputs.add(
            LockedInput(
              source: InputSource(name: fields[2], url: fields[3]),
              sha256: fields[1],
            ),
          );
        default:
          throw FormatException('Unreadable lock line.', line);
      }
    }
    if (emoji == null || tag == null || locales == null) {
      throw const FormatException(
        'The lock needs emoji-version, cldr-tag and locales.',
      );
    }
    final lock = InputsLock(
      emojiVersion: emoji,
      cldrTag: tag,
      locales: locales,
      inputs: inputs,
    );
    for (final source in lock.plan.sources) {
      final pinned = inputs.where((i) => i.name == source.name);
      if (pinned.length != 1) {
        throw FormatException('The lock must pin ${source.name} once.');
      }
      if (pinned.single.url != source.url) {
        throw FormatException(
          '${source.name} is pinned to ${pinned.single.url}, '
          'not ${source.url}.',
        );
      }
    }
    return lock;
  }

  /// The Unicode Emoji version (`18.0`).
  final String emojiVersion;

  /// The CLDR release tag (`release-49-beta4`).
  final String cldrTag;

  /// The locales that get a keyword pack, in pack order. Unmodifiable.
  final List<String> locales;

  /// The pinned inputs. Unmodifiable.
  final List<LockedInput> inputs;

  /// The plan these pins were made for.
  InputsPlan get plan => InputsPlan(
    emojiVersion: emojiVersion,
    cldrTag: cldrTag,
    locales: locales,
  );

  /// The pin called [name]; throws a [StateError] when there is none.
  LockedInput input(String name) => inputs.singleWhere(
    (input) => input.name == name,
    orElse: () => throw StateError('No pinned input $name.'),
  );

  /// The text of this lock; [InputsLock.parse] reads back an equal one.
  String encode() {
    final out = StringBuffer()
      ..writeln('# Pinned generator inputs; rewrite with')
      ..writeln('#   dart run tool/generate.dart lock')
      ..writeln('emoji-version $emojiVersion')
      ..writeln('cldr-tag $cldrTag')
      ..writeln('locales ${locales.join(' ')}');
    for (final input in inputs) {
      out.writeln('input ${input.sha256} ${input.name} ${input.url}');
    }
    return out.toString();
  }

  static final RegExp _notHex = RegExp('[^0-9a-f]');
}

/// An [InputSource] with the SHA-256 of the exact bytes the assets were built
/// from.
@immutable
final class LockedInput {
  /// Creates the pin of [source] to [sha256].
  const LockedInput({required this.source, required this.sha256});

  /// What is pinned.
  final InputSource source;

  /// The lower-case hex SHA-256 of the input.
  final String sha256;

  /// The name of [source].
  String get name => source.name;

  /// The URL of [source].
  String get url => source.url;
}
