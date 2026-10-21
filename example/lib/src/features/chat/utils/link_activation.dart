/// Host routing for an activated markdown link URL.
///
/// Built from `Uri.scheme` after a link **selection interaction** — not a
/// parallel **inline hit** kind. The schemes besides the web's are the ones
/// `RichTextMarkdown` writes entities with: `mention:<id>` for a mention the
/// host resolved, `username:<name>` and `hashtag:<tag>` for what detection
/// found in the text.
///
/// Prefer [LinkActivation.fromUrl] once at the activation seam; switch on the
/// sealed variants instead of re-parsing the string in UI code.
sealed class LinkActivation {
  const LinkActivation();

  /// Classifies [url] from an activated markdown link.
  factory LinkActivation.fromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return LinkActivation.other(url);
    }
    return switch (uri.scheme) {
      'http' || 'https' => LinkActivation.web(uri),
      'mention' => switch (_afterScheme(url, 'mention:')) {
        final id? => LinkActivation.mention(id),
        null => LinkActivation.other(url),
      },
      'username' => switch (_afterScheme(url, 'username:')) {
        final name? => LinkActivation.username(name),
        null => LinkActivation.other(url),
      },
      'hashtag' => switch (_afterScheme(url, 'hashtag:')) {
        final tag? => LinkActivation.hashtag(tag),
        null => LinkActivation.other(url),
      },
      _ => LinkActivation.other(url),
    };
  }

  /// `http` / `https` — open-URL (or in-app browser) path.
  const factory LinkActivation.web(Uri uri) = WebLinkActivation;

  /// `mention:<id>` — the profile of a party the host resolved.
  const factory LinkActivation.mention(String id) = MentionLinkActivation;

  /// `username:<name>` — an `@name` detection found; the host looks it up.
  const factory LinkActivation.username(String name) = UsernameLinkActivation;

  /// `hashtag:<tag>` — a `#tag` detection found; the host searches it.
  const factory LinkActivation.hashtag(String tag) = HashtagLinkActivation;

  /// Unrecognized or unparseable URL — host fallback.
  const factory LinkActivation.other(String url) = OtherLinkActivation;
}

/// [LinkActivation] for `http` / `https`.
final class WebLinkActivation extends LinkActivation {
  /// Creates a web activation for [uri].
  const WebLinkActivation(this.uri);

  /// Parsed destination (scheme already `http` or `https`).
  final Uri uri;
}

/// [LinkActivation] for the `mention:` scheme.
final class MentionLinkActivation extends LinkActivation {
  /// Creates a mention activation for the party [id].
  const MentionLinkActivation(this.id);

  /// The id from `mention:<id>`.
  final String id;
}

/// [LinkActivation] for the `username:` scheme.
final class UsernameLinkActivation extends LinkActivation {
  /// Creates a username activation for [name].
  const UsernameLinkActivation(this.name);

  /// The name from `username:<name>`, without the `@`.
  final String name;
}

/// [LinkActivation] for the `hashtag:` scheme.
final class HashtagLinkActivation extends LinkActivation {
  /// Creates a hashtag activation for [tag].
  const HashtagLinkActivation(this.tag);

  /// The tag from `hashtag:<tag>`, without the `#`.
  final String tag;
}

/// [LinkActivation] when the scheme is none of the above.
final class OtherLinkActivation extends LinkActivation {
  /// Creates a fallback activation for the raw [url] string.
  const OtherLinkActivation(this.url);

  /// Original activated URL string.
  final String url;
}

/// What follows [prefix] in [url], or null when nothing does.
String? _afterScheme(String url, String prefix) {
  if (!url.startsWith(prefix)) return null;
  final rest = url.substring(prefix.length);
  return rest.isEmpty ? null : rest;
}
