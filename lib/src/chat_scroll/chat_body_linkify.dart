import 'package:meta/meta.dart';

/// Host-invoked **body linkify**: rewrite bare tokens in message text into
/// markdown links.
///
/// Closed static namespace for the pure rewrite. Runs at send and at
/// receive/materialize — never from the chat viewport paint or rebuild path.
/// The viewport only paints and activates already-marked markdown links
/// (ADR 017).
///
/// [ChatLinkifyPolicy] is a combinable allowlist bitmask. Exclusion zones —
/// fenced code, inline code, and existing `[…](…)` — are never rewritten.
/// Trailing sentence punctuation after a URL match is left outside the link.
/// Mentions use the `mention:` scheme; the host branches on scheme after the
/// existing link **inline hit** / **selection interaction** (no separate
/// mention hit kind).
///
/// A second [apply] is a no-op when exclusions hold (idempotent). Empty text
/// and [ChatLinkifyPolicy.none] are returned unchanged.
abstract final class ChatBodyLinkify {
  /// Rewrites [text] under [policy] into markdown link syntax.
  ///
  /// Defaults to [ChatLinkifyPolicy.webAndMentions].
  static String apply(
    String text, {
    ChatLinkifyPolicy policy = ChatLinkifyPolicy.webAndMentions,
  }) {
    if (text.isEmpty || policy.isNone) {
      return text;
    }
    return _linkify(
      text,
      rewriteUrls: policy.contains(ChatLinkifyPolicy.webUrls),
      rewriteMentions: policy.contains(ChatLinkifyPolicy.mentions),
    );
  }
}

/// Caller-owned allowlist for **body linkify**, stored as a bitfield
/// (`extension type` over `int`).
///
/// Flags combine — hosts OR bits instead of picking a sealed preset. Does not
/// own paint, activation, or **link preview**. The scroll/paint path must not
/// call [ChatBodyLinkify.apply].
///
/// ## Flags
///
/// | Constant | Rewrites |
/// | --- | --- |
/// | [ChatLinkifyPolicy.webUrls] | Bare `http` / `https` / `www` |
/// | [ChatLinkifyPolicy.mentions] | `@username` → `mention:<username>` |
/// | [ChatLinkifyPolicy.webAndMentions] | Both (`webUrls \| mentions`) |
/// | [ChatLinkifyPolicy.none] | No rewrite |
///
/// Exclusion zones for every non-empty policy: fenced code, inline code,
/// existing `[label](url)` (fixed package zones, not a separate host knob).
///
/// **Footgun**: a raw [int] can be passed where [ChatLinkifyPolicy] is expected
/// with no runtime error. Prefer the named constants below.
///
/// Mentions keep `@username` display text. Activation stays the existing link
/// channel; hosts interpret `Uri.scheme == 'mention'`.
extension type const ChatLinkifyPolicy._(int _value) {
  /// No token families — [ChatBodyLinkify.apply] returns text unchanged.
  static const ChatLinkifyPolicy none = ChatLinkifyPolicy._(0);

  /// Bare `http` / `https` / `www` → markdown links.
  ///
  /// `www.` tokens keep that display text and use an `https://` target.
  static const ChatLinkifyPolicy webUrls = ChatLinkifyPolicy._(1 << 0);

  /// Bare `@username` → `[@username](mention:username)`.
  static const ChatLinkifyPolicy mentions = ChatLinkifyPolicy._(1 << 1);

  /// [webUrls] and [mentions] together — the package default.
  static const ChatLinkifyPolicy webAndMentions = ChatLinkifyPolicy._(
    (1 << 0) | (1 << 1),
  );

  // --- Can be expanded up to 1 << 31 --- //

  /// Defined allowlist flags (not including convenience combinations).
  static const List<ChatLinkifyPolicy> values = <ChatLinkifyPolicy>[
    none,
    webUrls,
    mentions,
  ];

  /// Whether this policy includes [flag]'s bits.
  bool contains(ChatLinkifyPolicy flag) => (_value & flag._value) != 0;

  /// Union with [flag] (enable those token families).
  ChatLinkifyPolicy add(ChatLinkifyPolicy flag) =>
      ChatLinkifyPolicy._(_value | flag._value);

  /// Clear [flag]'s bits.
  ChatLinkifyPolicy remove(ChatLinkifyPolicy flag) =>
      ChatLinkifyPolicy._(_value & ~flag._value);

  /// XOR [flag]'s bits.
  ChatLinkifyPolicy toggle(ChatLinkifyPolicy flag) =>
      ChatLinkifyPolicy._(_value ^ flag._value);

