import 'package:bulletins/src/view/bulletin_builders.dart';
import 'package:bulletins/src/view/bulletin_message.dart';
import 'package:flutter/widgets.dart';

/// The reference desktop client's toast drawn as a bulletin: the builders to
/// pair with `BulletinPolicy.desktop()` and the `BulletinTokens.referenceDesktop`
/// colours.
///
/// The frame is the stock flat card (the toast is a plain rounded fill with
/// no shadow). The content differs from the stock one the way the toolkit's
/// toast lays out:
///
/// - the title is the bold first line of one text block that wraps, not a
///   line of its own; the block takes up to [maxLines] lines when the
///   bulletin names none (the stock content takes one, or two under a
///   title);
/// - a leading icon sits in a slot that takes the place of the start
///   padding, so an icon toast starts at the icon's own 12 px gap.
abstract final class DesktopBulletinBuilders {
  /// The most lines of a toast's text when the bulletin names none (the
  /// toolkit's `Config::maxlines`).
  static const int maxLines = 16;

  /// The desktop builders, with the host's own builders for the parts that
  /// have them: [animation] and [thumbnail] resolve a leading source (the
  /// reference's 20 px Lottie icons), [leading] and [action] replace those
  /// parts, and [frame] the card's surface.
  ///
  /// Give every builder here rather than through `copyWith` on the result:
  /// the content reads the builders it was made with.
  static BulletinBuilders create({
    BulletinFrameBuilder? frame,
    BulletinPartBuilder? leading,
    BulletinPartBuilder? action,
    BulletinSourceBuilder? animation,
    BulletinSourceBuilder? thumbnail,
  }) {
    late final BulletinBuilders builders;
    return builders = BulletinBuilders(
      frame: frame,
      leading: leading,
      action: action,
      animation: animation,
      thumbnail: thumbnail,
      content: (context, view) => content(context, view, builders),
    );
  }

  /// The toast's content: the leading slot, the text block (a bold title
  /// line, then the message with its links), and the action, in a row.
  static Widget content(
    BuildContext context,
    BulletinView view,
    BulletinBuilders builders,
  ) {
    final bulletin = view.bulletin;
    final policy = view.policy;
    final padding = policy.contentPadding;
    final style = TextStyle(
      color: view.tokens.foreground,
      fontSize: policy.messageTextSize,
    );
    final text = ExcludeSemantics(
      child: BulletinMessage(
        message: bulletin.message,
        links: bulletin.links,
        linkColor: view.tokens.accent,
        maxLines: bulletin.maxLines ?? maxLines,
        style: style,
        prefix: switch (bulletin.title) {
          final title? => TextSpan(
            text: '$title\n',
            style: TextStyle(
              fontSize: policy.titleTextSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          null => null,
        },
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        bulletin.leading == null ? padding.left : 0,
        padding.top,
        padding.right,
        padding.bottom,
      ),
      child: Row(
        children: [
          if (bulletin.leading != null)
            BulletinLeadingSlot(
              width: policy.leadingWidth,
              child: switch (builders.leading) {
                final leading? => leading(context, view),
                null => BulletinBuilders.stockLeading(context, view, builders),
              },
            ),
          Expanded(child: text),
          if (bulletin.action != null)
            (builders.action ?? BulletinBuilders.stockAction)(context, view),
        ],
      ),
    );
  }
}
