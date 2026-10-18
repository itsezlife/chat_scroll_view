import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:flutter/painting.dart' show TextRange;
import 'package:meta/meta.dart';

/// The offer to apply formatting after a plain paste whose text reads as
/// markdown (the reference desktop client's "Apply formatting" toast).
///
/// Paste itself never parses markdown (ADR 032); the host makes this offer
/// from the composer's paste report and the user takes it or not. Applying it
/// replaces the pasted [range] with [formatted].
@immutable
final class ChatFormatOffer {
  const ChatFormatOffer._({
    required this.range,
    required this.formatted,
    required this.after,
  });

  /// How long the offer stands.
  static const Duration lifetime = Duration(seconds: 9);

  /// The offer for [paste], which left the composer holding [after], or null
  /// when there is nothing to offer: the paste was rich already, or its text
  /// decodes to itself.
  static ChatFormatOffer? of(ComposerPaste paste, RichText after) {
    if (paste.wasRich) return null;
    final formatted = RichTextMarkdown.decode(paste.text);
    if (formatted == RichText.plain(paste.text)) return null;
    return ChatFormatOffer._(
      range: paste.range,
      formatted: formatted,
      after: after,
    );
  }

  /// Where the pasted text sits in the composer.
  final TextRange range;

  /// What the pasted text reads as, decoded.
  final RichText formatted;

  /// The composer's text right after the paste: any edit makes it differ, and
  /// the offer, which names a range of it, goes.
  final RichText after;
}