  /// Union — same as [add]; `webUrls | mentions` reads as combine.
  ChatLinkifyPolicy operator |(ChatLinkifyPolicy other) => add(other);

  /// XOR — same as [toggle] when [other] is a single flag family.
  ChatLinkifyPolicy operator ^(ChatLinkifyPolicy other) =>
      ChatLinkifyPolicy._(_value ^ other._value);

  /// No allowlist bits set.
  bool get isNone => _value == 0;
}

// --- Exclusion zones -------------------------------------------------------

/// Inclusive-exclusive `[start, end)` range that must not be rewritten.
@immutable
final class _Exclusion {
  const _Exclusion(this.start, this.end);

  final int start;
  final int end;

  bool contains(int index) => index >= start && index < end;
}

List<_Exclusion> _collectExclusions(String text) {
  final exclusions = <_Exclusion>[];
  var i = 0;
  while (i < text.length) {
    final fence = _matchFence(text, i);
    if (fence case final end?) {
      exclusions.add(_Exclusion(i, end));
      i = end;
      continue;
    }

    final inline = _matchInlineCode(text, i);
    if (inline case final end?) {
      exclusions.add(_Exclusion(i, end));
      i = end;
      continue;
    }

    final link = _matchMarkdownLink(text, i);
    if (link case final end?) {
      exclusions.add(_Exclusion(i, end));
      i = end;
      continue;
    }

    i += 1;
  }
  return exclusions;
}

bool _isExcluded(List<_Exclusion> exclusions, int index) {
  for (final exclusion in exclusions) {
    if (exclusion.contains(index)) {
      return true;
    }
  }
  return false;
}

/// Opening fence at [start] → exclusive end index after the closing fence.
int? _matchFence(String text, int start) {
  if (!_startsFence(text, start)) {
    return null;
  }
  final marker = text[start];
  var fenceLen = 0;
  while (start + fenceLen < text.length && text[start + fenceLen] == marker) {
    fenceLen += 1;
  }
  if (fenceLen < 3) {
    return null;
  }
  // Info string through end of opening line.
  var i = start + fenceLen;
  while (i < text.length && text[i] != '\n') {
    i += 1;
  }
  if (i < text.length && text[i] == '\n') {
    i += 1;
  }
  // Body until a closing fence of at least [fenceLen] markers.
  while (i < text.length) {
    if (_isLineStart(text, i) && text[i] == marker) {
      var closeLen = 0;
      while (i + closeLen < text.length && text[i + closeLen] == marker) {
        closeLen += 1;
      }
      if (closeLen >= fenceLen) {
        var end = i + closeLen;
        while (end < text.length && text[end] != '\n') {
          end += 1;
        }
        if (end < text.length && text[end] == '\n') {
          end += 1;
        }
        return end;
      }
    }
    i += 1;
  }
  // Unclosed fence: treat remainder as excluded.
  return text.length;
}

bool _startsFence(String text, int start) {
  if (!_isLineStart(text, start)) {
    return false;
  }
  if (start >= text.length) {
    return false;
  }
  final c = text[start];
  if (c != '`' && c != '~') {
    return false;
  }
  var len = 0;
  while (start + len < text.length && text[start + len] == c) {
    len += 1;
  }
  return len >= 3;
}

bool _isLineStart(String text, int index) =>
    index == 0 || text[index - 1] == '\n';

/// Inline `` `…` `` at [start] → exclusive end, or null.
///
/// Skips runs of three or more backticks (fence openers).
int? _matchInlineCode(String text, int start) {
  if (start >= text.length || text[start] != '`') {
    return null;
  }
  var openLen = 0;
  while (start + openLen < text.length && text[start + openLen] == '`') {
    openLen += 1;
  }
  if (openLen >= 3) {
    return null;
  }
  var i = start + openLen;
  while (i < text.length) {
    if (text[i] == '`') {
      var closeLen = 0;
      while (i + closeLen < text.length && text[i + closeLen] == '`') {
        closeLen += 1;
      }
      if (closeLen == openLen) {
        return i + closeLen;
      }
      i += closeLen;
      continue;
    }
    if (text[i] == '\n') {
      return null;
    }
    i += 1;
  }
  return null;
}

