import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// How the field paints the spans of its text that carry an entity.
///
/// Weight, slant, underline and strike are structural and always applied. The
/// colours are the host's: the composer ships no colour of its own, so a role
/// left null paints nothing for that role (a link is still underlined). Hosts
/// usually build the value with [ComposerEntityStyles.fromTokens] from the
/// composer token group of the chrome theme.
@immutable
final class ComposerEntityStyles {
  /// Styles with the given colours; a null colour leaves the role unpainted.
  const ComposerEntityStyles({
    this.link,
    this.mention,
    this.codeBackground,
    this.spoilerBackground,
    this.quoteBackground,
  });

  /// The default mapping of [tokens] onto the roles: the accent for links and
  /// mentions, translucent text and accent tints behind code, spoilers and
  /// quotes.
  factory ComposerEntityStyles.fromTokens(ComposerTokens tokens) =>
      ComposerEntityStyles(
        link: tokens.cursor,
        mention: tokens.cursor,
        codeBackground: tokens.text.withValues(alpha: 0.1),
        spoilerBackground: tokens.text.withValues(alpha: 0.18),
        quoteBackground: tokens.replyLine.withValues(alpha: 0.12),
      );

  /// Text colour of a link.
  final Color? link;

  /// Text colour of a mention.
  final Color? mention;

  /// Fill behind inline code.
  final Color? codeBackground;

  /// Fill behind a spoiler: the field shows the text, marked.
  final Color? spoilerBackground;

  /// Fill behind a quote.
  final Color? quoteBackground;

  @override
  bool operator ==(Object other) =>
      other is ComposerEntityStyles &&
      other.link == link &&
      other.mention == mention &&
      other.codeBackground == codeBackground &&
      other.spoilerBackground == spoilerBackground &&
      other.quoteBackground == quoteBackground;

  @override
  int get hashCode => Object.hash(
    link,
    mention,
    codeBackground,
    spoilerBackground,
    quoteBackground,
  );
}
