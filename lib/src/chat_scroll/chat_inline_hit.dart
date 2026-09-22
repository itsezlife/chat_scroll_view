import 'dart:ui' show Offset, Path;

import 'package:flutter/foundation.dart';

/// Semantic inline hit on a markdown body element (hyperlink or code block).
///
/// Inline hits participate in viewport gesture arbitration: they are
/// first-class interactions that are not consumed solely as idle selection
/// dismissals or row toggles.
///
/// When produced by pointer hit-testing against mounted markdown surfaces,
/// carries the optional [contourPath] (closed vector-smoothed contour computed
/// by `ChatSmoothContour`) and [touchOrigin] (content-local coordinates of the
/// tap event) to drive tactile tap highlight animations.
@immutable
sealed class ChatInlineHit {
  /// Base constructor for inline hit variants.
  const ChatInlineHit();

  /// Creates a link hit.
  const factory ChatInlineHit.link({
    required int messageId,
    required String title,
    required String url,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Link;

  /// Creates a code or monospace snippet hit.
  const factory ChatInlineHit.code({
    required int messageId,
    required String code,
    String? language,
    Path? contourPath,
    Offset? touchOrigin,
  }) = ChatInlineHit$Code;

  /// The message ID whose body contains the hit element.
  abstract final int messageId;

  /// Optional vector-smoothed contour path wrapping the hit span's line bounding boxes.
  Path? get contourPath;

  /// Optional content-local coordinates of the pointer origin where the tap occurred.
  Offset? get touchOrigin;
}

/// An inline link hit in a markdown message body.
///
/// Carries the tapped hyperlink's target [url] and display [title], alongside
/// optional geometry for tactile tap feedback.
@immutable
final class ChatInlineHit$Link extends ChatInlineHit {
  /// Creates a link hit descriptor.
  const ChatInlineHit$Link({
    required this.messageId,
    required this.title,
    required this.url,
    this.contourPath,
    this.touchOrigin,
  });

  @override
  final int messageId;

  /// Display text or label of the link (falls back to [url] if none).
  final String title;

  /// Target URL string parsed from markdown.
  final String url;

  @override
  final Path? contourPath;

  @override
  final Offset? touchOrigin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Link &&
          other.messageId == messageId &&
          other.title == title &&
          other.url == url &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode =>
      Object.hash(messageId, title, url, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Link(messageId: '
      '$messageId, title: $title, url: $url, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}

/// An inline code hit in a markdown message body.
///
/// Produced by taps on fenced code blocks or inline monospace code snippets,
/// alongside optional geometry for tactile tap feedback.
@immutable
final class ChatInlineHit$Code extends ChatInlineHit {
  /// Creates a code hit descriptor.
  const ChatInlineHit$Code({
    required this.messageId,
    required this.code,
    this.language,
    this.contourPath,
    this.touchOrigin,
  });

  @override
  final int messageId;

  /// Text content of the code block or monospace span.
  final String code;

  /// Programming language identifier if present on a fenced code block,
  /// or null for inline monospace spans or unspecified blocks.
  final String? language;

  @override
  final Path? contourPath;

  @override
  final Offset? touchOrigin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInlineHit$Code &&
          other.messageId == messageId &&
          other.code == code &&
          other.language == language &&
          other.contourPath == contourPath &&
          other.touchOrigin == touchOrigin;

  @override
  int get hashCode =>
      Object.hash(messageId, code, language, contourPath, touchOrigin);

  @override
  String toString() =>
      r'ChatInlineHit$Code(messageId: '
      '$messageId, code: $code, language: $language, '
      'contourPath: $contourPath, touchOrigin: $touchOrigin)';
}