/// `[label](destination)` at [start] → exclusive end, or null.
int? _matchMarkdownLink(String text, int start) {
  if (start >= text.length || text[start] != '[') {
    return null;
  }
  final closeBracket = text.indexOf(']', start + 1);
  if (closeBracket < 0) {
    return null;
  }
  if (closeBracket + 1 >= text.length || text[closeBracket + 1] != '(') {
    return null;
  }
  var depth = 1;
  var i = closeBracket + 2;
  while (i < text.length) {
    final c = text[i];
    if (c == '(') {
      depth += 1;
    } else if (c == ')') {
      depth -= 1;
      if (depth == 0) {
        return i + 1;
      }
    } else if (c == '\n') {
      return null;
    }
    i += 1;
  }
  return null;
}

// --- Token rewrite ---------------------------------------------------------

final RegExp _$schemedUrl = RegExp(
  r'''https?://[^\s<>\[\]()`'"]+''',
  caseSensitive: false,
);

final RegExp _$wwwUrl = RegExp(
  r'''(?<![/@\w])www\.[^\s<>\[\]()`'"]+''',
  caseSensitive: false,
);

/// Bare `@username` — not email local-parts (`user@host`).
final RegExp _$mention = RegExp(r'(?<![\w])@[A-Za-z0-9_]+');

String _linkify(
  String text, {
  required bool rewriteUrls,
  required bool rewriteMentions,
}) {
  final exclusions = _collectExclusions(text);
  final buffer = StringBuffer();
  var cursor = 0;

  while (cursor < text.length) {
    if (_isExcluded(exclusions, cursor)) {
      final end = _exclusionEndCovering(exclusions, cursor);
      buffer.write(text.substring(cursor, end));
      cursor = end;
      continue;
    }

    final freeEnd = _nextExclusionStart(exclusions, cursor) ?? text.length;
    final free = text.substring(cursor, freeEnd);
    buffer.write(
      _rewriteFreeSegment(
        free,
        rewriteUrls: rewriteUrls,
        rewriteMentions: rewriteMentions,
      ),
    );
    cursor = freeEnd;
  }

  return buffer.toString();
}

int _exclusionEndCovering(List<_Exclusion> exclusions, int index) {
  var end = index + 1;
  for (final exclusion in exclusions) {
    if (exclusion.contains(index)) {
      if (exclusion.end > end) {
        end = exclusion.end;
      }
    }
  }
  return end;
}

int? _nextExclusionStart(List<_Exclusion> exclusions, int from) {
  int? best;
  for (final exclusion in exclusions) {
    if (exclusion.start >= from) {
      if (best == null || exclusion.start < best) {
        best = exclusion.start;
      }
    }
  }
  return best;
}

String _rewriteFreeSegment(
  String segment, {
  required bool rewriteUrls,
  required bool rewriteMentions,
}) {
  if (segment.isEmpty) {
    return segment;
  }

  final matches = <_TokenMatch>[
    if (rewriteUrls) ...[
      for (final match in _$schemedUrl.allMatches(segment))
        _TokenMatch(
          start: match.start,
          end: _trimTrailingPunctuation(segment, match.start, match.end),
          targetFor: (token) => token,
        ),
      for (final match in _$wwwUrl.allMatches(segment))
        _TokenMatch(
          start: match.start,
          end: _trimTrailingPunctuation(segment, match.start, match.end),
          targetFor: (token) => 'https://$token',
        ),
    ],
    if (rewriteMentions)
      for (final match in _$mention.allMatches(segment))
        _TokenMatch(
          start: match.start,
          end: match.end,
          targetFor: (token) => 'mention:${token.substring(1)}',
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));

  if (matches.isEmpty) {
    return segment;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    if (match.start < cursor || match.end <= match.start) {
      continue;
    }
    buffer.write(segment.substring(cursor, match.start));
    final token = segment.substring(match.start, match.end);
    buffer.write('[$token](${match.targetFor(token)})');
    cursor = match.end;
  }
  buffer.write(segment.substring(cursor));
  return buffer.toString();
}

@immutable
final class _TokenMatch {
  const _TokenMatch({
    required this.start,
    required this.end,
    required this.targetFor,
  });

  final int start;
  final int end;

  /// Builds the markdown link destination from the matched display token.
  final String Function(String token) targetFor;
}

/// Shrink [end] so trailing sentence punctuation is not part of the URL.
int _trimTrailingPunctuation(String text, int start, int end) {
  var trimmed = end;
  while (trimmed > start) {
    final c = text[trimmed - 1];
    if (c == '.' ||
        c == ',' ||
        c == ';' ||
        c == ':' ||
        c == '!' ||
        c == '?' ||
        c == ')' ||
        c == ']' ||
        c == '"' ||
        c == "'") {
      trimmed -= 1;
      continue;
    }
    break;
  }
  return trimmed;
}
