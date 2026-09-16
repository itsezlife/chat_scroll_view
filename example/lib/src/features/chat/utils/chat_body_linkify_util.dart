import 'package:chat_scroll_view/chat_scroll_view.dart';

/// Host routing for an activated markdown link URL.
///
/// Built from `Uri.scheme` after a link **selection interaction** — not a
/// parallel **inline hit** kind. Mentions are expected as `mention:<username>`
/// after **body linkify**.
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
      'mention' => switch (_mentionUsername(url, uri)) {
        final user? => LinkActivation.mention(user),
        null => LinkActivation.other(url),
      },
      _ => LinkActivation.other(url),
    };
  }

  /// `http` / `https` — open-URL (or in-app browser) path.
  const factory LinkActivation.web(Uri uri) = WebLinkActivation;

  /// `mention:<username>` — profile / mention path.
  const factory LinkActivation.mention(String username) = MentionLinkActivation;

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
  /// Creates a mention activation for [username] (no `@` prefix).
  const MentionLinkActivation(this.username);

  /// Username from `mention:<username>` (without leading `@`).
  final String username;
}

/// [LinkActivation] when the scheme is neither web nor mention.
final class OtherLinkActivation extends LinkActivation {
  /// Creates a fallback activation for the raw [url] string.
  const OtherLinkActivation(this.url);

  /// Original activated URL string.
  final String url;
}

/// Host-owned **body linkify** policy and link-activation entry points.
///
/// Owns this app's [ChatLinkifyPolicy] and the scheme split after link
/// activation. Call [materialize] on send and on receive/materialize — never
/// from the chat viewport paint or rebuild path (ADR 017). Change [policy]
/// here when product allowlists change; do not scatter policy bits at call
/// sites.
///
/// Thin host wrapper around package [ChatBodyLinkify] — keep policy and
/// activation routing in one place.
abstract final class ChatBodyLinkifyUtil {
  /// Allowlist for this host — web URLs.
  static const ChatLinkifyPolicy policy = ChatLinkifyPolicy.webUrls;

  /// Rewrites bare tokens into markdown links for storage and display.
  ///
  /// Idempotent under package exclusions (fenced / inline code, existing
  /// `[…](…)`).
  static String materialize(String text) =>
      ChatBodyLinkify.apply(text, policy: policy);

  /// Classifies an activated link URL for host routing.
  static LinkActivation activation(String url) => LinkActivation.fromUrl(url);
}

String? _mentionUsername(String url, Uri uri) {
  // Opaque `mention:alice` puts the name in [Uri.path].
  final user = uri.path;
  if (user.isNotEmpty) return user;
  const prefix = 'mention:';
  if (url.startsWith(prefix)) {
    final rest = url.substring(prefix.length);
    return rest.isEmpty ? null : rest;
  }
  return null;
}
