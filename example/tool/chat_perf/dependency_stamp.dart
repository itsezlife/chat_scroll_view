/// Which build of a dependency a launch measured. Pure Dart.
///
/// A path override moves under the run without any version change, and a
/// version bump in a lock can change rendering cost; the metadata block names
/// both so a baseline can be flagged when the markdown engine differs.
library;

/// The resolved entry of one package in a `pubspec.lock`.
final class DependencyStamp {
  const DependencyStamp({
    required this.name,
    required this.version,
    required this.source,
    this.location,
    this.revision,
  });

  final String name;
  final String version;

  /// `path`, `git` or `hosted`.
  final String source;

  /// The path (for `path`) or url (for `git`), as the lock says.
  final String? location;

  /// The resolved commit (git lock entry, or the checkout's HEAD for a path),
  /// when known.
  final String? revision;

  DependencyStamp withRevision(String? revision) => DependencyStamp(
    name: name,
    version: version,
    source: source,
    location: location,
    revision: revision,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    'source': source,
    'location': ?location,
    'revision': ?revision,
  };
}

/// Reads [name] from the text of a `pubspec.lock`; null when absent.
DependencyStamp? parseLockEntry(String lock, String name) {
  final lines = lock.split('\n');
  final start = lines.indexWhere((l) => l == '  $name:');
  if (start < 0) return null;
  String? field(String key) {
    for (var i = start + 1; i < lines.length; i++) {
      final l = lines[i];
      // The next package starts at two spaces of indent.
      if (l.isNotEmpty && !l.startsWith('   ')) break;
      final m = RegExp('^\\s+$key: *"?([^"]*)"?\$').firstMatch(l);
      if (m != null) return m.group(1);
    }
    return null;
  }

  final source = field('source');
  final version = field('version');
  if (source == null || version == null) return null;
  return DependencyStamp(
    name: name,
    version: version,
    source: source,
    location: switch (source) {
      'path' => field('path'),
      'git' => field('url'),
      _ => null,
    },
    revision: source == 'git' ? field('resolved-ref') : null,
  );
}

/// The commit a `.git/HEAD` names, given the file texts; null when it cannot
/// be told from them (packed refs, a worktree pointer file).
String? parseHeadRevision(String head, String? Function(String ref) readRef) {
  final trimmed = head.trim();
  if (trimmed.startsWith('ref: ')) {
    return readRef(trimmed.substring(5))?.trim();
  }
  return trimmed.isEmpty ? null : trimmed;
}
