import 'package:meta/meta.dart';

/// What [EntityDetection.apply] looks for, chosen by the host.
///
/// The three kinds of text are switched on separately; a policy with all of
/// them off detects nothing. It replaces body linkify's allowlist: a host that
/// wants web URLs only passes [DetectionPolicy.urlsOnly].
///
/// Detection is host-invoked, never the viewport's: a host builds the policy
/// once, next to the place it calls [EntityDetection.apply] (a send path, a
/// receive path, a link-preview listener) and keeps it constant, because
/// [EntityDetection.strip] must be given the policy that detected what it
/// removes.
@immutable
final class DetectionPolicy {
  /// Creates a policy; everything is on and the schemes are `http` and
  /// `https` unless said otherwise.
  const DetectionPolicy({
    this.urls = true,
    this.usernames = true,
    this.hashtags = true,
    this.schemes = const {'http', 'https'},
  });

  /// Web URLs only: no `@name`, no `#tag`. The policy of a link preview and
  /// of a host that links nothing else.
  static const DetectionPolicy urlsOnly = DetectionPolicy(
    usernames: false,
    hashtags: false,
  );

  /// Whether a bare URL or email becomes a link: `https://a.b/c`, `a.com`,
  /// `user@a.com` (a `mailto:` link).
  final bool urls;

  /// Whether `@name` becomes a username.
  final bool usernames;

  /// Whether `#tag` becomes a hashtag.
  final bool hashtags;

  /// The schemes a URL with an explicit scheme may have, matched ignoring
  /// case: `http` and `https` by default. With a scheme any host is accepted
  /// (`tg://resolve?domain=x`); a URL with a scheme outside the set is not
  /// detected.
  ///
  /// A URL without a scheme (`a.com`) is linked to [implicitScheme] with its
  /// text as the label. `mention`, `username` and `hashtag` are the schemes
  /// markdown spells entities with, so they never match, and an entry that is
  /// not a scheme name is ignored.
  final Set<String> schemes;

  /// Whether this policy detects anything at all.
  bool get detectsAnything => urls || usernames || hashtags;

  /// The scheme a URL typed without one is linked to: `https` when [schemes]
  /// allows it, else the first usable entry, else null (and then only URLs
  /// with an explicit scheme are detected).
  String? get implicitScheme {
    final usable = usableSchemes;
    if (usable.contains('https')) return 'https';
    return usable.isEmpty ? null : usable.first;
  }

  /// [schemes] lowercased, without what cannot be a scheme here.
  List<String> get usableSchemes => [
    for (final scheme in schemes)
      if (_isUsable(scheme.toLowerCase())) scheme.toLowerCase(),
  ];

  static final RegExp _schemeName = RegExp(r'^[a-z][a-z0-9+.\-]*$');
  static const Set<String> _reserved = {'mention', 'username', 'hashtag'};

  static bool _isUsable(String scheme) =>
      _schemeName.hasMatch(scheme) && !_reserved.contains(scheme);

  @override
  bool operator ==(Object other) =>
      other is DetectionPolicy &&
      other.urls == urls &&
      other.usernames == usernames &&
      other.hashtags == hashtags &&
      other.schemes.length == schemes.length &&
      other.schemes.containsAll(schemes);

  @override
  int get hashCode =>
      Object.hash(urls, usernames, hashtags, Object.hashAllUnordered(schemes));

  @override
  String toString() =>
      'DetectionPolicy(urls: $urls, usernames: $usernames, '
      'hashtags: $hashtags, schemes: $schemes)';
}
